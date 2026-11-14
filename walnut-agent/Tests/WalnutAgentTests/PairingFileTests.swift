import Darwin
import Foundation
import WalnutPairing
import XCTest
@testable import WalnutAgent

final class PairingFileTests: XCTestCase {
    func testPairingRequiresATerminalAndLeavesSavedMacUntouched() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("pairing.json")
        let saved = Pairing(version: 2, serviceName: "Walnut-Test", port: PairingWire.rememberedPort, key: Data(repeating: 19, count: 32))
        try saved.save(to: config)
        let original = try Data(contentsOf: config)

        let cli = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("walnut-agent")
        let process = Process()
        process.executableURL = cli
        process.arguments = ["pair"]
        process.environment = ProcessInfo.processInfo.environment.merging(["WALNUT_AGENT_CONFIG": config.path]) { _, value in value }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let output = Pipe()
        process.standardError = output
        let exited = expectation(description: "Noninteractive pairing exits")
        process.terminationHandler = { _ in exited.fulfill() }
        try process.run()
        try? output.fileHandleForWriting.close()
        defer { if process.isRunning { process.terminate() } }
        await fulfillment(of: [exited], timeout: 5)
        guard !process.isRunning else { return }
        XCTAssertNotEqual(process.terminationStatus, 0)
        let diagnostic = try XCTUnwrap(String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8))
        XCTAssertTrue(diagnostic.contains("confirm the numbers match"), diagnostic)
        XCTAssertEqual(try Data(contentsOf: config), original)
    }

    func testRememberedPairingLoadsFromPrivateConfigButCannotBeImported() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("pairing.json")
        let pairing = Pairing(version: 2, serviceName: "Walnut-Test", port: PairingWire.rememberedPort, key: Data(repeating: 19, count: 32))
        try pairing.save(to: config)
        XCTAssertEqual(try Pairing.load(from: config), pairing)

        let exported = directory.appendingPathComponent("pairing.txt")
        let token = try "walnut-agent:" + JSONEncoder().encode(pairing).base64EncodedString()
        try Data(token.utf8).write(to: exported)
        XCTAssertThrowsError(try Pairing.fromToken(token))
        XCTAssertThrowsError(try Pairing.fromFile(at: exported))

        let invalid = Pairing(version: 2, serviceName: pairing.serviceName, port: PairingWire.port, key: pairing.key)
        XCTAssertThrowsError(try Pairing.decode(JSONEncoder().encode(invalid)))
    }

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
