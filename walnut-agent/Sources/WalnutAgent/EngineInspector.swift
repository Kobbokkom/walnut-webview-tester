import CoreFoundation
import Darwin
import Foundation

enum EngineInspector {
    private static let tool = "agent_engine_inspection"
    private static let package = "pymobiledevice3==11.51.0"

    static func run(arguments: [String]) async throws {
        let options = try Options(arguments)
        let executable = try findUV()
        let bridge = DeviceBridge(usb: options.usb ? USBOptions(udid: options.udid) : nil)
        do {
            let grant = try await authorize(bridge)
            do {
                try await runAdapter(executable, options: options, grant: grant, bridge: bridge)
            } catch {
                await end(grant, bridge: bridge)
                throw error
            }
            await end(grant, bridge: bridge)
        } catch {
            await bridge.shutdown()
            throw error
        }
        await bridge.shutdown()
    }

    private struct Grant {
        let id: String
        let nonce: String
        let bundleId: String
    }

    private static func authorize(_ bridge: DeviceBridge) async throws -> Grant {
        let response = try await bridge.call(tool, arguments: ["action": "authorize"]) as? [String: Any]
        guard let data = response?["data"] as? [String: Any], let id = data["grantId"] as? String,
              let nonce = data["nonce"] as? String, let bundle = data["bundleId"] as? String,
              UUID(uuidString: id) != nil, UUID(uuidString: nonce) != nil,
              ["com.kobbokkom.wina", "com.kobbokkom.wina.qa"].contains(bundle) else {
            throw AgentError("Walnut returned an invalid Web Inspector grant.")
        }
        return Grant(id: id, nonce: nonce, bundleId: bundle)
    }

    private static func end(_ grant: Grant, bridge: DeviceBridge) async {
        _ = try? await bridge.call(tool, arguments: ["action": "end", "grantId": grant.id])
    }

    private enum Event {
        case command(Result<Data, AgentError>)
        case packet(Result<Data, AgentError>)
        case inputClosed
        case adapterClosed
        case checkScope
    }

