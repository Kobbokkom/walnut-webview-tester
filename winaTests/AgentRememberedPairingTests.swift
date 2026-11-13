import Foundation
import XCTest
@testable import wina

@MainActor
final class AgentRememberedPairingTests: XCTestCase {
    func testSaveReplaceForgetAndInstallationLoss() throws {
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id, isDirectory: true)
        let store = AgentRememberedPairing.Store(directory: directory, account: id)
        defer {
            try? store.forget()
            try? FileManager.default.removeItem(at: directory)
        }

        XCTAssertNil(try store.load())
        let first = AgentRememberedPairing(key: Data(repeating: 1, count: 32), serviceName: "Walnut-first")
        try store.save(first)
        XCTAssertEqual(try store.load(), first)
        XCTAssertTrue(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)

        let replacement = AgentRememberedPairing(key: Data(repeating: 2, count: 32), serviceName: "Walnut-second")
        try store.save(replacement)
        XCTAssertEqual(try store.load(), replacement)

        try FileManager.default.removeItem(at: directory)
        XCTAssertNil(try store.load())
        try store.save(first)
        XCTAssertEqual(try store.load(), first)

        try store.forget()
        try store.forget()
        XCTAssertNil(try store.load())
    }
}
