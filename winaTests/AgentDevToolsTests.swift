import WebKit
import XCTest
@testable import wina

@MainActor
final class AgentDevToolsTests: XCTestCase {
    func testConsoleFiltersRetainedRecordsByDocumentAndHidesRawContent() async throws {
        let webView = WKWebView()
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let manager = navigator.consoleManager
        let first = UUID()
        let second = UUID()
        manager.agentDocumentID = first
        manager.addLog(type: "error", message: "secret log")
        manager.agentDocumentID = second
        manager.addLog(type: "error", message: "secret log")
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }

        XCTAssertEqual(manager.logs.count, 2, "Identical messages must not collapse across documents")
        let response = try await AgentDevTools.call(
            "console_list", arguments: ["documentId": second.uuidString], navigator: navigator,
            storage: StorageManager(), console: ConsoleSession(), authorize: { _ in false }
        )
        let result = try XCTUnwrap(response as? [String: Any])
        let rows = try XCTUnwrap(result["records"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["documentId"] as? String, second.uuidString)
        XCTAssertNil(rows.first?["message"])

        do {
            _ = try await AgentDevTools.call(
                "console_list", arguments: ["raw": true], navigator: navigator,
                storage: StorageManager(), console: ConsoleSession(), authorize: { _ in false }
            )
            XCTFail("Raw Console data requires approval")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The iPhone did not approve this action.")
        }
        withExtendedLifetime(webView) {}
    }

    func testApprovedConsoleReadIncludesStructuredContent() async throws {
        let webView = WKWebView()
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        var log = ConsoleLog(type: .dir, message: "", source: nil, timestamp: Date())
        log.objectValue = .array(ConsoleArray(elements: [.string("captured value")], totalCount: 5, isTruncated: true))
        navigator.consoleManager.logs = [log]

        let storage = StorageManager()
        let console = ConsoleSession()
        let list = try await AgentDevTools.call(
            "console_list", arguments: ["raw": true], navigator: navigator,
            storage: storage, console: console, authorize: { _ in true }
        )
        let listPayload = try XCTUnwrap(list as? [String: Any])
        let rows = try XCTUnwrap(listPayload["records"] as? [[String: Any]])
        XCTAssertEqual(rows.first?["arrayCount"] as? Int, 5)
        XCTAssertEqual(rows.first?["arrayTruncated"] as? Bool, true)
        XCTAssertTrue((rows.first?["object"] as? String)?.contains("captured value") == true)

        let detail = try await AgentDevTools.call(
            "console_detail", arguments: ["id": log.id.uuidString], navigator: navigator,
            storage: storage, console: console, authorize: { _ in true }
        )
        XCTAssertEqual((detail as? [String: Any])?["object"] as? String, rows.first?["object"] as? String)
        withExtendedLifetime(webView) {}
    }

    func testTighterClearPolicyRequiresApprovalEvenBeforeCapturingLogs() async throws {
        let webView = WKWebView()
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        XCTAssertTrue(navigator.consoleManager.logs.isEmpty)
        navigator.agentLogSettings.consoleClearStrategy = .keep
        navigator.agentLogSettings.consolePreserveLog = true

        let storage = StorageManager()
        let console = ConsoleSession()
        for arguments: [String: Any] in [["clearStrategy": "page"], ["preserveOnReload": false]] {
            do {
                _ = try await AgentDevTools.call(
                    "console_configure", arguments: arguments, navigator: navigator,
                    storage: storage, console: console, authorize: { _ in false }
                )
                XCTFail("A policy that can delete retained logs requires approval")
            } catch {
                XCTAssertEqual(error.localizedDescription, "The iPhone did not approve this action.")
            }
        }
        XCTAssertEqual(navigator.agentLogSettings.consoleClearStrategy, .keep)
        XCTAssertEqual(navigator.agentLogSettings.consolePreserveLog, true)
        withExtendedLifetime(webView) {}
    }

    func testValidationSeparatesBooleansFromIntegers() throws {
        XCTAssertThrowsError(try AgentDevInput(values: ["raw": 1]).bool("raw"))
        XCTAssertThrowsError(try AgentDevInput(values: ["limit": true]).int("limit", default: 30, range: 1...100))
        XCTAssertEqual(try AgentDevInput(values: ["limit": 5]).int("limit", default: 30, range: 1...100), 5)
    }
}
