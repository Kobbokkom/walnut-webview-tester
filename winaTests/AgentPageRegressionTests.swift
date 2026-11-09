import WebKit
import XCTest
@testable import wina

@MainActor
final class AgentPageRegressionTests: XCTestCase {
    private final class SourcesNavigator: WebViewNavigator {
        private(set) var resultBytes = 0

        override func evaluateJavaScriptReportingErrors(_ script: String, contentWorld: WKContentWorld) async throws -> Any? {
            let value = try await super.evaluateJavaScriptReportingErrors(script, contentWorld: contentWorld)
            resultBytes = (value as? String)?.utf8.count ?? 0
            return value
        }
    }

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
        let marker = "Tail.[marker]"
        let prefix = String(repeating: "🧪", count: 51_000)
        let webView = await load("<script>/*\(prefix)\(marker)*/</script>")
        let navigator = SourcesNavigator()
        navigator.attach(to: webView)

        let first = try await call("sources_list", ["section": "html"], navigator)
        let firstLine = try firstRow(first)
        XCTAssertEqual(firstLine["nextTextOffset"] as? Int, 2048)
        XCTAssertLessThan(navigator.resultBytes, 10_000, "Raw HTML transfers only the requested text page")
        let document = try XCTUnwrap(first["documentId"] as? String)
        let matched = try await call("sources_list", ["section": "html", "query": marker.lowercased(), "documentId": document], navigator)
        let matchedLine = try firstRow(matched)
        XCTAssertTrue((matchedLine["text"] as? String)?.hasPrefix(marker) == true)
        XCTAssertGreaterThan(matchedLine["textOffset"] as? Int ?? 0, 50_000)

        let scripts = try await call("sources_list", ["section": "scripts", "query": marker.lowercased()], navigator)
        XCTAssertEqual(try firstRow(scripts)["index"] as? Int, 0)
        XCTAssertLessThan(navigator.resultBytes, 1024, "Script search sends metadata only")

