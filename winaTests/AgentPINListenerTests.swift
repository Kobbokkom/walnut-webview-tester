import CryptoKit
import Foundation
import Network
import WalnutPairing
import XCTest
@testable import wina

@MainActor
final class AgentPINListenerTests: XCTestCase {
    private let payload = Data("test pairing record".utf8)
    private let listener = AgentPINListener()

    @MainActor private final class ApprovalState {
        var allowed = false
        var verifications: [String] = []
    }

    func testPINRequiresApprovalAndGrantsOnlyOnce() async throws {
        let approval = ApprovalState()
        let code = try await start { verification in
            approval.verifications.append(verification)
            return approval.allowed
        }
        defer { listener.stop() }

        let wrongCode = code == "000000" ? "000001" : "000000"
        let invalid = try await exchange(code: wrongCode)
        XCTAssertNil(invalid.grant)
        XCTAssertTrue(approval.verifications.isEmpty)
        XCTAssertEqual(listener.code, code)

        let changedShare = try await exchange(code: code, tamperWithReveal: true)
        XCTAssertNil(changedShare.grant)
        XCTAssertTrue(approval.verifications.isEmpty)

        let denied = try await exchange(code: code)
        XCTAssertNil(denied.grant)
        XCTAssertEqual(approval.verifications, [denied.verification])
        XCTAssertEqual(listener.code, code)

        approval.allowed = true
        let approved = try await exchange(code: code)
        XCTAssertEqual(approved.grant, payload)
        XCTAssertEqual(approval.verifications, [denied.verification, approved.verification])
        XCTAssertNil(listener.code)
        XCTAssertTrue(listener.didGrant)
    }

    func testAttemptLimitDisablesPIN() async throws {
        let code = try await start { _ in
            XCTFail("An invalid proof must not prompt for approval")
            return false
        }
        defer { listener.stop() }
        let wrongCode = code == "000000" ? "000001" : "000000"
        for _ in 0..<5 {
            let invalid = try await exchange(code: wrongCode)
            XCTAssertNil(invalid.grant)
        }
        XCTAssertNil(listener.code)
    }

    func testStoppingPINClosesAwaitingClient() async throws {
        let asked = expectation(description: "Verification requested")
        let code = try await start { _ in
            asked.fulfill()
            do { try await Task.sleep(for: .seconds(30)) } catch { return false }
            return true
        }
        defer { listener.stop() }
        let connecting = Task { try await exchange(code: code) }
        await fulfillment(of: [asked], timeout: 5)
        listener.stop()
        let result = try await connecting.value
        XCTAssertNil(result.grant)
        XCTAssertNil(listener.code)
    }

    private func start(_ authorize: @escaping @MainActor @Sendable (String) async -> Bool) async throws -> String {
        try listener.start(serviceName: "Walnut-test-\(UUID().uuidString)", payload: payload, authorize: authorize)
        let deadline = ContinuousClock.now + .seconds(3)
        while listener.code == nil, listener.error == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let code = try XCTUnwrap(listener.code, listener.error ?? "PIN listener did not start")
        XCTAssertTrue(PairingWire.isCode(code))
        return code
    }

    private func exchange(code: String, tamperWithReveal: Bool = false) async throws -> (verification: String, grant: Data?) {
        let port = try XCTUnwrap(NWEndpoint.Port(rawValue: PairingWire.port))
        let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            connection.cancel()
        }
        defer {
            timeout.cancel()
            connection.cancel()
        }
        let handshake = try PairingHandshake(role: .client, code: code, context: PairingWire.context)
        var nonce = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let commitment = try PairingWire.commitment(message: handshake.message, nonce: nonce)
        connection.start(queue: .main)
        try await send(PairingWire.Hello(commitment: commitment), using: connection)
        let response = await receive(using: connection)
        let challengeData = try XCTUnwrap(response)
        let challenge = try JSONDecoder().decode(PairingWire.Challenge.self, from: challengeData)
        let keys = try handshake.finish(peer: challenge.message)
        if tamperWithReveal { nonce[0] ^= 1 }
        try await send(PairingWire.Proof(message: handshake.message, nonce: nonce, proof: keys.clientProof), using: connection)
        guard let grantData = await receive(using: connection) else { return (keys.verificationCode, nil) }
        let grant = try JSONDecoder().decode(PairingWire.Grant.self, from: grantData)
        return (keys.verificationCode, try keys.open(grant.payload))
    }

    private func send(_ value: some Encodable, using connection: NWConnection) async throws {
        let frame = try JSONEncoder().encode(value) + Data([10])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receive(using connection: NWConnection) async -> Data? {
        var buffer = Data()
        let limit = PairingWire.maximumFrame + 1
        while buffer.count < limit {
            let chunk: Data? = await withCheckedContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: limit) { data, _, _, _ in
                    continuation.resume(returning: data)
                }
            }
            guard let chunk, !chunk.isEmpty else { return nil }
            buffer.append(chunk)
            if let newline = buffer.firstIndex(of: 10) { return Data(buffer[..<newline]) }
        }
        return nil
    }
}
