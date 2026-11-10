import Foundation
import os
import XCTest
@testable import WalnutAgent

final class CLISessionTests: XCTestCase {
    func testCatalogAndCallsShareOneOrderedSessionAfterErrors() async throws {
        let invalidUTF8 = Data(#"{"op":"call","name":"page_interact","arguments":{"action":"fill","text":""#.utf8)
            + Data([0xFF]) + Data(#""}}"#.utf8)
        var input = [
            Data(#"{"op":"tools"}"#.utf8),
            Data(#"{"op":"call","name":"walnut_capabilities"}"#.utf8),
            Data(#"{"op":"call","name":"walnut_recording","arguments":{"action":"read","offset":512}}"#.utf8),
            invalidUTF8,
            Data(#"{"op":"call","name":"walnut_browser","arguments":[]}"#.utf8),
            Data(#"{"op":"call","name":"walnut_browser","arguments":{"action":"open","url":"https://example.test"}}"#.utf8),
            Data(#"{"op":"call","name":"walnut_browser","arguments":{"action":"status"}}"#.utf8)
        ].makeIterator()
        let calls = OSAllocatedUnfairLock(initialState: [String]())
        let session = CLISession { name, arguments in
            let action = try XCTUnwrap(name == "walnut_capabilities" ? "tools" : arguments["action"] as? String)
            calls.withLock { $0.append(action) }
            switch action {
            case "tools":
                let properties = ["action": ["type": "string"], "offset": ["type": "integer"]]
                let recording: [String: Any] = ["name": "walnut_recording", "inputSchema": ["properties": properties]]
                return ["mode": "wkwebview", "data": ["tools": [recording]]]
            case "open":
                XCTAssertEqual(arguments["url"] as? String, "https://example.test")
                throw AgentError("Navigation was declined.")
            default:
                return ["runId": "observed-run", "data": ["url": "about:blank"]]
            }
        }
        var replies: [[String: Any]] = []
        let succeeded = try await session.run(read: { input.next().map { .success($0) } }, write: { line in
            XCTAssertEqual(line.last, 0x0A)
            replies.append(try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any]))
        })

        XCTAssertFalse(succeeded)
        XCTAssertEqual(calls.withLock { $0 }, ["tools", "tools", "open", "status"])
        XCTAssertEqual(replies.compactMap { $0["ok"] as? Bool }, [true, true, false, false, false, false, true])
        let catalog = try Self.result(in: XCTUnwrap(replies.first))
        let catalogByName = try Self.result(in: replies[1])
        XCTAssertEqual(catalog as NSDictionary, catalogByName as NSDictionary)
        XCTAssertEqual(catalog["mode"] as? String, "wkwebview")
        let catalogData = try XCTUnwrap(catalog["data"] as? [String: Any])
        let tools = try XCTUnwrap(catalogData["tools"] as? [[String: Any]])
        let schema = try XCTUnwrap(tools.first?["inputSchema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), ["action"])
        XCTAssertEqual(replies[3]["error"] as? String, "Session requests must use UTF-8.")
        XCTAssertTrue(replies.contains { $0["error"] as? String == "Navigation was declined." })
        let status = try Self.result(in: XCTUnwrap(replies.last))
        XCTAssertEqual(status["runId"] as? String, "observed-run")
    }

    func testScreenshotReturnsPrivateFileAndRejectsInvalidBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base64 = Self.png
        let session = CLISession(screenshotDirectory: directory) { name, arguments in
            XCTAssertEqual(name, "walnut_screenshot")
            let saveToPhotos = arguments["saveToPhotos"] as? Bool ?? false
            let image: [String: Any] = [
                "mimeType": "image/png", "data": saveToPhotos ? "invalid base64!" : base64, "savedToPhotos": false
            ]
            return ["runId": "capture", "data": image]
        }
        var input = [
            #"{"op":"call","name":"walnut_screenshot"}"#,
            #"{"op":"call","name":"walnut_screenshot","arguments":{"saveToPhotos":true}}"#
        ].map { Data($0.utf8) }.makeIterator()
        var replies: [[String: Any]] = []
        let succeeded = try await session.run(read: { input.next().map { .success($0) } }, write: { line in
            replies.append(try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any]))
        })

        XCTAssertFalse(succeeded)
        XCTAssertEqual(replies.compactMap { $0["ok"] as? Bool }, [true, false])
        let envelope = try Self.result(in: XCTUnwrap(replies.first))
        XCTAssertEqual(envelope["runId"] as? String, "capture")
        let details = try XCTUnwrap(envelope["data"] as? [String: Any])
        let path = try XCTUnwrap(details["path"] as? String)
        let file = URL(fileURLWithPath: path)
        XCTAssertEqual(file.pathExtension, "png")
        XCTAssertNil(details["data"])
        XCTAssertEqual(try Data(contentsOf: file), try XCTUnwrap(Data(base64Encoded: base64)))
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [file.lastPathComponent])
    }

    func testFailedMacScreenshotWritePreservesPhotosResult() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: file) }
        let session = CLISession(screenshotDirectory: file) { _, arguments in
            XCTAssertEqual(arguments["saveToPhotos"] as? Bool, true)
            return ["runId": "capture", "data": ["mimeType": "image/png", "data": Self.png, "savedToPhotos": true]]
        }
        var input = [Data(#"{"op":"call","name":"walnut_screenshot","arguments":{"saveToPhotos":true}}"#.utf8)].makeIterator()
        var reply: [String: Any] = [:]
        let succeeded = try await session.run(read: { input.next().map { .success($0) } }, write: { line in
            reply = try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
        })

        XCTAssertFalse(succeeded)
        XCTAssertEqual(reply["ok"] as? Bool, false)
        XCTAssertNotNil(reply["error"])
        let result = try Self.result(in: reply)
        XCTAssertEqual(result["runId"] as? String, "capture")
        let data = try XCTUnwrap(result["data"] as? [String: Any])
        XCTAssertEqual(data["savedToPhotos"] as? Bool, true)
        XCTAssertNil(data["path"])
        XCTAssertNil(data["data"])
    }

    private static let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAX+XDSwAAAABJRU5ErkJggg=="

    private static func result(in reply: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(reply["result"] as? [String: Any])
    }
}
