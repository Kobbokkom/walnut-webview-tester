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
        var committed = 0
    }

    func testComparisonRequiresApprovalAndGrantsOnlyOnce() async throws {
        let approval = ApprovalState()
        try await start(commit: { approval.committed += 1 }, authorize: { verification in
            approval.verifications.append(verification)
            return approval.allowed
        })
        defer { listener.stop() }

        let invalid = try await exchange(tamperWithProof: true)
        XCTAssertNil(invalid.grant)
        XCTAssertTrue(approval.verifications.isEmpty)
        XCTAssertTrue(listener.isPairingAvailable)

        let changedShare = try await exchange(tamperWithReveal: true)
        XCTAssertNil(changedShare.grant)
        XCTAssertTrue(approval.verifications.isEmpty)

        let denied = try await exchange()
        XCTAssertNil(denied.grant)
        XCTAssertEqual(approval.verifications, [denied.verification])
        XCTAssertTrue(listener.isPairingAvailable)
        XCTAssertEqual(approval.committed, 0)

        approval.allowed = true
        let approved = try await exchange()
        XCTAssertEqual(approved.grant, payload)
        XCTAssertEqual(approved.verification.utf8.count, 6)
        XCTAssertTrue(approved.verification.utf8.allSatisfy { (48...57).contains($0) })
        XCTAssertEqual(approval.verifications, [denied.verification, approved.verification])
        XCTAssertEqual(approval.committed, 1)
        XCTAssertFalse(listener.isPairingAvailable)
        XCTAssertTrue(listener.didGrant)
    }

    func testAttemptLimitDisablesNewPairing() async throws {
        try await start { _ in
            XCTFail("An invalid proof must not prompt for approval")
            return false
        }
        defer { listener.stop() }
        for _ in 0..<5 {
            let invalid = try await exchange(tamperWithProof: true)
            XCTAssertNil(invalid.grant)
        }
        XCTAssertFalse(listener.isPairingAvailable)
    }

    func testStoppingPairingClosesAwaitingClient() async throws {
        let asked = expectation(description: "Verification requested")
        try await start(commit: { XCTFail("A stopped request must not be saved") }, authorize: { _ in
            asked.fulfill()
            do { try await Task.sleep(for: .seconds(30)) } catch { return false }
            return true
        })
        defer { listener.stop() }
        let connecting = Task { try await exchange() }
        await fulfillment(of: [asked], timeout: 5)
        listener.stop()
        let result = try await connecting.value
        XCTAssertNil(result.grant)
        XCTAssertFalse(listener.isPairingAvailable)
    }

    func testFailingToSaveClosesPairingWithoutGrant() async throws {
        try await start(commit: { throw URLError(.cannotWriteToFile) }, authorize: { _ in true })
        defer { listener.stop() }
        let result = try await exchange()
        XCTAssertNil(result.grant)
        XCTAssertFalse(listener.isPairingAvailable)
        XCTAssertFalse(listener.didGrant)
        XCTAssertNotNil(listener.error)
    }

    func testSavedKeyCanReconnectRepeatedlyWithoutApproval() async throws {
        let secret = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let wrongSecret = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let name = "Walnut-test-\(UUID().uuidString)"
        try listener.startRemembered(serviceName: name, secret: secret, payload: payload)
        defer { listener.stop() }
        try await waitUntilReady()
        XCTAssertFalse(listener.isPairingAvailable)

        let rejected = try await exchange(secret: wrongSecret)
        XCTAssertNil(rejected.grant)
        for _ in 0..<2 {
            let approved = try await exchange(secret: secret)
            XCTAssertEqual(approved.grant, payload)
            XCTAssertTrue(listener.isReady)
            XCTAssertFalse(listener.didGrant)
        }
        listener.stop()
        XCTAssertFalse(listener.isReady)
    }

    private func start(
        commit: @escaping @MainActor @Sendable () throws -> Void = {},
        authorize: @escaping @MainActor @Sendable (String) async -> Bool
    ) async throws {
        try listener.start(serviceName: "Walnut-test-\(UUID().uuidString)", payload: payload, commit: commit, authorize: authorize)
        try await waitUntilReady()
        XCTAssertTrue(listener.isPairingAvailable)
    }

    private func waitUntilReady() async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !listener.isReady, listener.error == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard listener.isReady else { throw AgentError(listener.error ?? "Pairing listener did not start") }
    }

    private func exchange(
        tamperWithReveal: Bool = false,
        tamperWithProof: Bool = false
    ) async throws -> (verification: String, grant: Data?) {
        let handshake = try PairingHandshake(role: .client, context: PairingWire.context)
        return try await exchange(handshake, port: PairingWire.port, tamperWithReveal: tamperWithReveal,
                                  tamperWithProof: tamperWithProof)
    }

    private func exchange(secret: Data) async throws -> (verification: String, grant: Data?) {
        let handshake = try PairingHandshake(role: .client, secret: secret, context: PairingWire.rememberedContext)
        return try await exchange(handshake, port: PairingWire.rememberedPort)
    }

    private func exchange(
        _ handshake: PairingHandshake,
        port portNumber: UInt16,
        tamperWithReveal: Bool = false,
        tamperWithProof: Bool = false
    ) async throws -> (verification: String, grant: Data?) {
        let port = try XCTUnwrap(NWEndpoint.Port(rawValue: portNumber))
        let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            connection.cancel()
        }
        defer {
            timeout.cancel()
            connection.cancel()
        }
        var nonce = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let commitment = try PairingWire.commitment(message: handshake.message, nonce: nonce)
        connection.start(queue: .main)
        try await send(PairingWire.Hello(commitment: commitment), using: connection)
        let response = await receive(using: connection)
        let challengeData = try XCTUnwrap(response)
        let challenge = try JSONDecoder().decode(PairingWire.Challenge.self, from: challengeData)
        let keys = try handshake.finish(peer: challenge.message, nonce: nonce)
        if tamperWithReveal { nonce[0] ^= 1 }
        var proof = keys.clientProof
        if tamperWithProof { proof[0] ^= 1 }
        try await send(PairingWire.Proof(message: handshake.message, nonce: nonce, proof: proof), using: connection)
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
