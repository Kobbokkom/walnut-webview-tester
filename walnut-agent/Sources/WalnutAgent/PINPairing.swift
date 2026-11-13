import Foundation
import Network
import WalnutPairing

enum PINPairing {
    static func pair(code: String, usb: USBOptions?) async throws -> Pairing {
        guard PairingWire.isCode(code) else { throw PairingHandshakeError.invalidCode }
        let bridge = DeviceBridge(usb: usb)
        defer { withExtendedLifetime(bridge) {} }
        let handshake = try PairingHandshake(role: .client, code: code, context: PairingWire.context)
        if let forwarded = try bridge.usbEndpoint(devicePort: PairingWire.port) {
            return try await exchange(handshake, endpoint: forwarded, usesUSB: true, needsApproval: true)
        }
        let service = try await chooseService()
        let endpoint = NWEndpoint.service(name: service, type: PairingWire.serviceType, domain: "local.", interface: nil)
        let pairing = try await exchange(handshake, endpoint: endpoint, usesUSB: false, needsApproval: true)
        guard pairing.serviceName == service else { throw PairingHandshakeError.invalidGrant }
        return pairing
    }

    static func resume(_ pairing: Pairing, using bridge: DeviceBridge) async throws -> Pairing {
        let handshake = try PairingHandshake(role: .client, secret: pairing.key, context: PairingWire.rememberedContext)
        let forwarded = try bridge.usbEndpoint(devicePort: pairing.port)
        let endpoint = forwarded ?? .service(
            name: pairing.serviceName, type: PairingWire.rememberedServiceType, domain: "local.", interface: nil
        )
        do {
            let command = try await exchange(handshake, endpoint: endpoint, usesUSB: forwarded != nil, needsApproval: false)
            guard command.version == 1 else { throw PairingHandshakeError.invalidGrant }
            return command
        } catch {
            try Task.checkCancellation()
            throw AgentError("Could not reconnect to Walnut. Keep Walnut open on your iPhone. If automatic connection is off, "
                + "tap Start connection in Mac Agent. If you forgot the Mac, pair again. (\(error.localizedDescription))")
        }
    }

    private static func exchange(
        _ handshake: PairingHandshake, endpoint: NWEndpoint, usesUSB: Bool, needsApproval: Bool
    ) async throws -> Pairing {
        var generator = SystemRandomNumberGenerator()
        let nonce = Data((0..<PairingWire.nonceSize).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        let commitment = try PairingWire.commitment(message: handshake.message, nonce: nonce)
        let hello = try frame(PairingWire.Hello(commitment: commitment))
        let firstConnection = BridgeExchange(to: endpoint, using: .tcp, responseLimit: PairingWire.maximumFrame)
        let connection: BridgeExchange
        let challenge: Data
        do {
            challenge = try await firstConnection.run(hello, timeout: 8, reportsBeforeSend: true)
            connection = firstConnection
        } catch let error as BridgeExchange.BeforeSendError {
            guard usesUSB, (error.underlying as? NWError) == .posix(.ECONNREFUSED) else { throw error.underlying }
            // iproxy may still be starting. The first connection never sent the commitment.
            try await Task.sleep(for: .milliseconds(250))
            connection = BridgeExchange(to: endpoint, using: .tcp, responseLimit: PairingWire.maximumFrame)
            challenge = try await connection.run(hello, timeout: 8)
        }
        let peer = try JSONDecoder().decode(PairingWire.Challenge.self, from: challenge)
        let keys = try handshake.finish(peer: peer.message)
        if needsApproval {
            let instruction = "Confirmation number: \(keys.verificationCode)\nApprove pairing on your iPhone only if the confirmation number matches.\n"
            FileHandle.standardError.write(Data(instruction.utf8))
        }
        let proof = PairingWire.Proof(message: handshake.message, nonce: nonce, proof: keys.clientProof)
        let reply: Data
        do {
            reply = try await connection.run(frame(proof), timeout: needsApproval ? 55 : 8)
        } catch where needsApproval {
            try Task.checkCancellation()
            throw AgentError("Pairing was not approved. Check the code and start a new pairing attempt on your iPhone.")
        }
        let grant = try JSONDecoder().decode(PairingWire.Grant.self, from: reply)
        return try Pairing.decode(keys.open(grant.payload))
    }

    private static func frame<Message: Encodable>(_ message: Message) throws -> Data {
        var data = try JSONEncoder().encode(message)
        guard data.count <= PairingWire.maximumFrame else { throw PairingHandshakeError.exchangeFailed }
        data.append(0x0A)
        return data
    }

    private static func chooseService() async throws -> String {
        let names = try await discoverServices()
        if names.count == 1, let name = names.first { return name }
        guard !names.isEmpty else {
            throw AgentError("No Walnut pairing session found. Open Mac Agent on the iPhone and check Local Network access on both devices.")
        }
        let choices = names.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        FileHandle.standardError.write(Data("Select the pairing name shown on your iPhone:\n\(choices)\nSelection: ".utf8))
        guard let input = readLine(), let selection = Int(input), (1...names.count).contains(selection) else {
            throw AgentError("Run `walnut-agent pair` again and enter a number from the list.")
        }
        return names[selection - 1]
    }

    private static func discoverServices() async throws -> [String] {
        let browser = NWBrowser(for: .bonjour(type: PairingWire.serviceType, domain: "local."), using: .tcp)
        let queue = DispatchQueue(label: "walnut-agent.pairing-discovery")
        return try await withCheckedThrowingContinuation { continuation in
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 2) {
                defer { browser.cancel() }
                switch browser.state {
                case .failed(let error), .waiting(let error):
                    if error == .dns(-65570) {
                        continuation.resume(throwing: AgentError("Allow Walnut Agent in Mac System Settings → Privacy & Security → Local Network and retry."))
                    } else {
                        continuation.resume(throwing: error)
                    }
                default:
                    let names = browser.browseResults.compactMap { result -> String? in
                        guard case let .service(name, type, _, _) = result.endpoint, type == PairingWire.serviceType,
                              (1...63).contains(name.utf8.count),
                              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
                        return name
                    }
                    continuation.resume(returning: Set(names).sorted())
                }
            }
        }
    }
}
