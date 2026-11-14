import Foundation
import Network
import Observation
import Security
import UIKit
import WalnutPairing

@Observable
@MainActor
final class AgentSession {
    static let autoConnectKey = "macAgentAutoConnect"

    private(set) var pairingCode: String?
    private(set) var pairingDeviceName: String?
    private(set) var isConnected = false
    private var hasConnectedMac = false
    private(set) var isRunning = false
    private(set) var connectionError: String?
    private(set) var pairingStorageError: String?
    var approval: AgentApprovalGate.Request? { approvals.pending }

    private let approvals = AgentApprovalGate()
    private let pinListener = AgentPINListener()
    private let rememberedListener = AgentPINListener()
    private var rememberedPairing: AgentRememberedPairing?
    var hasRememberedMac: Bool { rememberedPairing != nil }
    var reconnectError: String? { isRunning && hasRememberedMac ? rememberedListener.error : nil }
    var isPairingReady: Bool { hasRememberedMac ? rememberedListener.isReady : hasConnectedMac }
    var isPairingAvailable: Bool { pinListener.isPairingAvailable }
    var pairingError: String? { pinListener.error ?? pairingStartError }
    var hasPairingGrant: Bool { hasRememberedMac || hasConnectedMac }
    private var pairingStartError: String?
    @ObservationIgnored private var pairingPayload: Data?
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var peer: NWConnection?
    @ObservationIgnored private var handshake: NWConnection?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var isReceiving = false
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var onDisconnect: (() -> Void)?

    typealias Handler = @MainActor (String, [String: Any]) async throws -> Any
    private static weak var activeSession: AgentSession?
    private static let maxRequest = 256 * 1024
    static let maxResponse = 16 * 1024 * 1024

    func start(rememberedOnly: Bool = false, handler: @escaping Handler, onDisconnect: @escaping () -> Void) {
        guard !isRunning else { return }
        guard Self.activeSession == nil else {
            if !rememberedOnly { connectionError = "Stop the Mac Agent connection in the other Walnut window first." }
            return
        }
        connectionError = nil
        do {
            try loadRememberedMac()
            guard !rememberedOnly || hasRememberedMac else { return }
            let key = try Self.makeKey()
            let name = Self.makeServiceName()
            let listener = try NWListener(using: Self.parameters(key: key))
            listener.service = NWListener.Service(name: name, type: "_walnut-agent._tcp")
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor [weak self, weak listener] in
                    guard let self, let listener, self.listener === listener else { return }
                    if case .ready = state, let port = listener.port?.rawValue,
                       port == PairingWire.port || port == PairingWire.rememberedPort {
                        // Keep both fixed bootstrap ports free for pairing and reconnect.
                        self.stop()
                        self.start(rememberedOnly: rememberedOnly, handler: handler, onDisconnect: onDisconnect)
                        return
                    }
                    self.update(state, name: name, key: key, port: listener.port, rememberedOnly: rememberedOnly)
                }
            }
            listener.newConnectionHandler = { [weak self, weak listener] connection in
                Task { @MainActor [weak self, weak listener] in
                    guard let self, let listener, self.listener === listener else {
                        connection.cancel()
                        return
                    }
                    self.accept(connection, handler: handler)
                }
            }
            self.onDisconnect = onDisconnect
            self.listener = listener
            isRunning = true
            Self.activeSession = self
            listener.start(queue: .main)
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func stopManually() {
        UserDefaults.standard.set(false, forKey: Self.autoConnectKey)
        stop()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if Self.activeSession === self { Self.activeSession = nil }
        pairingCode = nil
        pairingDeviceName = nil
        pairingPayload = nil
        pairingStartError = nil
        hasConnectedMac = false
        pinListener.stop()
        rememberedListener.stop()
        if let approval { approvals.resolve(approval.id, allow: false) }
        listener?.cancel()
        listener = nil
        handshake?.cancel()
        handshake = nil
        if let peer { disconnect(peer) } else { onDisconnect?() }
        onDisconnect = nil
    }

    func authorize(_ message: String) async -> Bool {
        await authorize(message, preview: nil)
    }

    func authorize(_ message: String, preview: UIImage?) async -> Bool {
        guard isConnected, await approvals.authorize(message, preview: preview) else { return false }
        return isConnected && !Task.isCancelled
    }

