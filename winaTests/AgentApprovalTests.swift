import XCTest
@testable import wina

@MainActor
final class AgentApprovalTests: XCTestCase {
    func testCancelledPromptCannotResolveNextRequestWithIdenticalMessage() async throws {
        let gate = AgentApprovalGate()
        let first = Task { await gate.authorize("Allow action?") }
        let old = try await pending(in: gate)
        first.cancel()
        let firstAllowed = await first.value
        XCTAssertFalse(firstAllowed)

        let second = Task { await gate.authorize("Allow action?") }
        let current = try await pending(in: gate)
        XCTAssertNotEqual(current.id, old.id)
        gate.resolve(old.id, allow: true)
        XCTAssertEqual(gate.pending?.id, current.id)

        gate.resolve(current.id, allow: false)
        let secondAllowed = await second.value
        XCTAssertFalse(secondAllowed)
        XCTAssertNil(gate.pending)
    }

    private func pending(in gate: AgentApprovalGate) async throws -> AgentApprovalGate.Request {
        for _ in 0..<50 {
            if let request = gate.pending { return request }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try XCTUnwrap(gate.pending)
    }
}
