import Foundation
import os
import XCTest
@testable import WalnutAgent

final class RecordingDownloadTests: XCTestCase {
    func testMCPReturnsPrivateRecordingPathInsteadOfBase64() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let offsets = OSAllocatedUnfairLock(initialState: [Int]())
        let server = MCPServer(recordingDirectory: directory) { name, arguments in
            XCTAssertEqual(name, "walnut_recording")
            let offset = try XCTUnwrap(arguments["offset"] as? Int)
            offsets.withLock { $0.append(offset) }
            return Self.chunk(id: "recording", offset: offset)
        }
        let message = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"walnut_recording","arguments":{"action":"read"}}}"#.utf8)
        let response = await server.respond(to: message)
        let result = try XCTUnwrap(response?["result"] as? [String: Any])
        let envelope = try XCTUnwrap(result["structuredContent"] as? [String: Any])
        let details = try XCTUnwrap(envelope["data"] as? [String: Any])
        let path = try XCTUnwrap(details["path"] as? String)
        XCTAssertEqual(offsets.withLock { $0 }, [0, 3])
        XCTAssertEqual(details["size"] as? Int, 6)
        XCTAssertNil(details["data"])
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data("abcdef".utf8))
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }

    func testRecordingReplacementDiscardsPartialFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await RecordingDownload.save(using: { _, arguments in
                let offset = try XCTUnwrap(arguments["offset"] as? Int)
                return Self.chunk(id: offset == 0 ? "original" : "replacement", offset: offset)
            }, arguments: ["action": "read"], to: directory)
            XCTFail("Downloaded bytes from two different recordings")
        } catch {
            XCTAssertTrue(error is AgentError)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    private static func chunk(id: String, offset: Int) -> [String: Any] {
        let bytes = Data((offset == 0 ? "abc" : "def").utf8)
        return ["runId": "run", "data": [
            "recordingId": id,
            "mimeType": "video/quicktime",
            "data": bytes.base64EncodedString(),
            "offset": offset,
            "nextOffset": offset + bytes.count,
            "size": 6,
            "done": offset != 0
        ]]
    }
}