    private static func runAdapter(_ executable: URL, options: Options, grant: Grant, bridge: DeviceBridge) async throws {
        let process = Process()
        let requests = Pipe()
        let replies = Pipe()
        process.executableURL = executable
        process.arguments = ["run", "--no-project", "--with", package, "--", "python", "-I", "-c", InspectorProgram.source]
            + (options.wifi ? ["--mobdev2"] : [])
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("PYMOBILEDEVICE3_") && $0.key != "USBMUXD_SOCKET_ADDRESS" }
        process.standardInput = requests
        process.standardOutput = replies
        process.standardError = FileHandle.standardError
        signal(SIGPIPE, SIG_IGN)
        try process.run()
        let writer = requests.fileHandleForWriting
        do {
            try write(["version": 1, "udid": options.udid, "bundleId": grant.bundleId, "nonce": grant.nonce], to: writer)
            try await relay(replies.fileHandleForReading, writer: writer, grant: grant, bridge: bridge)
            await stop(process, input: writer)
            guard !process.isRunning, process.terminationStatus == 0 else {
                throw AgentError("Web Inspector stopped. See the adapter error above.")
            }
        } catch {
            await stop(process, input: writer)
            throw error
        }
    }

    private static func relay(_ output: FileHandle, writer: FileHandle, grant: Grant, bridge: DeviceBridge) async throws {
        let (events, continuation) = AsyncThrowingStream<Event, Error>.makeStream()
        let commandReady = DispatchSemaphore(value: 1)
        let packetReady = DispatchSemaphore(value: 1)
        let scopeReady = DispatchSemaphore(value: 1)
        read(CLILineReader(), into: continuation, permit: commandReady, command: true)
        read(CLILineReader(descriptor: output.fileDescriptor, limit: 8 * 1024 * 1024,
                           oversizedError: AgentError("Web Inspector output exceeded 8 MiB.")),
             into: continuation, permit: packetReady, command: false)
        let canQueueScopeCheck = { scopeReady.wait(timeout: .now()) == .success }
        let heartbeat = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                if canQueueScopeCheck(),
                   case .terminated = continuation.yield(.checkScope) {
                    scopeReady.signal()
                    return
                }
            }
        }
        defer {
            heartbeat.cancel()
            continuation.finish()
            commandReady.signal()
            packetReady.signal()
            scopeReady.signal()
        }
        for try await event in events {
            switch event {
            case .command(let frame):
                defer { commandReady.signal() }
                try await send(frame, writer: writer, grant: grant, bridge: bridge)
            case .packet(let frame):
                defer { packetReady.signal() }
                let data = try frame.get()
                guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
                    throw AgentError("Web Inspector returned an invalid packet.")
                }
                try await validate(grant, bridge: bridge, command: nil)
                try writeFrame(data, to: STDOUT_FILENO)
            case .checkScope:
                defer { scopeReady.signal() }
                try await validate(grant, bridge: bridge, command: nil)
            case .inputClosed:
                try? writer.close()
            case .adapterClosed:
                return
            }
        }
        try Task.checkCancellation()
        throw AgentError("Web Inspector stream closed unexpectedly.")
    }

    private static func read(
        _ reader: CLILineReader, into continuation: AsyncThrowingStream<Event, Error>.Continuation,
        permit: DispatchSemaphore, command: Bool
    ) {
        DispatchQueue(label: command ? "walnut-agent.inspector.input" : "walnut-agent.inspector.output").async {
            do {
                while true {
                    permit.wait()
                    guard let frame = try reader.next() else {
                        permit.signal()
                        continuation.yield(command ? .inputClosed : .adapterClosed)
                        return
                    }
                    if case .terminated = continuation.yield(command ? .command(frame) : .packet(frame)) {
                        permit.signal()
                        return
                    }
                }
            } catch {
                permit.signal()
                continuation.finish(throwing: error)
            }
        }
    }

    private static func send(_ frame: Result<Data, AgentError>, writer: FileHandle, grant: Grant, bridge: DeviceBridge) async throws {
        var id: Any = NSNull()
        let data: Data
        do {
            data = try frame.get()
            let command = try Command(data)
            id = command.id
            try await validate(grant, bridge: bridge, command: command)
        } catch {
            try write(["id": id, "error": ["code": -32000, "message": error.localizedDescription]], to: .standardOutput)
            return
        }
        try writeFrame(data, to: writer.fileDescriptor)
    }

    private static func validate(_ grant: Grant, bridge: DeviceBridge, command: Command?) async throws {
        var arguments: [String: Any] = ["action": "validate", "grantId": grant.id]
        if let command {
            arguments["method"] = command.method
            arguments["params"] = command.params
        }
        let response = try await bridge.call(tool, arguments: arguments) as? [String: Any]
        guard let data = response?["data"] as? [String: Any], data["valid"] as? Bool == true else {
            throw AgentError("The authorized Walnut document is no longer available.")
        }
    }

    private static func stop(_ process: Process, input: FileHandle) async {
        try? input.close()
        for _ in 0..<60 where process.isRunning { try? await Task.sleep(for: .milliseconds(50)) }
        if process.isRunning {
            process.terminate()
            for _ in 0..<60 where process.isRunning { try? await Task.sleep(for: .milliseconds(50)) }
        }
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }

    private static func write(_ object: [String: Any], to handle: FileHandle) throws {
        try writeFrame(JSONSerialization.data(withJSONObject: object), to: handle.fileDescriptor)
    }

    static func writeFrame(_ payload: Data, to descriptor: Int32, timeoutMs: Int32 = 2_000) throws {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags != -1, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != -1 else {
            throw AgentError("Could not write to the Web Inspector stream.")
        }
        defer { _ = fcntl(descriptor, F_SETFL, flags) }
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(1, timeoutMs)) * 1_000_000
        try (payload + Data([10])).withUnsafeBytes { buffer in
            guard let address = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let now = DispatchTime.now().uptimeNanoseconds
                guard now < deadline else { throw AgentError("The Web Inspector stream stopped accepting output.") }
                var ready = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
                let remainingMs = Int32(max(1, (deadline - now) / 1_000_000))
                let count = poll(&ready, 1, remainingMs)
                if count == -1, errno == EINTR { continue }
                guard count > 0, ready.revents & Int16(POLLOUT) != 0 else {
                    throw AgentError("The Web Inspector stream stopped accepting output.")
                }
                let written = Darwin.write(descriptor, address.advanced(by: offset), buffer.count - offset)
                if written < 0, [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
                guard written > 0 else { throw AgentError("Could not write to the Web Inspector stream.") }
                offset += written
            }
        }
    }

    private static func findUV() throws -> URL {
        let paths = ProcessInfo.processInfo.environment["PATH", default: ""] + ":/opt/homebrew/bin:/usr/local/bin"
        for directory in paths.split(separator: ":") {
            let executable = URL(fileURLWithPath: String(directory)).appendingPathComponent("uv")
            if FileManager.default.isExecutableFile(atPath: executable.path) { return executable }
        }
        throw AgentError("Web Inspector requires uv on the Mac. Install it with `brew install uv`.")
    }

    struct Options {
        let udid: String
        let usb: Bool
        let wifi: Bool

        init(_ arguments: [String]) throws {
            var values = arguments
            let mode = values.last.flatMap { ["--usb", "--wifi"].contains($0) ? $0 : nil }
            if mode != nil { values.removeLast() }
            guard values.count == 2, let udid = try CLI.parseUSB(["--usb"] + values)?.udid else {
                throw AgentError("Use `walnut-agent inspect --udid UDID [--usb | --wifi]`.")
            }
            self.udid = udid
            usb = mode == "--usb"
            wifi = mode == "--wifi"
        }
    }

    struct Command {
        let id: Int
        let method: String
        let params: [String: Any]

        init(_ data: Data) throws {
            guard let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  request.keys.allSatisfy({ ["id", "method", "params"].contains($0) }),
                  let number = request["id"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let id = request["id"] as? Int, (1...Int(Int32.max)).contains(id),
                  let method = request["method"] as? String, (1...80).contains(method.utf8.count),
                  let params = (request["params"] ?? [:]) as? [String: Any] else {
                throw AgentError("Send a CDP command with an integer id, method, and optional params object.")
            }
            self.id = id
            self.method = method
            self.params = params
        }
    }
}
