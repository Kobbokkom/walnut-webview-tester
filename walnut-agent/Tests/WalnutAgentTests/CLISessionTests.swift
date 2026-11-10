import Foundation
import os
import XCTest
@testable import WalnutAgent

final class CLISessionTests: XCTestCase {
    func testCatalogAndCallsShareOneOrderedSessionAfterErrors() async throws {
        var input = [
            #"{"op":"tools"}"#,
            #"{"op":"call","name":"walnut_browser","arguments":[]}"#,
            #"{"op":"call","name":"walnut_browser","arguments":{"action":"navigate","url":"https://example.test"}}"#,
            #"{"op":"call","name":"walnut_browser","arguments":{"action":"status"}}"#
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
            case "navigate":
                XCTAssertEqual(arguments["url"] as? String, "https://example.test")
                throw AgentError("Navigation was declined.")
            default:
                return ["runId": "observed-run", "data": ["url": "about:blank"]]
            }
        }
        var replies: [[String: Any]] = []
        let succeeded = try await session.run(read: { input.next() }, write: { line in
            XCTAssertEqual(line.last, 0x0A)
            replies.append(try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any]))
        })

        XCTAssertFalse(succeeded)
        XCTAssertEqual(calls.withLock { $0 }, ["tools", "navigate", "status"])
        XCTAssertEqual(replies.compactMap { $0["ok"] as? Bool }, [true, false, false, true])
        let catalog = try Self.result(in: XCTUnwrap(replies.first))
        XCTAssertEqual(catalog["mode"] as? String, "wkwebview")
        let catalogData = try XCTUnwrap(catalog["data"] as? [String: Any])
        let tools = try XCTUnwrap(catalogData["tools"] as? [[String: Any]])
        let schema = try XCTUnwrap(tools.first?["inputSchema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), ["action"])
        XCTAssertTrue(replies.contains { $0["error"] as? String == "Navigation was declined." })
        let status = try Self.result(in: XCTUnwrap(replies.last))
        XCTAssertEqual(status["runId"] as? String, "observed-run")
    }

    func testScreenshotReturnsPrivateFileAndRejectsInvalidBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAX+XDSwAAAABJRU5ErkJggg=="
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
        ].makeIterator()
        var replies: [[String: Any]] = []
        let succeeded = try await session.run(read: { input.next() }, write: { line in
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

    private static func result(in reply: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(reply["result"] as? [String: Any])
    }
}
