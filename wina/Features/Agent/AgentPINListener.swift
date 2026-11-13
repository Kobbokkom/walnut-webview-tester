import Foundation
import Network
import Observation
import WalnutPairing

@Observable
@MainActor
final class AgentPINListener {
    private(set) var code: String?
    private(set) var error: String?
    private(set) var didGrant = false

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var peer: Peer?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var deadline: ContinuousClock.Instant?
    @ObservationIgnored private var attempts = 0

    private static let lifetime = Duration.seconds(120)
    private static let attemptLimit = 5

    @MainActor private final class Peer {
        enum Stage {
            case hello, proof(PairingHandshake, commitment: Data), approval, grant
        }

        let connection: NWConnection
        let payload: Data
        let authorize: @MainActor @Sendable (String) async -> Bool
        var stage = Stage.hello
        var buffer = Data()
        var timeout: Task<Void, Never>?
        var approval: Task<Void, Never>?

        init(_ connection: NWConnection, payload: Data, authorize: @escaping @MainActor @Sendable (String) async -> Bool) {
            self.connection = connection
            self.payload = payload
            self.authorize = authorize
        }
    }

    func start(serviceName: String, payload: Data, authorize: @escaping @MainActor @Sendable (String) async -> Bool) throws {
        stop()
        error = nil
        guard let port = NWEndpoint.Port(rawValue: PairingWire.port) else { throw AgentError("Invalid pairing port.") }
        let pin = String(format: "%06d", Int.random(in: 0...999_999))
        let listener = try NWListener(using: .tcp, on: port)
        listener.service = NWListener.Service(name: serviceName, type: PairingWire.serviceType)
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor [weak self, weak listener] in
                guard let self, let listener, self.listener === listener else { return }
                switch state {
                case .ready: self.code = pin
                case .failed(let error):
                    self.stop()
                    self.error = error.localizedDescription
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self, weak listener] connection in
            Task { @MainActor [weak self, weak listener] in
                guard let self, let listener, self.listener === listener else { connection.cancel(); return }
                self.accept(connection, payload: payload, authorize: authorize)
            }
        }
        self.listener = listener
        attempts = 0
        deadline = .now + Self.lifetime
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: Self.lifetime) } catch { return }
            self?.stop()
        }
        listener.start(queue: .main)
    }

    func stop() {
        didGrant = false
        stopAdvertising()
        if let peer { close(peer) }
    }

    private func stopAdvertising() {
        expiry?.cancel()
        expiry = nil
        listener?.cancel()
        listener = nil
        deadline = nil
        code = nil
    }

    private var liveCode: String? {
        guard let deadline, ContinuousClock.now < deadline else { return nil }
        return code
    }

    private func accept(_ connection: NWConnection, payload: Data, authorize: @escaping @MainActor @Sendable (String) async -> Bool) {
        guard liveCode != nil, peer == nil, attempts < Self.attemptLimit else { connection.cancel(); return }
        let peer = Peer(connection, payload: payload, authorize: authorize)
        self.peer = peer
        connection.stateUpdateHandler = { [weak self, weak peer] state in
            Task { @MainActor [weak self, weak peer] in
                guard let self, let peer, self.peer === peer else { return }
                switch state {
                case .ready: self.receive(peer)
                case .failed, .cancelled: self.close(peer)
                default: break
                }
            }
        }
        startPeerTimeout(peer)
        connection.start(queue: .main)
    }

    private func startPeerTimeout(_ peer: Peer) {
        peer.timeout?.cancel()
        peer.timeout = Task { [weak self, weak peer] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            if let peer { self?.close(peer) }
        }
    }

    private func receive(_ peer: Peer) {
        let limit = PairingWire.maximumFrame + 1
        peer.connection.receive(minimumIncompleteLength: 1, maximumLength: limit) { [weak self, weak peer] data, _, done, error in
            Task { @MainActor [weak self, weak peer] in
                guard let self, let peer, self.peer === peer else { return }
                guard error == nil, !done, let data, !data.isEmpty else { self.close(peer); return }
                switch peer.stage {
                case .approval, .grant: self.close(peer); return
                case .hello, .proof: break
                }
                peer.buffer.append(data)
                guard peer.buffer.count <= PairingWire.maximumFrame + 1 else { self.close(peer); return }
                guard let newline = peer.buffer.firstIndex(of: 10) else { self.receive(peer); return }
                guard newline == peer.buffer.index(before: peer.buffer.endIndex) else { self.close(peer); return }
                let frame = Data(peer.buffer[..<newline])
                peer.buffer.removeAll()
                do { try self.handle(frame, from: peer) } catch { self.close(peer) }
            }
        }
    }

    private func handle(_ frame: Data, from peer: Peer) throws {
        guard let pin = liveCode else { close(peer); return }
        switch peer.stage {
        case .hello:
            let hello = try JSONDecoder().decode(PairingWire.Hello.self, from: frame)
            guard hello.commitment.count == PairingWire.commitmentSize else { close(peer); return }
            attempts += 1
            let handshake = try PairingHandshake(role: .server, code: pin, context: PairingWire.context)
            peer.stage = .proof(handshake, commitment: hello.commitment)
            try send(PairingWire.Challenge(message: handshake.message), to: peer)
        case .proof(let handshake, let commitment):
            let proof = try JSONDecoder().decode(PairingWire.Proof.self, from: frame)
            guard proof.message.count == PairingWire.messageSize, proof.nonce.count == PairingWire.nonceSize,
                  try PairingWire.commitment(message: proof.message, nonce: proof.nonce) == commitment else {
                close(peer)
                return
            }
            let keys = try handshake.finish(peer: proof.message)
            guard keys.verifyClientProof(proof.proof) else { close(peer); return }
            peer.timeout?.cancel()
            peer.stage = .approval
            receive(peer)
            peer.approval = Task { [weak self, weak peer] in
                guard let self, let peer else { return }
                let allowed = await peer.authorize(keys.verificationCode)
                guard self.peer === peer else { return }
                guard allowed, !Task.isCancelled, self.liveCode != nil else { self.close(peer); return }
                do {
                    let grant = PairingWire.Grant(payload: try keys.seal(peer.payload))
                    peer.stage = .grant
                    self.didGrant = true
                    self.stopAdvertising()
                    self.startPeerTimeout(peer)
                    try self.send(grant, to: peer)
                } catch { self.close(peer) }
            }
        case .approval, .grant:
            close(peer)
        }
    }

    private func send(_ message: some Encodable, to peer: Peer) throws {
        let data = try JSONEncoder().encode(message)
        guard data.count <= PairingWire.maximumFrame else { throw AgentError("Pairing message is too large.") }
        peer.connection.send(content: data + Data([10]), completion: .contentProcessed { [weak self, weak peer] error in
            Task { @MainActor [weak self, weak peer] in
                guard let self, let peer, self.peer === peer else { return }
                if error != nil { self.close(peer); return }
                switch peer.stage {
                case .proof: self.receive(peer)
                case .grant: self.close(peer, deliveredGrant: true)
                default: break
                }
            }
        })
    }

    private func close(_ peer: Peer, deliveredGrant: Bool = false) {
        guard self.peer === peer else { return }
        if case .grant = peer.stage, !deliveredGrant { didGrant = false }
        self.peer = nil
        peer.timeout?.cancel()
        peer.approval?.cancel()
        peer.connection.cancel()
        if attempts >= Self.attemptLimit { stopAdvertising() }
    }
}
