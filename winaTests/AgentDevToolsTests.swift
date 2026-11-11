import SwiftUI
import WebKit
import XCTest
@testable import wina

@MainActor
final class AgentDevToolsTests: XCTestCase {
    func testAccessibilitySearchAndDetailUseTheRetainedIssue() async throws {
        let webView = WKWebView()
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        defer { withExtendedLifetime(webView) {} }
        let markup = "<img data-fixture=\"" + String(repeating: "가🙂", count: 40_000) + "\">"
        let issue = AccessibilityIssue(
            severity: .error, category: .images, help: "Missing description", failureSummary: "Add alternative text",
            element: "<img>", fullHtml: markup, selector: "#picture", helpUrl: nil, ruleId: "image-alt"
        )
        navigator.accessibilityManager.issues = [issue]
        let context = AgentDevContext(navigator: navigator) { _ in true }
        for query in ["IMAGE-ALT", "Images", "#picture"] {
            let value = try await AgentDevTools.callPage(
                "accessibility_audit", AgentDevInput(values: ["run": false, "query": query]), context
            )
            let result = try XCTUnwrap(value as? [String: Any])
            XCTAssertEqual(result["total"] as? Int, 1)
        }

        let id = issue.id.uuidString
        let first = try await AgentDevTools.callPage(
            "accessibility_detail", AgentDevInput(values: ["id": id]), context
        )
        let prefix = try XCTUnwrap(first as? [String: Any])
        let offset = try XCTUnwrap(prefix["nextByteOffset"] as? Int)
        let contentID = try XCTUnwrap(prefix["contentId"] as? String)
        let second = try await AgentDevTools.callPage(
            "accessibility_detail", AgentDevInput(values: ["id": id, "byteOffset": offset, "contentId": contentID]), context
        )
        let suffix = try XCTUnwrap(second as? [String: Any])
        let initialContent = try XCTUnwrap(prefix["content"] as? String)
        let remainingContent = try XCTUnwrap(suffix["content"] as? String)
        XCTAssertEqual(initialContent.utf8.count, offset)
        XCTAssertNil(suffix["nextByteOffset"])
        let joined = Data((initialContent + remainingContent).utf8)
        let detail = try XCTUnwrap(JSONSerialization.jsonObject(with: joined) as? [String: Any])
        XCTAssertEqual(detail["html"] as? String, markup)
        XCTAssertEqual(detail["failure"] as? String, "Add alternative text")
    }

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

    func testConsoleDetailAndJSONExportContinueFullRetainedRecord() async throws {
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

        func export(_ cursor: [String: Any] = [:]) async throws -> [String: Any] {
            var arguments = cursor
            arguments["format"] = "json"
            let response = try await AgentDevTools.call(
                "console_list", arguments: arguments, navigator: navigator,
                storage: storage, console: console, authorize: { _ in true }
            )
            return try XCTUnwrap(response as? [String: Any])
        }

        let firstExport = try await export()
        let exportPrefix = try XCTUnwrap(firstExport["records"] as? String)
        let exportOffset = try XCTUnwrap(firstExport["nextByteOffset"] as? Int)
        let exportId = try XCTUnwrap(firstExport["contentId"] as? String)
        XCTAssertEqual(exportPrefix.utf8.count, exportOffset)
        let lastExport = try await export(["byteOffset": exportOffset, "contentId": exportId])
        let exportSuffix = try XCTUnwrap(lastExport["records"] as? String)
        XCTAssertEqual(exportPrefix + exportSuffix, "[" + prefix + suffix + "]")
        XCTAssertNil(lastExport["nextByteOffset"])
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

        let empty = ConsoleLog(type: .log, message: "", source: nil, timestamp: newer.timestamp)
        let headingLength = ConsoleExporter.exportAsText([empty]).utf8.count
        let boundary = ConsoleLog(
            type: .log, message: String(repeating: "x", count: 256 * 1024 - headingLength),
            source: nil, timestamp: newer.timestamp
        )
        navigator.consoleManager.logs = [older, boundary]
        let boundaryStart = try await export()
        let boundaryOffset = try XCTUnwrap(boundaryStart["nextByteOffset"] as? Int)
        let boundaryId = try XCTUnwrap(boundaryStart["contentId"] as? String)
        XCTAssertEqual(boundaryOffset, 256 * 1024)
        XCTAssertEqual(boundaryStart["records"] as? String, ConsoleExporter.exportAsText([boundary]))
        let boundaryEnd = try await export(["byteOffset": boundaryOffset, "contentId": boundaryId])
        XCTAssertEqual(boundaryEnd["records"] as? String, "\n\n" + ConsoleExporter.exportAsText([older]))
        withExtendedLifetime(webView) {}
    }

