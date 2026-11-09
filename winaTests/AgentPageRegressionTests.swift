import WebKit
import XCTest
@testable import wina

@MainActor
final class AgentPageRegressionTests: XCTestCase {
    private final class NavigationDelegate: NSObject, WKNavigationDelegate {
        let loaded: XCTestExpectation

        init(loaded: XCTestExpectation) {
            self.loaded = loaded
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded.fulfill()
        }
    }

    func testPageSearchReturnsOnlyValidatedNumericFields() async throws {
        let webView = await load("""
            <p>search needle</p>
            <script>JSON.stringify = () => '{"index":2,"count":4,"secret":"private data"}';</script>
            """)
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let next = try await call("page_search", ["action": "next"], navigator)
        XCTAssertEqual(next as? [String: Int], ["index": 2])
        let find = try await call("page_search", ["action": "find", "query": "needle"], navigator)
        XCTAssertEqual(find as? [String: Int], ["index": 2, "count": 4])

        _ = try await webView.evaluateJavaScript("JSON.stringify = () => '{\"index\":true}'; void 0;")
        do {
            _ = try await call("page_search", ["action": "previous"], navigator)
            XCTFail("A Boolean index is invalid")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Invalid page search result.")
        }
    }

    func testConsoleReportsAnExceptionAndAcceptsUndefined() async throws {
        let webView = await load("<p>console</p>")
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let success = try await call("console_evaluate", ["script": "void 0"], navigator)
        XCTAssertEqual(success["result"] as? String, "undefined")

        do {
            _ = try await call("console_evaluate", ["script": "throw new Error('fixture exception')"], navigator)
            XCTFail("A JavaScript exception must fail the tool call")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("fixture exception"), error.localizedDescription)
        }
    }

    func testLongMinifiedHTMLAndInlineScriptCanBeReadPastTheirPreviousCaps() async throws {
        let marker = "tail-marker"
        let prefix = String(repeating: "é", count: 51_000)
        let webView = await load("<script>/*\(prefix)\(marker)*/</script>")
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)

        let first = try await call("sources_list", ["section": "html"], navigator)
        let firstLine = try firstRow(first)
        XCTAssertEqual(firstLine["nextTextOffset"] as? Int, 2048)
        let document = try XCTUnwrap(first["documentId"] as? String)
        let matched = try await call("sources_list", ["section": "html", "query": marker, "documentId": document], navigator)
        let matchedLine = try firstRow(matched)
        XCTAssertTrue((matchedLine["text"] as? String)?.hasPrefix(marker) == true)
        XCTAssertGreaterThan(matchedLine["textOffset"] as? Int ?? 0, 50_000)

        let head = try await call("sources_detail", ["kind": "script", "index": 0], navigator)
        XCTAssertEqual(try firstRow(head)["nextTextOffset"] as? Int, 8192)
        let tail = try await call(
            "sources_detail", ["kind": "script", "index": 0, "textOffset": 51_002, "documentId": document], navigator
        )
        let entry = try firstRow(tail)
        XCTAssertEqual(entry["value"] as? String, marker + "*/")
        XCTAssertNil(entry["nextTextOffset"])
        withExtendedLifetime(webView) {}
    }

    func testLongStylesheetAndElementMarkupCanBeReadBeyondTheirFirstPage() async throws {
        let prefix = String(repeating: "a", count: 33_000)
        let webView = await load("""
            <style>p { --test: \(prefix)css-tail; }</style>
            <p error="ordinary attribute">\(prefix)markup-tail</p>
            """)
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)

        let css = try await call("sources_detail", ["kind": "stylesheet", "index": 0], navigator)
        let nextCSS = try XCTUnwrap(css["nextRawTextOffset"] as? Int)
        let cssTail = try await call("sources_detail", ["kind": "stylesheet", "index": 0, "textOffset": nextCSS], navigator)
        XCTAssertTrue((cssTail["raw"] as? String)?.contains("css-tail") == true)
        XCTAssertNil(cssTail["nextRawTextOffset"])

        let element = try await call(
            "sources_detail", ["kind": "element", "path": "0", "section": "html", "query": "markup-tail"], navigator
        )
        XCTAssertTrue((try firstRow(element)["value"] as? String)?.hasPrefix("markup-tail") == true)
        let attrs = try await call(
            "sources_detail", ["kind": "element", "path": "0.1.0", "section": "attributes"], navigator
        )
        let attribute = try firstRow(attrs)
        XCTAssertEqual(attribute["key"] as? String, "error")
        XCTAssertEqual(attribute["value"] as? String, "ordinary attribute")
    }

    private func call(
        _ tool: String, _ arguments: [String: Any], _ navigator: WebViewNavigator
    ) async throws -> [String: Any] {
        let result = try await AgentDevTools.call(
            tool, arguments: arguments, navigator: navigator,
            storage: StorageManager(), console: ConsoleSession(), authorize: { _ in true }
        )
        return try XCTUnwrap(result as? [String: Any])
    }

    private func firstRow(_ payload: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap((payload["entries"] as? [[String: Any]])?.first)
    }

    private func load(_ html: String) async -> WKWebView {
        let webView = WKWebView()
        let loaded = expectation(description: "Fixture loaded")
        let delegate = NavigationDelegate(loaded: loaded)
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 15)
        withExtendedLifetime(delegate) {}
        return webView
    }
}
