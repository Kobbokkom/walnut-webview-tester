import Foundation
import Network
import Security

typealias AgentToolCall = @Sendable (String, [String: Any]) async throws -> Any

struct USBOptions {
    var localPort: UInt16?
    var udid: String?
}

// The CLI session and MCP request queue serialize calls to the active connection and USB proxy.
final class DeviceBridge: @unchecked Sendable {
    static let requestLimit = 256 * 1024
    private let usb: USBOptions?
    private var active: (pairing: Pairing, command: Pairing, exchange: BridgeExchange)?
    private var proxy: Process?
    private var proxyPort: UInt16?

    init(usb: USBOptions?) {
        self.usb = usb
    }

    deinit {
        if let proxy, proxy.isRunning { proxy.terminate() }
    }

    func shutdown() async {
        if let active { await active.exchange.close() }
        active = nil
        if let proxy, proxy.isRunning { proxy.terminate() }
        proxy = nil
        proxyPort = nil
    }

    func call(_ tool: String, arguments: [String: Any] = [:]) async throws -> Any {
        try Task.checkCancellation()
        let pairing = try Pairing.load(from: Pairing.file)
        let id = UUID().uuidString
        let payload = try Self.request(id: id, tool: tool, arguments: arguments)
        let timeout: TimeInterval
        switch tool {
        case "walnut_capabilities": timeout = 7
        case "agent_engine_inspection" where arguments["method"] == nil && arguments["action"] as? String != "authorize":
            timeout = 5
        case "walnut_screenshot": timeout = 125 // SafariVC can require two approvals and the system picker.
        case "walnut_browser" where arguments["cleanStart"] as? Bool == true: timeout = 120
        default: timeout = 90
        }
        let reply: Data
        let wasCached = active?.pairing == pairing
        do {
            do {
                reply = try await send(payload, pairing: pairing, timeout: timeout, retryUSBStartup: !wasCached)
            } catch is BridgeExchange.BeforeSendError where pairing.version == 2 && wasCached {
                active = nil
                try Task.checkCancellation()
                // Only a request which never started sending can be retried after reconnecting.
                reply = try await send(payload, pairing: pairing, timeout: timeout, retryUSBStartup: true)
            }
        } catch {
            active = nil
            throw (error as? BridgeExchange.BeforeSendError)?.underlying ?? error
        }
        return try Self.result(reply, for: id)
    }

    private func send(_ payload: Data, pairing: Pairing, timeout: TimeInterval, retryUSBStartup: Bool) async throws -> Data {
        let exchange = try await connect(pairing)
        do {
            return try await exchange.run(payload, timeout: timeout, reportsBeforeSend: true)
        } catch let error as BridgeExchange.BeforeSendError {
            guard retryUSBStartup, usb != nil, (error.underlying as? NWError) == .posix(.ECONNREFUSED),
                  let command = active?.command else { throw error }
            // Preserve the new iproxy process and the session parameters it forwards to.
            active = nil
            try await Task.sleep(for: .milliseconds(250))
            return try await connectCommand(command, saved: pairing).run(payload, timeout: timeout)
        }
    }

    private func connect(_ pairing: Pairing) async throws -> BridgeExchange {
        if let active, active.pairing == pairing { return active.exchange }
        active = nil
        let command = pairing.version == 2 ? try await PINPairing.resume(pairing, using: self) : pairing
        return try connectCommand(command, saved: pairing)
    }

    private func connectCommand(_ command: Pairing, saved: Pairing) throws -> BridgeExchange {
        let endpoint: NWEndpoint
        if let forwarded = try usbEndpoint(devicePort: command.port) {
            endpoint = forwarded
        } else {
            endpoint = .service(name: command.serviceName, type: "_walnut-agent._tcp", domain: "local.", interface: nil)
        }
        let exchange = BridgeExchange(to: endpoint, using: Self.parameters(key: command.key))
        active = (saved, command, exchange)
        return exchange
    }

    func usbEndpoint(devicePort: UInt16) throws -> NWEndpoint? {
        guard let usb else { return nil }
        let port = try startUSBProxy(usb, devicePort: devicePort)
        return .hostPort(host: "127.0.0.1", port: port)
    }

    static func request(id: String, tool: String, arguments: [String: Any]) throws -> Data {
        var payload = try JSONSerialization.data(withJSONObject: ["id": id, "tool": tool, "arguments": arguments])
        guard payload.count <= requestLimit else { throw AgentError("The Walnut request exceeds 256 KiB.") }
        payload.append(0x0A)
        return payload
    }

    static func result(_ data: Data, for id: String) throws -> Any {
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              response["id"] as? String == id else {
            throw AgentError("Walnut returned an invalid response.")
        }
        switch (response["result"], response["error"]) {
        case (.some(let result), .none): return result
        case (.none, let error as String): throw AgentError(error)
        default: throw AgentError("Walnut returned an invalid response.")
        }
    }

    static func parameters(key: Data) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        let identity = Data("walnut-agent-v1".utf8)
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_tls_resumption_enabled(options, false)
        sec_protocol_options_set_tls_tickets_enabled(options, false)
        sec_protocol_options_add_pre_shared_key(
            options,
            key.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData,
            identity.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData
        )
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        return NWParameters(tls: tls)
    }

    private func startUSBProxy(_ options: USBOptions, devicePort: UInt16) throws -> NWEndpoint.Port {
        let localPort = options.localPort ?? devicePort
        guard let endpointPort = NWEndpoint.Port(rawValue: localPort) else {
            throw AgentError("The USB port is invalid.")
        }
        if let proxy, proxy.isRunning {
            if proxyPort == devicePort { return endpointPort }
            proxy.terminate()
            proxy.waitUntilExit()
        }
        let searchPath = ProcessInfo.processInfo.environment["PATH", default: ""] + ":/opt/homebrew/bin:/usr/local/bin"
        let executables = searchPath.split(separator: ":").map { String($0) + "/iproxy" }
        guard let executable = executables.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw AgentError("USB mode requires `iproxy` from libusbmuxd. Install it with `brew install libusbmuxd`.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        var arguments = ["--local", "--source", "127.0.0.1"]
        if let udid = options.udid { arguments += ["--udid", udid] }
        process.arguments = arguments + ["\(localPort):\(devicePort)"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.standardError
        process.standardError = FileHandle.standardError
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "USBMUXD_SOCKET_ADDRESS")
        process.environment = environment
        try process.run()
        proxy = process
        proxyPort = devicePort
        return endpointPort
    }
}