    func testConsoleExportAllowsCancellationAfterApproval() async throws {
        let webView = WKWebView()
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        navigator.consoleManager.logs = (0..<30).map {
            ConsoleLog(type: .log, message: "record \($0)", source: nil, timestamp: Date())
        }

        var exportTask: Task<Void, Error>?
        exportTask = Task { @MainActor in
            _ = try await AgentDevTools.call(
                "console_list", arguments: ["format": "json"], navigator: navigator,
                storage: StorageManager(), console: ConsoleSession(), authorize: { _ in
                    Task { @MainActor in exportTask?.cancel() }
                    return true
                }
            )
        }
        let task = try XCTUnwrap(exportTask)
        do {
            try await task.value
            XCTFail("The export must let the queued cancellation run before returning")
        } catch is CancellationError {
            // Expected.
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

    func testNetworkTextAndJSONExportsContinueWithoutMixingChangedPages() async throws {
        let webView = WKWebView()
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let requestStart = Date(timeIntervalSince1970: 1_700_000_000)
        let request = NetworkRequest(
            id: UUID(), method: "GET", url: "https://example.com/" + String(repeating: "🙂", count: 70_000),
            requestHeaders: nil, startTime: requestStart, pageIsSecure: true, status: 503,
            endTime: requestStart.addingTimeInterval(0.125), error: "Fixture request failed", requestType: .fetch
        )
        let resource = ResourceEntry(
            id: UUID(), name: "https://example.com/final.css", initiatorType: .link,
            startTime: 1, duration: 1, transferSize: 1, encodedBodySize: 1, decodedBodySize: 1,
            dnsTime: 0, tcpTime: 0, tlsTime: 0, requestTime: 0, responseTime: 0, timestamp: Date()
        )
        let restrictedResource = ResourceEntry(
            id: UUID(), name: "https://other.example/hidden.css", initiatorType: .link,
            startTime: 1, duration: 42, transferSize: 0, encodedBodySize: 0, decodedBodySize: 0,
            dnsTime: 0, tcpTime: 0, tlsTime: 0, requestTime: 0, responseTime: 0, timestamp: Date()
        )
        navigator.resourceManager.resources = [restrictedResource, resource]

        let storage = StorageManager()
        let console = ConsoleSession()
        func export(_ format: String, cursor: [String: Any] = [:], approved: Bool = true) async throws -> [String: Any] {
            var arguments = cursor
            arguments["format"] = format
            let response = try await AgentDevTools.call(
                "network_list", arguments: arguments, navigator: navigator,
                storage: storage, console: console, authorize: { _ in approved }
            )
            return try XCTUnwrap(response as? [String: Any])
        }

        for format in ["text", "json"] {
            navigator.networkManager.requests = [request]
            let first = try await export(format)
            let prefix = try XCTUnwrap(first["export"] as? String)
            let next = try XCTUnwrap(first["nextByteOffset"] as? Int)
            let contentId = try XCTUnwrap(first["contentId"] as? String)
            XCTAssertEqual(prefix.utf8.count, next)
            XCTAssertLessThanOrEqual(next, 256 * 1024)
            let cursor: [String: Any] = ["byteOffset": next, "contentId": contentId]
            let last = try await export(format, cursor: cursor)
            let suffix = try XCTUnwrap(last["export"] as? String)
            XCTAssertNil(last["nextByteOffset"])
            XCTAssertEqual(last["requestCount"] as? Int, 1)
            XCTAssertEqual(last["resourceCount"] as? Int, 2)
            if format == "text" {
                let timestamp = DateFormatter()
                timestamp.dateFormat = "HH:mm:ss.SSS"
                XCTAssertEqual(prefix + suffix, """
                    [\(timestamp.string(from: requestStart))] GET \(request.url) → 503 (125ms) ERROR: Fixture request failed

                    [Stylesheet] \(resource.name)
                      Duration: 1ms, Size: \(resource.displaySize)

                    [Stylesheet] \(restrictedResource.name)
                      Duration: 42ms, Size: — (cross-origin)
                    """)
            } else {
                let rows = try XCTUnwrap(AgentDevTools.parseJSON(prefix + suffix) as? [String: [[String: Any]]])
                XCTAssertEqual(rows["requests"]?.first?["url"] as? String, request.url)
                XCTAssertEqual(rows["resources"]?.first?["url"] as? String, resource.name)
            }

            do {
                _ = try await export(format, cursor: cursor, approved: false)
                XCTFail("A Network continuation still needs approval")
            } catch {
                XCTAssertEqual(error.localizedDescription, "The iPhone did not approve this action.")
            }
            navigator.networkManager.requests = []
            do {
                _ = try await export(format, cursor: cursor)
                XCTFail("A Network continuation must reject a changed page")
            } catch {
                XCTAssertEqual(error.localizedDescription, "The Network content changed. Start reading it again.")
            }
            let small = try await export(format)
            XCTAssertNotNil(small["export"] as? String)
            XCTAssertNil(small["nextByteOffset"])
        }
        withExtendedLifetime(webView) {}
    }

    func testNetworkOverviewReturnsCapturedStackOnlyWithRawApproval() async throws {
        let webView = WKWebView()
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let frames = (0..<10).map {
            StackFrame(functionName: "function\($0)", fileName: "https://example.com/test.js", lineNumber: $0, columnNumber: 1)
        }
        let request = NetworkRequest(
            id: UUID(), method: "GET", url: "https://example.com/", requestHeaders: nil, startTime: Date(),
            pageIsSecure: true, requestType: .fetch, stackFrames: frames
        )
        navigator.networkManager.requests = [request]
        let storage = StorageManager()
        let console = ConsoleSession()
        let sanitized = try await AgentDevTools.call(
            "network_detail", arguments: ["id": request.id.uuidString], navigator: navigator,
            storage: storage, console: console, authorize: { _ in false }
        )
        XCTAssertNil((sanitized as? [String: Any])?["stack"])
        let approved = try await AgentDevTools.call(
            "network_detail", arguments: ["id": request.id.uuidString, "raw": true], navigator: navigator,
            storage: storage, console: console, authorize: { _ in true }
        )
        let stack = try XCTUnwrap((approved as? [String: Any])?["stack"] as? [[String: Any]])
        XCTAssertEqual(stack.compactMap { $0["functionName"] as? String }, frames.map(\.functionName))
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

    func testNativeLogSettingsShowSessionValuesAndSaveOnlyEditedOptions() {
        let navigator = WebViewNavigator()
        navigator.agentLogSettings.consolePreserveLog = true
        navigator.agentLogSettings.consoleClearStrategy = .page
        navigator.agentLogSettings.networkClearStrategy = .origin
        var savedPreserve = false
        var savedStrategy = LogClearStrategy.keep
        let preserve = AgentLogSettings.binding(
            Binding(get: { savedPreserve }, set: { savedPreserve = $0 }),
            navigator: navigator, override: \.consolePreserveLog
        )
        let strategy = AgentLogSettings.binding(
            Binding(get: { savedStrategy }, set: { savedStrategy = $0 }),
            navigator: navigator, override: \.networkClearStrategy
        )

        XCTAssertTrue(preserve.wrappedValue)
        XCTAssertEqual(strategy.wrappedValue, .origin)
        XCTAssertFalse(savedPreserve)
        XCTAssertEqual(savedStrategy, .keep)

        preserve.wrappedValue = false
        strategy.wrappedValue = .page
        XCTAssertNil(navigator.agentLogSettings.consolePreserveLog)
        XCTAssertNil(navigator.agentLogSettings.networkClearStrategy)
        XCTAssertEqual(navigator.agentLogSettings.consoleClearStrategy, .page)

        navigator.agentLogSettings = AgentLogSettings()
        XCTAssertFalse(preserve.wrappedValue)
        XCTAssertEqual(strategy.wrappedValue, .page)
    }

    func testConsoleLevelFiltersApplyOnlyToTheQuery() async throws {
        let webView = WKWebView()
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        defer { withExtendedLifetime(webView) {} }
        navigator.consoleManager.logs = [ConsoleLog.LogType.log, .warn, .error].map {
            ConsoleLog(type: $0, message: $0.rawValue, source: nil, timestamp: Date())
        }
        let storage = StorageManager()
        let console = ConsoleSession()
        console.enabledLogTypes = [.log]

        func list(_ arguments: [String: Any]) async throws -> [String] {
            let result = try await AgentDevTools.call(
                "console_list", arguments: arguments, navigator: navigator,
                storage: storage, console: console, authorize: { _ in false }
            )
            let response = try XCTUnwrap(result as? [String: Any])
            let rows = try XCTUnwrap(response["records"] as? [[String: Any]])
            return rows.compactMap { $0["type"] as? String }
        }

        let filters: [[String: Any]] = [["types": ["warn", "error"]], ["type": "warn"], ["types": [String]()], [:]]
        for (filter, expected) in zip(filters, [["error", "warn"], ["warn"], [], ["log"]]) {
            let result = try await list(filter)
            XCTAssertEqual(result, expected)
        }
        let conflicting = try? await list(["type": "warn", "types": ["error"]])
        XCTAssertNil(conflicting)
        XCTAssertEqual(console.enabledLogTypes, [.log])
    }

    func testValidationSeparatesBooleansFromIntegers() throws {
        XCTAssertThrowsError(try AgentDevInput(values: ["raw": 1]).bool("raw"))
        XCTAssertThrowsError(try AgentDevInput(values: ["limit": true]).int("limit", default: 30, range: 1...100))
        XCTAssertEqual(try AgentDevInput(values: ["limit": 5]).int("limit", default: 30, range: 1...100), 5)
    }
}
