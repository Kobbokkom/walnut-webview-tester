import CryptoKit
import Foundation

public enum PairingWire {
    public static let context = "walnut-pair-v1"
    public static let serviceType = "_walnut-pair._tcp"
    public static let port: UInt16 = 58691
    public static let rememberedContext = "walnut-resume-v1"
    public static let rememberedServiceType = "_walnut-resume._tcp"
    public static let rememberedPort: UInt16 = 58692
    public static let rememberedSecretSize = 32
    public static let maximumFrame = 4096
    public static let messageSize = 32
    public static let nonceSize = 32
    public static let commitmentSize = 32

    public static func isCode(_ value: String) -> Bool {
        value.utf8.count == 6 && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    public static func commitment(message: Data, nonce: Data) throws -> Data {
        guard message.count == messageSize, nonce.count == nonceSize else {
            throw PairingHandshakeError.exchangeFailed
        }
        // Commit to the client share before the server discloses its share.
        var transcript = Data("walnut-pair-v1/client-commitment/".utf8)
        transcript.append(nonce)
        transcript.append(message)
        return Data(SHA256.hash(data: transcript))
    }

    public struct Hello: Codable, Sendable {
        public let commitment: Data
        public init(commitment: Data) { self.commitment = commitment }
    }

    public struct Challenge: Codable, Sendable {
        public let message: Data
        public init(message: Data) { self.message = message }
    }

    public struct Proof: Codable, Sendable {
        public let message: Data
        public let nonce: Data
        public let proof: Data

        public init(message: Data, nonce: Data, proof: Data) {
            self.message = message
            self.nonce = nonce
            self.proof = proof
        }
    }

    public struct Grant: Codable, Sendable {
        public let payload: Data
        public init(payload: Data) { self.payload = payload }
    }
}
