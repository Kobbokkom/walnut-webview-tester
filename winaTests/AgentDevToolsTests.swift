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

    func testConsoleRegexSearchesCompleteRetainedMessage() async throws {
        let webView = WKWebView()
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let message = String(repeating: "x", count: 3_000) + "tail marker"
        let log = ConsoleLog(type: .log, message: message, source: nil, timestamp: Date())
        navigator.consoleManager.logs = [log]

        let response = try await AgentDevTools.call(
            "console_list", arguments: ["query": "tail marker$", "regex": true], navigator: navigator,
            storage: StorageManager(), console: ConsoleSession(), authorize: { _ in true }
        )
        let result = try XCTUnwrap(response as? [String: Any])
        let rows = try XCTUnwrap(result["records"] as? [[String: Any]])
        XCTAssertEqual(rows.first?["id"] as? String, log.id.uuidString)
        XCTAssertNil(rows.first?["message"])

        let expensiveMatch = ConsoleLog(
            type: .log, message: String(repeating: "a", count: 100_000) + "!", source: nil, timestamp: Date()
        )
        navigator.consoleManager.logs = [expensiveMatch]
        do {
            _ = try await AgentDevTools.call(
                "console_list", arguments: ["query": "^(a+)+$", "regex": true], navigator: navigator,
                storage: StorageManager(), console: ConsoleSession(), authorize: { _ in true }
            )
            XCTFail("An unfinished Console regex search must surface an error")
        } catch let error as AgentError {
            XCTAssertTrue([
                "The Console search pattern exceeded its time limit.",
                "The Console search pattern could not complete."
            ].contains(error.localizedDescription))
        }
        withExtendedLifetime(webView) {}
    }

    func testConsoleDetailContinuesFullRetainedRecord() async throws {
        let webView = WKWebView()
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let message = String(repeating: "🙂", count: 70_000)
        let stack = String(repeating: "s", count: 5_000) + "stack tail"
        let object = String(repeating: "o", count: 33_000) + "object tail"
        let table = (0..<25).map { ["index": String($0), "value": String(repeating: "v", count: 300)] }
        var log = ConsoleLog(type: .table, message: message, source: nil, timestamp: Date())
        log.stackTrace = stack
        log.objectValue = .string(object)
        log.tableData = table
        navigator.consoleManager.logs = [log]

        let storage = StorageManager()
        let console = ConsoleSession()
        func detail(_ cursor: [String: Any] = [:]) async throws -> [String: Any] {
            var arguments = cursor
            arguments["id"] = log.id.uuidString
            let response = try await AgentDevTools.call(
                "console_detail", arguments: arguments, navigator: navigator,
                storage: storage, console: console, authorize: { _ in true }
            )
            return try XCTUnwrap(response as? [String: Any])
        }

        let first = try await detail()
        let prefix = try XCTUnwrap(first["content"] as? String)
        let next = try XCTUnwrap(first["nextByteOffset"] as? Int)
        let contentId = try XCTUnwrap(first["contentId"] as? String)
        XCTAssertEqual(prefix.utf8.count, next)
        XCTAssertLessThanOrEqual(next, 256 * 1024)

        let second = try await detail(["byteOffset": next, "contentId": contentId])
        let suffix = try XCTUnwrap(second["content"] as? String)
        XCTAssertNil(second["nextByteOffset"])
        let record = try XCTUnwrap(AgentDevTools.parseJSON(prefix + suffix) as? [String: Any])
        XCTAssertEqual(record["message"] as? String, message)
        XCTAssertEqual(record["stack"] as? String, stack)
        XCTAssertEqual(record["object"] as? String, log.objectValue?.copyableString)
        XCTAssertEqual(record["table"] as? [[String: String]], table)
        withExtendedLifetime(webView) {}
    }

    func testConsoleTextExportContinuesWithoutMixingChangedPages() async throws {
        let webView = WKWebView()
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let message = String(repeating: "🙂", count: 70_000)
        let older = ConsoleLog(type: .log, message: "older record", source: nil, timestamp: Date())
        let newer = ConsoleLog(type: .log, message: message, source: nil, timestamp: Date())
        navigator.consoleManager.logs = [older, newer]
        let storage = StorageManager()
        let console = ConsoleSession()
        func export(_ cursor: [String: Any] = [:], approved: Bool = true) async throws -> [String: Any] {
            var arguments = cursor
            arguments["format"] = "text"
            let response = try await AgentDevTools.call(
                "console_list", arguments: arguments, navigator: navigator,
                storage: storage, console: console, authorize: { _ in approved }
            )
            return try XCTUnwrap(response as? [String: Any])
        }

        let first = try await export()
        let prefix = try XCTUnwrap(first["records"] as? String)
        let next = try XCTUnwrap(first["nextByteOffset"] as? Int)
        let contentId = try XCTUnwrap(first["contentId"] as? String)
        XCTAssertEqual(prefix.utf8.count, next)
        let cursor: [String: Any] = ["byteOffset": next, "contentId": contentId]
        let second = try await export(cursor)
        let suffix = try XCTUnwrap(second["records"] as? String)
        XCTAssertEqual(prefix + suffix, ConsoleExporter.exportAsText([newer, older], includeObjects: true))
        XCTAssertNil(second["nextByteOffset"])

        let invalidCursor: [String: Any] = ["byteOffset": next + 1, "contentId": contentId]
        do {
            _ = try await export(invalidCursor)
            XCTFail("A cursor cannot start inside a UTF-8 scalar")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Invalid Console byte offset"))
        }
        do {
            _ = try await export(cursor, approved: false)
            XCTFail("A continuation still needs approval")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The iPhone did not approve this action.")
        }
        navigator.consoleManager.logs = [older]
        do {
            _ = try await export(cursor)
            XCTFail("Changed export content must reject the old cursor")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The Console content changed. Start reading it again.")
        }
        withExtendedLifetime(webView) {}
    }

    func testNetworkSearchUsesDecodedResourceNameOnlyWithRawApproval() async throws {
        let webView = WKWebView()
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let entry = ResourceEntry(
            id: UUID(), name: "https://example.com/fixture%20asset.css", initiatorType: .link,
            startTime: 1, duration: 1, transferSize: 1, encodedBodySize: 1, decodedBodySize: 1,
            dnsTime: 0, tcpTime: 0, tlsTime: 0, requestTime: 0, responseTime: 0, timestamp: Date()
        )
        navigator.resourceManager.resources = [entry]
        let storage = StorageManager()
        let console = ConsoleSession()

        let sanitized = try await AgentDevTools.call(
            "network_list", arguments: ["query": "fixture asset.css"], navigator: navigator,
            storage: storage, console: console, authorize: { _ in false }
        )
        XCTAssertEqual((sanitized as? [String: Any])?["resourceCount"] as? Int, 0)
        let approved = try await AgentDevTools.call(
            "network_list", arguments: ["query": "fixture asset.css", "raw": true], navigator: navigator,
            storage: storage, console: console, authorize: { _ in true }
        )
        XCTAssertEqual((approved as? [String: Any])?["resourceCount"] as? Int, 1)
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
