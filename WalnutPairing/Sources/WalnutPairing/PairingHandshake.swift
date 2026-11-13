import CryptoKit
import Foundation
import WalnutSPAKE2

public enum PairingHandshakeError: LocalizedError {
    case invalidCode, exchangeFailed, invalidGrant

    public var errorDescription: String? {
        switch self {
        case .invalidCode: "Enter the six-digit Walnut pairing code."
        case .exchangeFailed: "Walnut could not authenticate this pairing exchange."
        case .invalidGrant: "Walnut returned an invalid pairing grant."
        }
    }
}

/// BoringSSL's SPAKE2 over Ed25519 follows draft-irtf-cfrg-spake2-02.
/// Both peers must use Walnut's transcript and role labels.
public final class PairingHandshake {
    public enum Role {
        case client, server
    }

    public let message: Data
    private let role: Role
    private let context: Data
    private var exchange: OpaquePointer?

    public init(role: Role, code: String, context: String) throws {
        guard PairingWire.isCode(code) else { throw PairingHandshakeError.invalidCode }
        let contextBytes = Data(context.utf8)
        guard (1...128).contains(contextBytes.count) else { throw PairingHandshakeError.exchangeFailed }
        let clientID = Array("walnut-pair-v1/client/".utf8) + contextBytes
        let serverID = Array("walnut-pair-v1/server/".utf8) + contextBytes
        let (ownID, peerID) = role == .client ? (clientID, serverID) : (serverID, clientID)
        guard let exchange = walnut_spake2_new(
            role == .client, ownID, ownID.count, peerID, peerID.count
        ) else { throw PairingHandshakeError.exchangeFailed }

        let password = Array(code.utf8)
        var message = [UInt8](repeating: 0, count: PairingWire.messageSize)
        let capacity = message.count
        guard walnut_spake2_generate(exchange, password, password.count, &message, capacity) else {
            walnut_spake2_free(exchange)
            throw PairingHandshakeError.exchangeFailed
        }
        self.role = role
        self.context = contextBytes
        self.exchange = exchange
        self.message = Data(message)
    }

    deinit {
        if let exchange { walnut_spake2_free(exchange) }
    }

    public func finish(peer: Data) throws -> PairingKeys {
        guard let exchange else { throw PairingHandshakeError.exchangeFailed }
        self.exchange = nil
        defer { walnut_spake2_free(exchange) }
        guard peer.count == PairingWire.messageSize else { throw PairingHandshakeError.exchangeFailed }
        let peerMessage = Array(peer)
        var material = [UInt8](repeating: 0, count: 64)
        let capacity = material.count
        guard walnut_spake2_finish(exchange, peerMessage, peerMessage.count, &material, capacity) else {
            throw PairingHandshakeError.exchangeFailed
        }

        // The two shares are fixed-size and ordered by role in both transcripts.
        var transcript = Data("walnut-pair-v1/spake2/".utf8)
        transcript.append(UInt8(context.count))
        transcript.append(context)
        transcript.append(role == .client ? message : peer)
        transcript.append(role == .client ? peer : message)
        let digest = Data(SHA256.hash(data: transcript))
        let secret = SymmetricKey(data: material)
        return PairingKeys(role: role, secret: secret, transcript: digest)
    }
}

public struct PairingKeys {
    private static let maximumGrant = 2048
    private static let gcmOverhead = 28

    private let role: PairingHandshake.Role
    private let transcript: Data
    private let proofKey: SymmetricKey
    private let grantKey: SymmetricKey
    public let verificationCode: String

    fileprivate init(role: PairingHandshake.Role, secret: SymmetricKey, transcript: Data) {
        self.role = role
        self.transcript = transcript
        proofKey = Self.deriveKey(secret, transcript, label: "walnut-pair-v1/client-proof")
        grantKey = Self.deriveKey(secret, transcript, label: "walnut-pair-v1/server-grant")
        let verification = Self.deriveKey(secret, transcript, label: "walnut-pair-v1/verification-code")
        let number = verification.withUnsafeBytes { bytes in
            UInt64(bigEndian: bytes.loadUnaligned(as: UInt64.self)) % 1_000_000
        }
        verificationCode = String(repeating: "0", count: 6 - String(number).count) + String(number)
    }

    public var clientProof: Data {
        Data(HMAC<SHA256>.authenticationCode(for: transcript, using: proofKey))
    }

    public func verifyClientProof(_ proof: Data) -> Bool {
        role == .server && proof.count == 32
            && HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: transcript, using: proofKey)
    }

    public func seal(_ payload: Data) throws -> Data {
        guard role == .server, (1...Self.maximumGrant).contains(payload.count),
              let combined = try AES.GCM.seal(payload, using: grantKey, authenticating: transcript).combined else {
            throw PairingHandshakeError.invalidGrant
        }
        return combined
    }

    public func open(_ encrypted: Data) throws -> Data {
        guard role == .client,
              (Self.gcmOverhead + 1...Self.maximumGrant + Self.gcmOverhead).contains(encrypted.count),
              let box = try? AES.GCM.SealedBox(combined: encrypted),
              let payload = try? AES.GCM.open(box, using: grantKey, authenticating: transcript) else {
            throw PairingHandshakeError.invalidGrant
        }
        return payload
    }

    private static func deriveKey(_ secret: SymmetricKey, _ transcript: Data, label: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: secret, salt: transcript, info: Data(label.utf8), outputByteCount: 32)
    }
}