    func resolveApproval(_ id: UUID, _ allow: Bool) {
        guard let approval, approval.id == id else { return }
        let canAllow = approval.pairingConfirmation == nil ? isConnected : isPairingAvailable && !isConnected
        approvals.resolve(id, allow: allow && isRunning && canAllow)
    }

    func startPairing() {
        guard !isConnected, !hasRememberedMac, !isPairingAvailable, let pairingPayload else { return }
        pairingStartError = nil
        do {
            let candidate = AgentRememberedPairing(key: try Self.makeKey(), serviceName: Self.makeServiceName())
            let grant = try Self.encodePairing(
                version: 2, serviceName: candidate.serviceName, port: PairingWire.rememberedPort, key: candidate.key
            )
            try pinListener.start(
                serviceName: candidate.serviceName,
                payload: grant,
                commit: { [weak self] in
                    guard let self, isRunning, !isConnected else { throw CancellationError() }
                    try remember(candidate, commandPayload: pairingPayload)
                },
                authorize: { [weak self] verification in
                    guard let self, isRunning, !isConnected else { return false }
                    let message = String(localized: "Allow the connection only if this number matches your Mac.")
                    guard await approvals.authorize(message, pairingConfirmation: verification) else { return false }
                    return isRunning && !isConnected && !Task.isCancelled
                }
            )
            pairingDeviceName = candidate.serviceName
        } catch {
            pairingStartError = String(localized: "Could not start pairing. Try again or share a pairing file.")
        }
    }

    func refreshRememberedMac() {
        guard !isRunning else { return }
        try? loadRememberedMac()
    }

    func forgetRememberedMac() {
        if let active = Self.activeSession, active !== self {
            active.stop()
            active.rememberedPairing = nil
        }
        stopManually()
        rememberedPairing = nil
        do {
            try AgentRememberedPairing.forget()
            pairingStorageError = nil
            connectionError = nil
        } catch {
            pairingStorageError = String(localized: "Could not forget the saved Mac. Unlock the iPhone and try again.")
        }
    }

    private func loadRememberedMac() throws {
        do {
            rememberedPairing = try AgentRememberedPairing.load()
            pairingStorageError = nil
        } catch {
            rememberedPairing = nil
            pairingStorageError = String(localized: "Could not read the saved Mac. Unlock the iPhone or forget the pairing.")
            throw error
        }
    }

    private func remember(_ candidate: AgentRememberedPairing, commandPayload: Data) throws {
        try startRememberedListener(candidate, commandPayload: commandPayload)
        do {
            try candidate.save()
        } catch {
            rememberedListener.stop()
            throw error
        }
        rememberedPairing = candidate
    }

    private func startRememberedListener(_ pairing: AgentRememberedPairing, commandPayload: Data) throws {
        try rememberedListener.startRemembered(
            serviceName: pairing.serviceName, secret: pairing.key, payload: commandPayload
        )
    }

