import Darwin
import Foundation
import XCTest
@testable import WalnutAgent

final class PairingFileTests: XCTestCase {
    func testImportsAirDroppedTokenWithoutChangingOriginalFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Walnut-pairing.txt")
        let pairing = Pairing(version: 1, serviceName: "Walnut-Test", port: 44_333, key: Data(repeating: 13, count: 32))
        let token = try "walnut-agent:" + JSONEncoder().encode(pairing).base64EncodedString()
        try Data((token + "\n").utf8).write(to: file)
        XCTAssertEqual(chmod(file.path, 0o644), 0)

        XCTAssertEqual(try Pairing.fromFile(at: file), pairing)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), token + "\n")
    }

    func testRejectsSymlinkDirectoryOversizedAndInvalidUTF8Imports() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("pairing.txt")
        let link = directory.appendingPathComponent("link.txt")
        try Data("walnut-agent:invalid".utf8).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try Pairing.fromFile(at: link))
        XCTAssertThrowsError(try Pairing.fromFile(at: directory))
        try Data(repeating: 65, count: 1025).write(to: file)
        XCTAssertThrowsError(try Pairing.fromFile(at: file))
        try Data([0xff]).write(to: file)
        XCTAssertThrowsError(try Pairing.fromFile(at: file))
    }
}
