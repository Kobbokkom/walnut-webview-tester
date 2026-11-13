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
    private(set) var isReady = false

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var peer: Peer?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var deadline: ContinuousClock.Instant?
    @ObservationIgnored private var attempts = 0

    private static let lifetime = Duration.seconds(120)
    private static let attemptLimit = 5

    private enum Credential: Sendable {
        case pin(String, commit: @MainActor @Sendable () throws -> Void, authorize: @MainActor @Sendable (String) async -> Bool)
        case remembered(Data)

        var pin: String? {
            if case .pin(let code, _, _) = self { return code }
            return nil
        }

        func handshake() throws -> PairingHandshake {
            switch self {
            case .pin(let code, _, _):
                try PairingHandshake(role: .server, code: code, context: PairingWire.context)
            case .remembered(let secret):
                try PairingHandshake(role: .server, secret: secret, context: PairingWire.rememberedContext)
            }
        }
    }

    @MainActor private final class Peer {
        enum Stage {
            case connecting, hello, proof(PairingHandshake, commitment: Data), approval, grant
        }

        let connection: NWConnection
        let payload: Data
        let credential: Credential
        var stage = Stage.connecting
        var buffer = Data()
        var timeout: Task<Void, Never>?
        var approval: Task<Void, Never>?

        init(_ connection: NWConnection, payload: Data, credential: Credential) {
            self.connection = connection
            self.payload = payload
            self.credential = credential
        }
    }

    func start(
        serviceName: String,
        payload: Data,
        commit: @escaping @MainActor @Sendable () throws -> Void = {},
        authorize: @escaping @MainActor @Sendable (String) async -> Bool
    ) throws {
        let pin = String(format: "%06d", Int.random(in: 0...999_999))
        try listen(serviceName: serviceName, payload: payload, credential: .pin(pin, commit: commit, authorize: authorize))
    }

    func startRemembered(serviceName: String, secret: Data, payload: Data) throws {
        guard secret.count == PairingWire.rememberedSecretSize else { throw AgentError("Invalid saved pairing key.") }
        try listen(serviceName: serviceName, payload: payload, credential: .remembered(secret))
    }

    private func listen(serviceName: String, payload: Data, credential: Credential) throws {
        stop()
        error = nil
        guard !payload.isEmpty else { throw AgentError("Missing pairing grant.") }
        let isPIN = credential.pin != nil
        let portNumber = isPIN ? PairingWire.port : PairingWire.rememberedPort
        guard let port = NWEndpoint.Port(rawValue: portNumber) else { throw AgentError("Invalid pairing port.") }
        let listener = try NWListener(using: .tcp, on: port)
        var service = NWListener.Service(name: serviceName, type: isPIN ? PairingWire.serviceType : PairingWire.rememberedServiceType)
        service.noAutoRename = !isPIN
        listener.service = service
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor [weak self, weak listener] in
                guard let self, let listener, self.listener === listener else { return }
                switch state {
                case .ready:
                    self.isReady = true
                    self.code = credential.pin
                    self.error = nil
                case .waiting(let error):
                    self.isReady = false
                    self.code = nil
                    self.error = error.localizedDescription
                    if let peer = self.peer { self.close(peer) }
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
                self.accept(connection, payload: payload, credential: credential)
            }
        }
        self.listener = listener
        attempts = 0
        if isPIN {
            deadline = .now + Self.lifetime
            expiry = Task { [weak self] in
                do { try await Task.sleep(for: Self.lifetime) } catch { return }
                self?.stop()
            }
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
        isReady = false
        deadline = nil
        code = nil
    }

    private var liveCode: String? {
        guard isReady, let deadline, ContinuousClock.now < deadline else { return nil }
        return code
    }

    private func accept(_ connection: NWConnection, payload: Data, credential: Credential) {
        guard isReady, peer == nil else { connection.cancel(); return }
        if credential.pin != nil, liveCode == nil || attempts >= Self.attemptLimit {
            connection.cancel()
            return
        }
        let peer = Peer(connection, payload: payload, credential: credential)
        self.peer = peer
        connection.stateUpdateHandler = { [weak self, weak peer] state in
            Task { @MainActor [weak self, weak peer] in
                guard let self, let peer, self.peer === peer else { return }
                switch state {
                case .ready:
                    guard case .connecting = peer.stage else { return }
                    peer.stage = .hello
                    self.receive(peer)
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
                case .connecting, .approval, .grant: self.close(peer); return
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
        guard isReady, peer.credential.pin == nil || liveCode != nil else { close(peer); return }
        switch peer.stage {
        case .hello:
            let hello = try JSONDecoder().decode(PairingWire.Hello.self, from: frame)
            guard hello.commitment.count == PairingWire.commitmentSize else { close(peer); return }
            if peer.credential.pin != nil { attempts += 1 }
            let handshake = try peer.credential.handshake()
            peer.stage = .proof(handshake, commitment: hello.commitment)
            send(try Self.encode(PairingWire.Challenge(message: handshake.message)), to: peer)
        case .proof(let handshake, let commitment):
            let proof = try JSONDecoder().decode(PairingWire.Proof.self, from: frame)
            guard proof.message.count == PairingWire.messageSize, proof.nonce.count == PairingWire.nonceSize,
                  try PairingWire.commitment(message: proof.message, nonce: proof.nonce) == commitment else {
                close(peer)
                return
            }
            let keys = try handshake.finish(peer: proof.message)
            guard keys.verifyClientProof(proof.proof) else { close(peer); return }
            switch peer.credential {
            case .pin(_, let commit, let authorize):
                authorizePIN(peer, keys: keys, commit: commit, authorize: authorize)
            case .remembered:
                try grant(peer, keys: keys)
            }
        case .connecting, .approval, .grant:
            close(peer)
        }
    }

    private func authorizePIN(
        _ peer: Peer,
        keys: PairingKeys,
        commit: @escaping @MainActor @Sendable () throws -> Void,
        authorize: @escaping @MainActor @Sendable (String) async -> Bool
    ) {
        peer.timeout?.cancel()
        peer.stage = .approval
        receive(peer)
        peer.approval = Task { [weak self, weak peer] in
            guard let self, let peer else { return }
            let allowed = await authorize(keys.verificationCode)
            guard self.peer === peer else { return }
            guard allowed, !Task.isCancelled, self.liveCode != nil else { self.close(peer); return }
            do { try self.grant(peer, keys: keys, commit: commit) } catch { self.close(peer) }
        }
    }

    private func grant(_ peer: Peer, keys: PairingKeys, commit: (@MainActor () throws -> Void)? = nil) throws {
        let grant = PairingWire.Grant(payload: try keys.seal(peer.payload))
        let frame = try Self.encode(grant)
        do {
            try commit?()
        } catch {
            stop()
            self.error = String(localized: "Could not save this pairing. Get a new code and try again.")
            return
        }
        peer.stage = .grant
        if peer.credential.pin != nil {
            didGrant = true
            stopAdvertising()
        }
        startPeerTimeout(peer)
        send(frame, to: peer)
    }

    private static func encode(_ message: some Encodable) throws -> Data {
        let data = try JSONEncoder().encode(message)
        guard data.count <= PairingWire.maximumFrame else { throw AgentError("Pairing message is too large.") }
        return data + Data([10])
    }

    private func send(_ frame: Data, to peer: Peer) {
        peer.connection.send(content: frame, completion: .contentProcessed { [weak self, weak peer] error in
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
        if case .grant = peer.stage, peer.credential.pin != nil, !deliveredGrant { didGrant = false }
        self.peer = nil
        peer.timeout?.cancel()
        peer.approval?.cancel()
        peer.connection.cancel()
        if attempts >= Self.attemptLimit { stopAdvertising() }
    }
}
