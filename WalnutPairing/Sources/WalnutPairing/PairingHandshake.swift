import CryptoKit
import Foundation

public enum PairingHandshakeError: LocalizedError {
    case exchangeFailed, invalidGrant

    public var errorDescription: String? {
        switch self {
        case .exchangeFailed: "Walnut could not authenticate this pairing exchange."
        case .invalidGrant: "Walnut returned an invalid pairing grant."
        }
    }
}

public final class PairingHandshake {
    public enum Role {
        case client, server
    }

    public let message: Data
    private let role: Role
    private let context: Data
    private let rememberedKey: SymmetricKey?
    private var privateKey: Curve25519.KeyAgreement.PrivateKey?

    public convenience init(role: Role, context: String) throws {
        try self.init(role: role, rememberedKey: nil, context: context)
    }

    public convenience init(role: Role, secret: Data, context: String) throws {
        guard secret.count == PairingWire.rememberedSecretSize else { throw PairingHandshakeError.exchangeFailed }
        try self.init(role: role, rememberedKey: SymmetricKey(data: secret), context: context)
    }

    private init(role: Role, rememberedKey: SymmetricKey?, context: String) throws {
        let contextBytes = Data(context.utf8)
        guard (1...128).contains(contextBytes.count) else { throw PairingHandshakeError.exchangeFailed }
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        self.role = role
        self.context = contextBytes
        self.rememberedKey = rememberedKey
        self.privateKey = privateKey
        message = privateKey.publicKey.rawRepresentation
    }

    public func finish(peer: Data, nonce: Data) throws -> PairingKeys {
        guard let privateKey else { throw PairingHandshakeError.exchangeFailed }
        self.privateKey = nil
        guard peer.count == PairingWire.messageSize, nonce.count == PairingWire.nonceSize, peer != message,
              let publicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peer),
              let sharedSecret = try? privateKey.sharedSecretFromKeyAgreement(with: publicKey) else {
            throw PairingHandshakeError.exchangeFailed
        }

        // The two shares are fixed-size and ordered by role in both transcripts.
        var transcript = Data("walnut-pair-v2/x25519/".utf8)
        transcript.append(rememberedKey == nil ? 0 : 1)
        transcript.append(UInt8(context.count))
        transcript.append(context)
        transcript.append(nonce)
        transcript.append(role == .client ? message : peer)
        transcript.append(role == .client ? peer : message)
        let digest = Data(SHA256.hash(data: transcript))
        // Resume requires both a new shared secret and the remembered key.
        let salt = rememberedKey.map { Data(HMAC<SHA256>.authenticationCode(for: digest, using: $0)) } ?? digest
        let secret = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: salt, sharedInfo: Data("walnut-pair-v2/handshake-key".utf8), outputByteCount: 32
        )
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
        proofKey = Self.deriveKey(secret, transcript, label: "walnut-pair-v2/client-proof")
        grantKey = Self.deriveKey(secret, transcript, label: "walnut-pair-v2/server-grant")
        let verification = Self.deriveKey(secret, transcript, label: "walnut-pair-v2/verification-code")
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
