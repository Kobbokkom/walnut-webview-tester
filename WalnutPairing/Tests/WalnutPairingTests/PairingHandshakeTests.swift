import Foundation
import WalnutPairing
import XCTest

final class PairingHandshakeTests: XCTestCase {
    func testMatchingComparisonConfirmsClientAndDecryptsGrant() throws {
        let (client, server) = try exchange()
        XCTAssertTrue(server.verifyClientProof(client.clientProof))
        XCTAssertEqual(client.verificationCode.utf8.count, 6)
        XCTAssertTrue(client.verificationCode.utf8.allSatisfy { (48...57).contains($0) })
        XCTAssertEqual(client.verificationCode, server.verificationCode)
        let payload = Data("test pairing grant".utf8)
        XCTAssertEqual(try client.open(server.seal(payload)), payload)
        XCTAssertThrowsError(try client.seal(payload))
        XCTAssertThrowsError(try server.open(server.seal(payload)))
    }

    func testWrongNonceOrContextCannotConfirmEitherPeer() throws {
        for (nonce, context) in [(Data(repeating: 3, count: PairingWire.nonceSize), "test"), (nonce, "other")] {
            let (client, server) = try exchange(serverContext: context, serverNonce: nonce)
            XCTAssertFalse(server.verifyClientProof(client.clientProof))
            XCTAssertThrowsError(try client.open(server.seal(Data([1]))))
        }
    }

    func testOneShotMalformedAndTamperedFrames() throws {
        let server = try PairingHandshake(role: .server, context: "test")
        for invalidShare in [Data([1]), Data(count: PairingWire.messageSize)] {
            let client = try PairingHandshake(role: .client, context: "test")
            XCTAssertThrowsError(try client.finish(peer: invalidShare, nonce: nonce))
            XCTAssertThrowsError(try client.finish(peer: server.message, nonce: nonce))
        }
        let client = try PairingHandshake(role: .client, context: "test")
        XCTAssertThrowsError(try client.finish(peer: client.message, nonce: nonce))
        let wrongNonce = try PairingHandshake(role: .client, context: "test")
        XCTAssertThrowsError(try wrongNonce.finish(peer: server.message, nonce: Data()))

        let (clientKeys, serverKeys) = try exchange()
        var proof = clientKeys.clientProof
        proof[0] ^= 1
        XCTAssertFalse(serverKeys.verifyClientProof(proof))
        var grant = try serverKeys.seal(Data([1]))
        grant[0] ^= 1
        XCTAssertThrowsError(try clientKeys.open(grant))
        XCTAssertThrowsError(try serverKeys.seal(Data(count: PairingWire.maximumFrame)))

        let (nextClient, nextServer) = try exchange()
        XCTAssertFalse(nextServer.verifyClientProof(clientKeys.clientProof))
        XCTAssertThrowsError(try nextClient.open(serverKeys.seal(Data([1]))))
    }

    func testRememberedSecretAuthenticatesFreshExchanges() throws {
        let secret = Data(repeating: 0xa4, count: PairingWire.rememberedSecretSize)
        let context = PairingWire.rememberedContext
        let client = try PairingHandshake(role: .client, secret: secret, context: context)
        let server = try PairingHandshake(role: .server, secret: secret, context: context)
        let nextServer = try PairingHandshake(role: .server, secret: secret, context: context)
        let clientKeys = try client.finish(peer: server.message, nonce: nonce)
        let serverKeys = try server.finish(peer: client.message, nonce: nonce)
        XCTAssertTrue(serverKeys.verifyClientProof(clientKeys.clientProof))
        XCTAssertEqual(try clientKeys.open(serverKeys.seal(Data([1]))), Data([1]))
        XCTAssertFalse(try nextServer.finish(peer: client.message, nonce: nonce).verifyClientProof(clientKeys.clientProof))
        XCTAssertThrowsError(try PairingHandshake(role: .client, secret: secret.dropLast(), context: context))
    }

    func testWrongRememberedSecretCannotConfirmEitherPeer() throws {
        let secret = Data(repeating: 0xa4, count: PairingWire.rememberedSecretSize)
        let wrongSecret = Data(repeating: 0xa5, count: PairingWire.rememberedSecretSize)
        let context = PairingWire.rememberedContext
        let client = try PairingHandshake(role: .client, secret: secret, context: context)
        let server = try PairingHandshake(role: .server, secret: wrongSecret, context: context)
        let clientKeys = try client.finish(peer: server.message, nonce: nonce)
        let serverKeys = try server.finish(peer: client.message, nonce: nonce)
        XCTAssertFalse(serverKeys.verifyClientProof(clientKeys.clientProof))
        XCTAssertThrowsError(try clientKeys.open(serverKeys.seal(Data([1]))))
    }

    func testCommitmentBindsClientShareAndNonce() throws {
        let message = Data(repeating: 1, count: PairingWire.messageSize)
        let nonce = Data(repeating: 2, count: PairingWire.nonceSize)
        let commitment = try PairingWire.commitment(message: message, nonce: nonce)
        XCTAssertEqual(commitment.count, PairingWire.commitmentSize)
        XCTAssertEqual(try PairingWire.commitment(message: message, nonce: nonce), commitment)
        XCTAssertNotEqual(try PairingWire.commitment(message: nonce, nonce: nonce), commitment)
        XCTAssertNotEqual(try PairingWire.commitment(message: message, nonce: message), commitment)
        XCTAssertThrowsError(try PairingWire.commitment(message: message.dropLast(), nonce: nonce))
        XCTAssertThrowsError(try PairingWire.commitment(message: message, nonce: nonce + Data([3])))

        let hello = try JSONEncoder().encode(PairingWire.Hello(commitment: commitment))
        XCTAssertEqual(try JSONDecoder().decode(PairingWire.Hello.self, from: hello).commitment, commitment)
        let challenge = try JSONEncoder().encode(PairingWire.Challenge(message: message))
        XCTAssertEqual(try JSONDecoder().decode(PairingWire.Challenge.self, from: challenge).message, message)
        let proof = try JSONEncoder().encode(PairingWire.Proof(message: message, nonce: nonce, proof: Data([4])))
        let reveal = try JSONDecoder().decode(PairingWire.Proof.self, from: proof)
        XCTAssertEqual(try PairingWire.commitment(message: reveal.message, nonce: reveal.nonce), commitment)
    }

    func testRejectsVersionOneHandshakeFrames() throws {
        let share = Data(count: PairingWire.messageSize).base64EncodedString()
        let hello = Data("{\"commitment\":\"\(share)\"}".utf8)
        let challenge = Data("{\"message\":\"\(share)\"}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(PairingWire.Hello.self, from: hello))
        XCTAssertThrowsError(try JSONDecoder().decode(PairingWire.Challenge.self, from: challenge))
    }

    private var nonce: Data { Data(repeating: 2, count: PairingWire.nonceSize) }

    private func exchange(
        serverContext: String = "test", serverNonce: Data? = nil
    ) throws -> (PairingKeys, PairingKeys) {
        let client = try PairingHandshake(role: .client, context: "test")
        let server = try PairingHandshake(role: .server, context: serverContext)
        return (try client.finish(peer: server.message, nonce: nonce),
                try server.finish(peer: client.message, nonce: serverNonce ?? nonce))
    }
}
