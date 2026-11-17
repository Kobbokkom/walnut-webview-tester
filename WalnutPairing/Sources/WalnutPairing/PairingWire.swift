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

    /// Proves the client opened the grant, so the phone saves the pairing only after the Mac user confirms it.
    public static func saveDigest(_ payload: Data) -> Data {
        Data(SHA256.hash(data: Data("walnut-pair-v2/save/".utf8) + payload))
    }

    public struct Hello: Codable, Sendable {
        public let commitment: Data
        /// The client sends `SaveConfirmation` before either side saves. Older clients omit it.
        public let confirmsSave: Bool

        public init(commitment: Data, confirmsSave: Bool) {
            self.commitment = commitment
            self.confirmsSave = confirmsSave
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            commitment = try container.decode(Data.self, forKey: .commitment)
            confirmsSave = try container.decodeIfPresent(Bool.self, forKey: .confirmsSave) ?? false
        }

        private enum CodingKeys: String, CodingKey {
            case commitment = "commitmentV2"
            case confirmsSave
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
        /// The phone has not saved the pairing yet and waits for `SaveConfirmation`. Older apps omit it.
        public let awaitsConfirmation: Bool

        public init(payload: Data, awaitsConfirmation: Bool = false) {
            self.payload = payload
            self.awaitsConfirmation = awaitsConfirmation
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            payload = try container.decode(Data.self, forKey: .payload)
            awaitsConfirmation = try container.decodeIfPresent(Bool.self, forKey: .awaitsConfirmation) ?? false
        }

        private enum CodingKeys: String, CodingKey {
            case payload, awaitsConfirmation
        }
    }

    /// Sent by the Mac after its user confirms the numbers matched.
    public struct SaveConfirmation: Codable, Sendable {
        public let digest: Data
        public init(digest: Data) { self.digest = digest }
    }

    /// Sent by the phone once the pairing is saved; the Mac saves only after this.
    public struct Saved: Codable, Sendable {
        public let saved: Bool
        public init() { saved = true }
    }
}
