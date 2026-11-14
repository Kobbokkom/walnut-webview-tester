import CryptoKit
import Foundation

public enum PairingWire {
    public static let context = "walnut-pair-v2"
    public static let serviceType = "_walnut-pair-v2._tcp"
    public static let port: UInt16 = 58691
    public static let rememberedContext = "walnut-resume-v2"
    public static let rememberedServiceType = "_walnut-back-v2._tcp"
    public static let rememberedPort: UInt16 = 58692
    public static let rememberedSecretSize = 32
    public static let maximumFrame = 4096
    public static let messageSize = 32
    public static let nonceSize = 32
    public static let commitmentSize = 32

    public static func commitment(message: Data, nonce: Data) throws -> Data {
        guard message.count == messageSize, nonce.count == nonceSize else {
            throw PairingHandshakeError.exchangeFailed
        }
        // Commit before the fresh server share to prevent grinding the comparison number (RFC 6189 §4.4.1.1).
        var transcript = Data("walnut-pair-v2/client-commitment/".utf8)
        transcript.append(nonce)
        transcript.append(message)
        return Data(SHA256.hash(data: transcript))
    }

    public struct Hello: Codable, Sendable {
        public let commitment: Data
        public init(commitment: Data) { self.commitment = commitment }

        private enum CodingKeys: String, CodingKey {
            case commitment = "commitmentV2"
        }
    }

    public struct Challenge: Codable, Sendable {
        public let message: Data
        public init(message: Data) { self.message = message }

        private enum CodingKeys: String, CodingKey {
            case message = "messageV2"
        }
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