        let head = try await call("sources_detail", ["kind": "script", "index": 0], navigator)
        XCTAssertEqual(try firstRow(head)["nextTextOffset"] as? Int, 8192)
        XCTAssertLessThan(navigator.resultBytes, 40_000, "Script details transfer only the requested text page")
        let tail = try await call(
            "sources_detail", ["kind": "script", "index": 0, "textOffset": 51_002, "documentId": document], navigator
        )
        let entry = try firstRow(tail)
        XCTAssertEqual(entry["value"] as? String, marker + "*/")
        XCTAssertNil(entry["nextTextOffset"])
        XCTAssertLessThan(navigator.resultBytes, 1024)
        withExtendedLifetime(webView) {}
    }

    func testLongStylesheetAndElementMarkupCanBeReadBeyondTheirFirstPage() async throws {
        let prefix = String(repeating: "a", count: 33_000)
        let webView = await load("""
            <style>p { --test: \(prefix)css-tail; }</style>
            <p error="ordinary attribute">\(prefix)markup-tail</p>
            """)
        defer { withExtendedLifetime(webView) {} }
        let navigator = SourcesNavigator()
        navigator.attach(to: webView)

        let css = try await call("sources_detail", ["kind": "stylesheet", "index": 0], navigator)
        let nextCSS = try XCTUnwrap(css["nextRawTextOffset"] as? Int)
        XCTAssertLessThan(navigator.resultBytes, 36_000, "Stylesheet details transfer only the selected chunks")
        let cssTail = try await call("sources_detail", ["kind": "stylesheet", "index": 0, "textOffset": nextCSS], navigator)
        XCTAssertTrue((cssTail["raw"] as? String)?.contains("css-tail") == true)
        XCTAssertNil(cssTail["nextRawTextOffset"])

        let element = try await call(
            "sources_detail", ["kind": "element", "path": "0", "section": "html", "query": "markup-tail"], navigator
        )
        XCTAssertTrue((try firstRow(element)["value"] as? String)?.hasPrefix("markup-tail") == true)
        XCTAssertLessThan(navigator.resultBytes, 1024, "Element HTML does not transfer the entire element twice")
        let attrs = try await call(
            "sources_detail", ["kind": "element", "path": "0.1.0", "section": "attributes"], navigator
        )
        let attribute = try firstRow(attrs)
        XCTAssertEqual(attribute["key"] as? String, "error")
        XCTAssertEqual(attribute["value"] as? String, "ordinary attribute")
    }

    func testSourcesSearchPreservesUnicodeMatchesAndOriginalScalarOffsets() async throws {
        let prefix = "/*🧪"
        let decomposed = "Cafe\u{301}"
        let webView = await load("<script>\(prefix)\(decomposed) Straße*/</script>")
        defer { withExtendedLifetime(webView) {} }
        let navigator = SourcesNavigator()
        navigator.attach(to: webView)

        for (query, expectedText, expectedPrefix) in [
            ("CAFÉ", decomposed, prefix),
            ("STRASSE", "Straße", prefix + decomposed + " ")
        ] {
            let args: [String: Any] = ["kind": "script", "index": 0, "query": query]
            let page = try await call("sources_detail", args, navigator)
            let entry = try firstRow(page)
            let offset = try XCTUnwrap(entry["textOffset"] as? Int)
            XCTAssertEqual(offset, expectedPrefix.unicodeScalars.count)
            XCTAssertTrue((entry["value"] as? String)?.hasPrefix(expectedText) == true)

            var cursorArgs = args
            cursorArgs["textOffset"] = offset
            let resumed = try await call("sources_detail", cursorArgs, navigator)
            XCTAssertEqual(try firstRow(resumed)["value"] as? String, entry["value"] as? String)
        }
        let partial = try await call("sources_detail", ["kind": "script", "index": 0, "query": "SE*/"], navigator)
        XCTAssertEqual(partial["total"] as? Int, 0, "Search must not start inside a folded letter.")
    }

    func testSourcesSearchFindsAnEmojiWithinAnUnchangedGrapheme() async throws {
        let prefix = "/*👩‍"
        let webView = await load("<script>\(prefix)💻*/</script>")
        defer { withExtendedLifetime(webView) {} }
        let navigator = SourcesNavigator()
        navigator.attach(to: webView)

        let page = try await call("sources_detail", ["kind": "script", "index": 0, "query": "💻"], navigator)
        let entry = try firstRow(page)
        XCTAssertEqual(entry["textOffset"] as? Int, prefix.unicodeScalars.count)
        XCTAssertEqual(entry["value"] as? String, "💻*/")
    }

    func testSourcesMetadataBoundsLargeURLsBeforeCrossingWebKit() async throws {
        let webView = await load("<p>Metadata fixture</p>")
        defer { withExtendedLifetime(webView) {} }
        _ = try await webView.evaluateJavaScript("""
        (() => {
            const suffix = 'a'.repeat(2 * 1024 * 1024);
            for (const url of [
                'data:text/javascript,' + suffix + 'needle-at-tail',
                'https://user:' + suffix + '@assets.example:8443/secret?token=private'
            ]) {
                const script = document.createElement('script');
                script.type = 'application/json';
                script.src = url;
                document.head.append(script);
            }
        })();
        """)
        let navigator = SourcesNavigator()
        navigator.attach(to: webView)

        let redacted = try await call("sources_list", ["section": "scripts"], navigator, authorize: { _ in false })
        let entries = try XCTUnwrap(redacted["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.map { $0["url"] as? String }, ["", "https://assets.example:8443"])
        XCTAssertLessThan(navigator.resultBytes, 512)

        let raw = try await call("sources_list", ["section": "scripts", "query": "needle-at-tail", "raw": true], navigator)
        let entry = try firstRow(raw)
        XCTAssertEqual(raw["total"] as? Int, 1, "Search examines the full URL before truncating its response.")
        let url = try XCTUnwrap(entry["url"] as? String)
        XCTAssertTrue(url.hasPrefix("data:text/javascript,"))
        XCTAssertEqual(url.count, 4096)
        XCTAssertLessThan(navigator.resultBytes, 4300)
    }

    private func call(
        _ tool: String,
        _ arguments: [String: Any],
        _ navigator: WebViewNavigator,
        authorize: @escaping (String) async -> Bool = { _ in true }
    ) async throws -> [String: Any] {
        let result = try await AgentDevTools.call(
            tool, arguments: arguments, navigator: navigator,
            storage: StorageManager(), console: ConsoleSession(), authorize: authorize
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
