import Foundation
import XCTest
@testable import wina

final class AgentPairingFileTests: XCTestCase {
    func testExportUsesPrivateTemporaryFileAndCanBeRemoved() throws {
        let token = "walnut-agent:test-token"
        let export = try AgentPairingFile(code: token)
        defer { export.remove() }

        XCTAssertEqual(export.url.lastPathComponent, "Walnut-pairing.txt")
        XCTAssertEqual(try String(contentsOf: export.url, encoding: .utf8), token)
        let file = try FileManager.default.attributesOfItem(atPath: export.url.path)
        let directory = try FileManager.default.attributesOfItem(atPath: export.url.deletingLastPathComponent().path)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((directory[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        export.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.url.path))
    }
}
