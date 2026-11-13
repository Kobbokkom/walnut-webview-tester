import Foundation
import WalnutPairing
import XCTest

final class PairingHandshakeTests: XCTestCase {
    func testMatchingCodeConfirmsClientAndDecryptsGrant() throws {
        let (client, server) = try exchange()
        XCTAssertTrue(server.verifyClientProof(client.clientProof))
        XCTAssertTrue(PairingWire.isCode(client.verificationCode))
        XCTAssertEqual(client.verificationCode, server.verificationCode)
        let payload = Data("test pairing grant".utf8)
        XCTAssertEqual(try client.open(server.seal(payload)), payload)
        XCTAssertThrowsError(try client.seal(payload))
        XCTAssertThrowsError(try server.open(server.seal(payload)))
    }

    func testWrongCodeOrContextCannotConfirmEitherPeer() throws {
        for (code, context) in [("042171", "test"), ("042170", "other")] {
            let (client, server) = try exchange(serverCode: code, serverContext: context)
            XCTAssertFalse(server.verifyClientProof(client.clientProof))
            XCTAssertThrowsError(try client.open(server.seal(Data([1]))))
        }
    }

    func testOneShotMalformedAndTamperedFrames() throws {
        let client = try PairingHandshake(role: .client, code: "042170", context: "test")
        let server = try PairingHandshake(role: .server, code: "042170", context: "test")
        XCTAssertThrowsError(try client.finish(peer: Data([1])))
        XCTAssertThrowsError(try client.finish(peer: server.message))

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

    func testPairingCodesAreSixASCIIDigits() {
        XCTAssertTrue(PairingWire.isCode("000001"))
        for invalid in ["12345", "1234567", "１２３４５６", "12345\n", " 12345"] {
            XCTAssertFalse(PairingWire.isCode(invalid))
        }
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
        let proof = try JSONEncoder().encode(PairingWire.Proof(message: message, nonce: nonce, proof: Data([4])))
        let reveal = try JSONDecoder().decode(PairingWire.Proof.self, from: proof)
        XCTAssertEqual(try PairingWire.commitment(message: reveal.message, nonce: reveal.nonce), commitment)
    }

    private func exchange(
        serverCode: String = "042170", serverContext: String = "test"
    ) throws -> (PairingKeys, PairingKeys) {
        let client = try PairingHandshake(role: .client, code: "042170", context: "test")
        let server = try PairingHandshake(role: .server, code: serverCode, context: serverContext)
        return (try client.finish(peer: server.message), try server.finish(peer: client.message))
    }
}
