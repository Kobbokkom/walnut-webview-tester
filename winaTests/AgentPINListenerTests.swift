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

    func testConfirmingMacSavesOnlyAfterItConfirms() async throws {
        let approval = ApprovalState()
        approval.allowed = true
        try await start(commit: { approval.committed += 1 }, authorize: { _ in approval.allowed })
        defer { listener.stop() }

        let declined = try await exchange(confirm: .decline)
        XCTAssertEqual(declined.grant, payload)
        XCTAssertFalse(declined.saved)
        XCTAssertEqual(approval.committed, 0, "Answering N in Terminal must leave the iPhone unpaired")
        XCTAssertFalse(listener.didGrant)
        XCTAssertFalse(listener.isAwaitingMac)
    }

    func testForgedSaveConfirmationIsRejected() async throws {
        let approval = ApprovalState()
        try await start(commit: { approval.committed += 1 }, authorize: { _ in true })
        defer { listener.stop() }
        let forged = try await exchange(confirm: .forged)
        XCTAssertFalse(forged.saved)
        XCTAssertEqual(approval.committed, 0)
    }

    func testConfirmedMacIsSavedOnBothSides() async throws {
        let approval = ApprovalState()
        try await start(commit: { approval.committed += 1 }, authorize: { _ in true })
        defer { listener.stop() }
        let confirmed = try await exchange(confirm: .accept)
        XCTAssertEqual(confirmed.grant, payload)
        XCTAssertTrue(confirmed.saved)
        XCTAssertEqual(approval.committed, 1)
        XCTAssertTrue(listener.didGrant)
        XCTAssertFalse(listener.isPairingAvailable)
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

    /// How the test Mac answers "Did the numbers match?"; nil acts as an older client that cannot confirm.
    private enum Confirm { case accept, decline, forged }

    private typealias Outcome = (verification: String, grant: Data?, saved: Bool)

    private func exchange(
        tamperWithReveal: Bool = false,
        tamperWithProof: Bool = false,
        confirm: Confirm? = nil
    ) async throws -> Outcome {
        let handshake = try PairingHandshake(role: .client, context: PairingWire.context)
        return try await exchange(handshake, port: PairingWire.port, tamperWithReveal: tamperWithReveal,
                                  tamperWithProof: tamperWithProof, confirm: confirm)
    }

    private func exchange(secret: Data) async throws -> Outcome {
        let handshake = try PairingHandshake(role: .client, secret: secret, context: PairingWire.rememberedContext)
        return try await exchange(handshake, port: PairingWire.rememberedPort)
    }

    private func exchange(
        _ handshake: PairingHandshake,
        port portNumber: UInt16,
        tamperWithReveal: Bool = false,
        tamperWithProof: Bool = false,
        confirm: Confirm? = nil
    ) async throws -> Outcome {
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
        try await send(PairingWire.Hello(commitment: commitment, confirmsSave: confirm != nil), using: connection)
        let response = await receive(using: connection)
        let challengeData = try XCTUnwrap(response)
        let challenge = try JSONDecoder().decode(PairingWire.Challenge.self, from: challengeData)
        let keys = try handshake.finish(peer: challenge.message, nonce: nonce)
        if tamperWithReveal { nonce[0] ^= 1 }
        var proof = keys.clientProof
        if tamperWithProof { proof[0] ^= 1 }
        try await send(PairingWire.Proof(message: handshake.message, nonce: nonce, proof: proof), using: connection)
        guard let grantData = await receive(using: connection) else { return (keys.verificationCode, nil, false) }
        let grant = try JSONDecoder().decode(PairingWire.Grant.self, from: grantData)
        let opened = try keys.open(grant.payload)
        XCTAssertEqual(grant.awaitsConfirmation, confirm != nil)
        guard let confirm, confirm != .decline else {
            connection.cancel()
            try await Task.sleep(for: .milliseconds(200))
            return (keys.verificationCode, opened, false)
        }
        let digest = PairingWire.saveDigest(confirm == .forged ? Data("other".utf8) : opened)
        try await send(PairingWire.SaveConfirmation(digest: digest), using: connection)
        let saved = await receive(using: connection).flatMap { try? JSONDecoder().decode(PairingWire.Saved.self, from: $0) }
        return (keys.verificationCode, opened, saved?.saved == true)
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