    private func update(_ state: NWListener.State, name: String, key: Data, port: NWEndpoint.Port?, rememberedOnly: Bool) {
        switch state {
        case .ready:
            connectionError = nil
            guard let port, pairingPayload == nil else { return }
            do {
                let bytes = try Self.encodePairing(version: 1, serviceName: name, port: port.rawValue, key: key)
                pairingPayload = bytes
                if !rememberedOnly {
                    let token = bytes.base64EncodedString()
                        .replacingOccurrences(of: "+", with: "-")
                        .replacingOccurrences(of: "/", with: "_")
                        .replacingOccurrences(of: "=", with: "")
                    pairingCode = "walnut-agent:\(token)"
                }
                if let rememberedPairing {
                    try startRememberedListener(rememberedPairing, commandPayload: bytes)
                } else {
                    startPairing()
                }
            } catch {
                stop()
                connectionError = error.localizedDescription
            }
        case .waiting(let error):
            connectionError = error.localizedDescription
        case .failed(let error):
            connectionError = error.localizedDescription
            stop()
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection, handler: @escaping Handler) {
        guard peer == nil, handshake == nil else {
            connection.cancel()
            return
        }
        handshake = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection else { return }
                switch state {
                case .ready where self.handshake === connection:
                    self.handshake = nil
                    self.peer = connection
                    self.hasConnectedMac = true
                    self.isConnected = true
                    self.pinListener.stop()
                    self.receive(connection, handler: handler)
                case .failed, .cancelled:
                    self.disconnect(connection)
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        Task { [weak self, weak connection] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, let connection, self.handshake === connection else { return }
            self.disconnect(connection)
        }
    }

    private func receive(_ connection: NWConnection, handler: @escaping Handler) {
        guard peer === connection else { return }
        if operation == nil, let end = buffer.firstIndex(of: 10) {
            let frame = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            // An empty frame lets the companion release the peer before it exits.
            guard !frame.isEmpty, frame.count <= Self.maxRequest else { disconnect(connection); return }
            process(frame, connection: connection, handler: handler)
            receive(connection, handler: handler)
            return
        }
        guard buffer.count <= Self.maxRequest else { disconnect(connection); return }
        guard !isReceiving else { return }
        isReceiving = true
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self, weak connection] data, _, done, error in
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection, self.peer === connection else { return }
                self.isReceiving = false
                guard error == nil, !done, let data else { self.disconnect(connection); return }
                self.buffer.append(data)
                self.receive(connection, handler: handler)
            }
        }
    }

    private func process(_ frame: Data, connection: NWConnection, handler: @escaping Handler) {
        operation = Task { [weak self, weak connection] in
            guard let self, let connection else { return }
            guard let (request, arguments) = try? AgentRequest.decode(frame) else {
                self.disconnect(connection)
                return
            }
            let payload: [String: Any]
            do {
                let result = try await handler(request.tool, arguments)
                payload = ["id": request.id, "result": result]
            } catch {
                payload = ["id": request.id, "error": error.localizedDescription]
            }
            guard !Task.isCancelled, self.peer === connection else { return }
            let response = JSONSerialization.isValidJSONObject(payload)
                ? (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                : Data()
            let bytes: Data
            if response.isEmpty || response.count >= Self.maxResponse {
                bytes = (try? JSONSerialization.data(withJSONObject: [
                    "id": request.id, "error": "Result is not serializable or exceeds the limit. Narrow the query."
                ])) ?? Data()
            } else {
                bytes = response
            }
            connection.send(content: bytes + Data([10]), completion: .contentProcessed { [weak self, weak connection] error in
                Task { @MainActor [weak self, weak connection] in
                    guard let self, let connection, self.peer === connection else { return }
                    self.operation = nil
                    if error == nil {
                        self.receive(connection, handler: handler)
                    } else {
                        self.disconnect(connection)
                    }
                }
            })
        }
    }

    private func disconnect(_ connection: NWConnection) {
        connection.cancel()
        if handshake === connection { handshake = nil }
        guard peer === connection else { return }
        peer = nil
        isConnected = false
        buffer.removeAll()
        isReceiving = false
        operation?.cancel()
        operation = nil
        if let approval { approvals.resolve(approval.id, allow: false) }
        onDisconnect?()
    }

    private static func makeKey() throws -> Data {
        var key = Data(count: 32)
        let status = key.withUnsafeMutableBytes { bytes in
            guard let address = bytes.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, bytes.count, address)
        }
        guard status == errSecSuccess else { throw AgentError("Could not generate a pairing key.") }
        return key
    }

    private static func makeServiceName() -> String {
        "Walnut-\(UUID().uuidString.prefix(12))"
    }

    private static func encodePairing(version: Int, serviceName: String, port: UInt16, key: Data) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "version": version, "serviceName": serviceName, "port": Int(port), "key": key.base64EncodedString()
        ])
    }

    private static func parameters(key: Data) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_tls_resumption_enabled(options, false)
        sec_protocol_options_set_tls_tickets_enabled(options, false)
        let identity = Data("walnut-agent-v1".utf8)
        sec_protocol_options_add_pre_shared_key(
            options,
            key.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData,
            identity.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData
        )
        if let cipher = tls_ciphersuite_t(rawValue: TLS_PSK_WITH_AES_128_GCM_SHA256) {
            sec_protocol_options_append_tls_ciphersuite(options, cipher)
        }
        return NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    }
}
