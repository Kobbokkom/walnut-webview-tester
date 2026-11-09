import Foundation
import Network
import Observation
import Security
import UIKit

@Observable
@MainActor
final class AgentSession {
    private(set) var pairingCode: String?
    private(set) var isConnected = false
    private(set) var isRunning = false
    private(set) var connectionError: String?
    var approval: AgentApprovalGate.Request? { approvals.pending }

    private let approvals = AgentApprovalGate()
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
    private static let maxResponse = 16 * 1024 * 1024

    func start(handler: @escaping Handler, onDisconnect: @escaping () -> Void) {
        guard !isRunning else { return }
        guard Self.activeSession == nil else {
            connectionError = "Stop the Mac Agent connection in the other Walnut window first."
            return
        }
        connectionError = nil
        do {
            let key = try Self.makeKey()
            let name = "Walnut-\(UUID().uuidString.prefix(12))"
            let listener = try NWListener(using: Self.parameters(key: key))
            listener.service = NWListener.Service(name: name, type: "_walnut-agent._tcp")
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor [weak self, weak listener] in
                    guard let self, let listener, self.listener === listener else { return }
                    self.update(state, name: name, key: key, port: listener.port)
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

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if Self.activeSession === self { Self.activeSession = nil }
        pairingCode = nil
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
        approvals.resolve(id, allow: allow && isConnected)
    }

    private func update(_ state: NWListener.State, name: String, key: Data, port: NWEndpoint.Port?) {
        switch state {
        case .ready:
            connectionError = nil
            guard let port else { return }
            let payload: [String: Any] = [
                "version": 1, "serviceName": name, "port": Int(port.rawValue), "key": key.base64EncodedString()
            ]
            if let bytes = try? JSONSerialization.data(withJSONObject: payload) {
                let token = bytes.base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "")
                pairingCode = "walnut-agent:\(token)"
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
                    self.isConnected = true
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
