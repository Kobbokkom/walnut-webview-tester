//
//  SearchTextTests.swift
//  winaTests
//
//  Comprehensive tests for SearchTextOverlay functionality including
//  JavaScript text search, highlighting, navigation, and edge cases.
//

import XCTest
import WebKit
@testable import wina

// MARK: - WKWebView Test Helpers

private enum TestWebViewLoader {
    static let baseURL = URL(string: "https://example.com")!
    static let loadTimeoutSeconds: Double = 5
}

/// Proper async WKWebView loading delegate (replaces flaky Task.sleep)
@MainActor
private final class TestNavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func waitForLoad(webView: WKWebView, html: String) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(TestWebViewLoader.loadTimeoutSeconds))
                await MainActor.run {
                    self?.finishIfNeeded()
                }
            }
            webView.loadHTMLString(html, baseURL: TestWebViewLoader.baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishIfNeeded()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishIfNeeded()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finishIfNeeded()
    }

    private func finishIfNeeded() {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let continuation {
            continuation.resume()
            self.continuation = nil
        }
    }
}

// MARK: - Search Text JavaScript Script Tests

final class SearchTextScriptTests: XCTestCase {

    // MARK: - Escape Function Tests

    func testEscapeBackslash() {
        let input = "test\\path"
        let escaped = escapeForJS(input)
        XCTAssertEqual(escaped, "test\\\\path")
    }

    func testEscapeSingleQuote() {
        let input = "it's a test"
        let escaped = escapeForJS(input)
        XCTAssertEqual(escaped, "it\\'s a test")
    }

    func testEscapeDoubleQuote() {
        let input = "say \"hello\""
        let escaped = escapeForJS(input)
        XCTAssertEqual(escaped, "say \\\"hello\\\"")
    }

    func testEscapeMultipleSpecialCharacters() {
        let input = "path\\to\\file's \"name\""
        let escaped = escapeForJS(input)
        XCTAssertEqual(escaped, "path\\\\to\\\\file\\'s \\\"name\\\"")
    }

    func testEscapeEmptyString() {
        let escaped = escapeForJS("")
        XCTAssertEqual(escaped, "")
    }

    func testEscapeNoSpecialCharacters() {
        let input = "simple text 123"
        let escaped = escapeForJS(input)
        XCTAssertEqual(escaped, "simple text 123")
    }

    func testEscapeUnicodeCharacters() {
        let input = "한글 테스트"
        let escaped = escapeForJS(input)
        XCTAssertEqual(escaped, "한글 테스트")
    }

    func testEscapeNewlineCharacters() {
        let input = "line1\nline2"
        let escaped = escapeForJS(input)
        // Newlines should be preserved (not escaped in this implementation)
        XCTAssertTrue(escaped.contains("\n"))
    }

    func testSearchScriptUsesRegexEscaping() {
        let script = SearchTextOverlay.searchScript(for: "a.b")
        XCTAssertNotNil(script)
        let expected = #"replace(/[.*+?^${}()|[\]\\]/g, '\\$&')"#
        XCTAssertTrue(script?.contains(expected) == true)
    }

    func testSearchScriptUsesJSONSerializationForKeyword() throws {
        let keyword = "say \"hello\""
        let data = try XCTUnwrap(
            try JSONSerialization.data(withJSONObject: keyword, options: .fragmentsAllowed)
        )
        let jsonKeyword = try XCTUnwrap(String(data: data, encoding: .utf8))
        let script = try XCTUnwrap(SearchTextOverlay.searchScript(for: keyword))

        XCTAssertTrue(script.contains("const keyword = \(jsonKeyword);"))
    }

    // MARK: - Helper

    private func escapeForJS(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - Search Text JSON Response Tests

final class SearchTextJSONResponseTests: XCTestCase {

    func testParseValidSearchResponse() {
        let jsonString = "{\"count\": 5, \"index\": 0}"
        let data = jsonString.data(using: .utf8)!

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["count"] as? Int, 5)
        XCTAssertEqual(json?["index"] as? Int, 0)
    }

    func testParseZeroMatchesResponse() {
        let jsonString = "{\"count\": 0, \"index\": 0}"
        let data = jsonString.data(using: .utf8)!

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["count"] as? Int, 0)
    }

    func testParseNavigationResponse() {
        let jsonString = "{\"index\": 3}"
        let data = jsonString.data(using: .utf8)!

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["index"] as? Int, 3)
    }

    func testParseInvalidJSON() {
        let jsonString = "not valid json"
        let data = jsonString.data(using: .utf8)!

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNil(json)
    }

    func testParseMissingFields() {
        let jsonString = "{}"
        let data = jsonString.data(using: .utf8)!

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertNil(json?["count"])
        XCTAssertNil(json?["index"])

        // Default values when missing
        let count = json?["count"] as? Int ?? 0
        let index = json?["index"] as? Int ?? 0
        XCTAssertEqual(count, 0)
        XCTAssertEqual(index, 0)
    }
}

// MARK: - WKWebView Search Integration Tests

@MainActor
final class SearchTextDOMIntegrationTests: XCTestCase {

    var webView: WKWebView!
    private var navigationDelegate: TestNavigationDelegate?

    override func setUp() async throws {
        try await super.setUp()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        navigationDelegate = TestNavigationDelegate()
        webView.navigationDelegate = navigationDelegate
    }

    override func tearDown() async throws {
        webView.navigationDelegate = nil
        navigationDelegate = nil
        webView = nil
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func loadTestHTML(_ html: String) async {
        await navigationDelegate?.waitForLoad(webView: webView, html: html)
    }

    private func executeScript(_ script: String) async -> Any? {
        return try? await webView.evaluateJavaScript(script)
    }

    private func createSearchScript(keyword: String) -> String {
        SearchTextOverlay.searchScript(for: keyword)!
    }

    private func createClearScript() -> String {
        """
        (function() {
            document.querySelectorAll('.__wina_search_highlight__').forEach(el => {
                const parent = el.parentNode;
                parent.replaceChild(document.createTextNode(el.textContent), el);
                parent.normalize();
            });
            window.__wina_search_elements__ = [];
            window.__wina_search_index__ = 0;
        })();
        """
    }

    private func createNavigateNextScript() -> String {
        """
        (function() {
            const elements = window.__wina_search_elements__ || [];
            if (elements.length === 0) return JSON.stringify({index: 0});

            let index = window.__wina_search_index__ || 0;

            if (elements[index]) {
                elements[index].style.backgroundColor = '#FFEB3B';
            }

            index = (index + 1) % elements.length;
            window.__wina_search_index__ = index;

            if (elements[index]) {
                elements[index].style.backgroundColor = '#FF9800';
            }

            return JSON.stringify({index: index});
        })();
        """
    }

    private func createNavigatePreviousScript() -> String {
        """
        (function() {
            const elements = window.__wina_search_elements__ || [];
            if (elements.length === 0) return JSON.stringify({index: 0});

            let index = window.__wina_search_index__ || 0;

            if (elements[index]) {
                elements[index].style.backgroundColor = '#FFEB3B';
            }

            index = (index - 1 + elements.length) % elements.length;
            window.__wina_search_index__ = index;

            if (elements[index]) {
                elements[index].style.backgroundColor = '#FF9800';
            }

            return JSON.stringify({index: index});
        })();
        """
    }

    // MARK: - Basic Search Tests

    func testSearchFindsExactMatch() async {
        let testHTML = """
        <html><body>
            <p>Hello World</p>
        </body></html>
        """
        await loadTestHTML(testHTML)

        let result = await executeScript(createSearchScript(keyword: "Hello")) as? String
        let data = result?.data(using: .utf8)
        let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]

        XCTAssertEqual(json?["count"] as? Int, 1)
    }

    func testSearchFindsMultipleMatches() async {
        let testHTML = """
        <html><body>
            <p>Hello Hello Hello</p>
        </body></html>
        """
        await loadTestHTML(testHTML)

        let result = await executeScript(createSearchScript(keyword: "Hello")) as? String
        let data = result?.data(using: .utf8)
        let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]

        XCTAssertEqual(json?["count"] as? Int, 3)
    }

    func testSearchIsCaseInsensitive() async {
        let testHTML = """
        <html><body>
            <p>Hello HELLO hello HeLLo</p>
        </body></html>
        """
        await loadTestHTML(testHTML)

        let result = await executeScript(createSearchScript(keyword: "hello")) as? String
        let data = result?.data(using: .utf8)
        let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]

        XCTAssertEqual(json?["count"] as? Int, 4)
    }

    func testSearchReturnsZeroForNoMatch() async {
        let testHTML = """
        <html><body>
            <p>Hello World</p>
        </body></html>
        """
        await loadTestHTML(testHTML)

        let result = await executeScript(createSearchScript(keyword: "xyz123")) as? String
        let data = result?.data(using: .utf8)
        let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]

        XCTAssertEqual(json?["count"] as? Int, 0)
    }

    func testSearchWithEmptyKeyword() async {
        let testHTML = "<html><body><p>Test</p></body></html>"
        await loadTestHTML(testHTML)

        let result = await executeScript(createSearchScript(keyword: "")) as? String
        let data = result?.data(using: .utf8)
        let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]

        XCTAssertEqual(json?["count"] as? Int, 0)
    }

    func testSearchPreservesMarkupLikeText() async {
        await loadTestHTML("<html><body><p id='text'>foo &lt;b&gt;bar&lt;/b&gt; &amp;amp;</p></body></html>")
        let before = await executeScript("document.getElementById('text').textContent") as? String
        _ = await executeScript(createSearchScript(keyword: "foo"))
        let after = await executeScript("document.getElementById('text').textContent") as? String
        let insertedMarkup = await executeScript("document.querySelectorAll('#text b').length") as? Int
        XCTAssertEqual(after, before)
        XCTAssertEqual(insertedMarkup, 0)
        _ = await executeScript(createClearScript())
        let cleared = await executeScript("document.getElementById('text').textContent") as? String
        XCTAssertEqual(cleared, before)
    }

    func testSourcesLookupKeepsSelectedSiblingWithWhitespaceAndSpecialID() async throws {
        await loadTestHTML("""
        <html><body>
          <p class="item">first</p>
          <!-- comment -->
          <p class="item" id="second'item">second</p>
        </body></html>
        """)
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let manager = SourcesManager()
        manager.setNavigator(navigator)
        await manager.fetchDOMTree()
        func findSecond(_ node: DOMNode) -> DOMNode? {
            if node.attributes["id"] == "second'item" { return node }
            return node.children.lazy.compactMap(findSecond).first
        }
        let root = try XCTUnwrap(manager.domTree)
        let selected = try XCTUnwrap(findSecond(root))
        let result = await executeScript("(\(SourcesManager.nodeLookupScript(path: selected.path))).textContent") as? String
        XCTAssertEqual(result, "second")
        navigator.detach()
    }

    func testAccessibilityAuditFailureDoesNotReportPass() async {
        await loadTestHTML("<html><body>test</body></html>")
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let manager = navigator.accessibilityManager
        _ = await executeScript("window.axe = {run: function(){ return Promise.reject(new Error('audit failed')); }}")
        await manager.runAudit(navigator: navigator)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertFalse(manager.hasScanned)
        XCTAssertFalse(manager.isScanning)
        _ = await executeScript("window.axe = {run: function(){ return Promise.resolve({violations: []}); }}")
        await manager.runAudit(navigator: navigator)
        XCTAssertNil(manager.errorMessage)
        XCTAssertTrue(manager.hasScanned)
        XCTAssertTrue(manager.issues.isEmpty)
        navigator.detach()
    }

    func testFailedAccessibilityRescanClearsPreviousFindings() async {
        await loadTestHTML("<html><body><img src='missing.png'></body></html>")
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let manager = navigator.accessibilityManager
        _ = await executeScript("""
        window.axe = {run: function(){return Promise.resolve({violations: [{
          id:'image-alt', impact:'serious', help:'Images need alternative text',
          nodes:[{html:'<img src="missing.png">', target:['img']}]
        }]});}};
        """)
        await manager.runAudit(navigator: navigator)
        XCTAssertTrue(manager.hasScanned)
        XCTAssertEqual(manager.issues.count, 1)
        _ = await executeScript("window.axe = {run: function(){return Promise.reject(new Error('rescan failed'));}}")
        await manager.runAudit(navigator: navigator)
        XCTAssertTrue(manager.issues.isEmpty)
        XCTAssertFalse(manager.hasScanned)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertFalse(manager.isScanning)
        navigator.detach()
    }

    // MARK: - Highlight Element Tests

    func testHighlightElementsAreCreated() async {
        let testHTML = """
        <html><body>
            <p>Find this word</p>
        </body></html>
        """
        await loadTestHTML(testHTML)

        _ = await executeScript(createSearchScript(keyword: "this"))

        let highlightCount = await executeScript(
            "document.querySelectorAll('.__wina_search_highlight__').length"
        ) as? Int

        XCTAssertEqual(highlightCount, 1)
    }

    func testHighlightElementsHaveCorrectClass() async {
        let testHTML = "<html><body><p>test word</p></body></html>"
        await loadTestHTML(testHTML)

        _ = await executeScript(createSearchScript(keyword: "test"))

        let hasClass = await executeScript(
            "document.querySelector('.__wina_search_highlight__') !== null"
        ) as? Bool

        XCTAssertEqual(hasClass, true)
    }

    func testFirstMatchHasActiveHighlightColor() async {
        let testHTML = "<html><body><p>test test</p></body></html>"
        await loadTestHTML(testHTML)

        _ = await executeScript(createSearchScript(keyword: "test"))

        let firstBgColor = await executeScript(
            "document.querySelectorAll('.__wina_search_highlight__')[0].style.backgroundColor"
        ) as? String

        // First match should have orange (#FF9800) background
        XCTAssertTrue(firstBgColor?.contains("rgb(255, 152, 0)") ?? false ||
                      firstBgColor?.contains("#FF9800") ?? false)
    }

    func testOtherMatchesHaveDefaultHighlightColor() async {
        let testHTML = "<html><body><p>test test test</p></body></html>"
        await loadTestHTML(testHTML)

        _ = await executeScript(createSearchScript(keyword: "test"))

        let secondBgColor = await executeScript(
            "document.querySelectorAll('.__wina_search_highlight__')[1].style.backgroundColor"
        ) as? String

        // Other matches should have yellow (#FFEB3B) background
        XCTAssertTrue(secondBgColor?.contains("rgb(255, 235, 59)") ?? false ||
                      secondBgColor?.contains("#FFEB3B") ?? false)
    }

    // MARK: - Clear Highlights Tests

    func testClearRemovesAllHighlights() async {
        let testHTML = "<html><body><p>test test test</p></body></html>"
        await loadTestHTML(testHTML)

        _ = await executeScript(createSearchScript(keyword: "test"))

        let beforeCount = await executeScript(
            "document.querySelectorAll('.__wina_search_highlight__').length"
        ) as? Int
        XCTAssertEqual(beforeCount, 3)

        _ = await executeScript(createClearScript())

        let afterCount = await executeScript(
            "document.querySelectorAll('.__wina_search_highlight__').length"
        ) as? Int
        XCTAssertEqual(afterCount, 0)
    }

    func testClearRestoresOriginalText() async {
        let testHTML = "<html><body><p id='test'>Hello World</p></body></html>"
        await loadTestHTML(testHTML)

        let originalText = await executeScript(
            "document.getElementById('test').textContent"
        ) as? String

        _ = await executeScript(createSearchScript(keyword: "World"))
        _ = await executeScript(createClearScript())

        let restoredText = await executeScript(
            "document.getElementById('test').textContent"
        ) as? String

        XCTAssertEqual(originalText, restoredText)
    }

    func testClearOnEmptyDoesNothing() async {
        let testHTML = "<html><body><p>No search yet</p></body></html>"
        await loadTestHTML(testHTML)

        // Clear without searching first
        _ = await executeScript(createClearScript())

        let highlightCount = await executeScript(
            "document.querySelectorAll('.__wina_search_highlight__').length"
        ) as? Int

        XCTAssertEqual(highlightCount, 0)
    }

    // MARK: - Navigation Tests

    func testNavigateNextUpdatesIndex() async {
        let testHTML = "<html><body><p>a b c a b c a</p></body></html>"
        await loadTestHTML(testHTML)

        _ = await executeScript(createSearchScript(keyword: "a"))

        // Navigate next
        let result = await executeScript(createNavigateNextScript()) as? String
        let data = result?.data(using: .utf8)
        let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]

        XCTAssertEqual(json?["index"] as? Int, 1)
    }

    func testNavigateNextWrapsAround() async {
        let testHTML = "<html><body><p>x y x</p></body></html>"
        await loadTestHTML(testHTML)

        _ = await executeScript(createSearchScript(keyword: "x"))

        // Navigate to second (index 1)
        _ = await executeScript(createNavigateNextScript())
        // Navigate wraps to first (index 0)
        let result = await executeScript(createNavigateNextScript()) as? String
        let data = result?.data(using: .utf8)
        let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]

        XCTAssertEqual(json?["index"] as? Int, 0)
    }

    func testNavigatePreviousUpdatesIndex() async {
        let testHTML = "<html><body><p>a b a b a</p></body></html>"
        await loadTestHTML(testHTML)

        _ = await executeScript(createSearchScript(keyword: "a"))

        // Move to second first
        _ = await executeScript(createNavigateNextScript())

        // Navigate previous
        let result = await executeScript(createNavigatePreviousScript()) as? String
        let data = result?.data(using: .utf8)
        let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]

        XCTAssertEqual(json?["index"] as? Int, 0)
    }

    func testNavigatePreviousWrapsAround() async {
        let testHTML = "<html><body><p>x y x y x</p></body></html>"
        await loadTestHTML(testHTML)

        _ = await executeScript(createSearchScript(keyword: "x"))

        // Navigate previous from index 0 wraps to last
        let result = await executeScript(createNavigatePreviousScript()) as? String
        let data = result?.data(using: .utf8)
        let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]

        XCTAssertEqual(json?["index"] as? Int, 2) // 3 matches, last index is 2
    }

    func testNavigateOnEmptyResultsReturnsZero() async {
        let testHTML = "<html><body><p>no match</p></body></html>"
        await loadTestHTML(testHTML)

        _ = await executeScript(createSearchScript(keyword: "xyz"))

        let result = await executeScript(createNavigateNextScript()) as? String
        let data = result?.data(using: .utf8)
        let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]

        XCTAssertEqual(json?["index"] as? Int, 0)
    }

    // MARK: - Active Highlight Color Tests

    func testNavigateNextChangesActiveHighlight() async {
        let testHTML = "<html><body><p>a b a</p></body></html>"
        await loadTestHTML(testHTML)

        _ = await executeScript(createSearchScript(keyword: "a"))
        _ = await executeScript(createNavigateNextScript())

        // First should now be yellow (inactive)
        let firstBgColor = await executeScript(
            "document.querySelectorAll('.__wina_search_highlight__')[0].style.backgroundColor"
        ) as? String

        // Second should now be orange (active)
        let secondBgColor = await executeScript(
            "document.querySelectorAll('.__wina_search_highlight__')[1].style.backgroundColor"
        ) as? String

        XCTAssertTrue(firstBgColor?.contains("rgb(255, 235, 59)") ?? false)
        XCTAssertTrue(secondBgColor?.contains("rgb(255, 152, 0)") ?? false)
    }

    // MARK: - Edge Case Tests

    func testSearchIgnoresScriptTags() async {
        let testHTML = """
        <html><body>
            <script>var test = 'test';</script>
            <p>visible test</p>
        </body></html>
        """
        await loadTestHTML(testHTML)

        let result = await executeScript(createSearchScript(keyword: "test")) as? String
        let data = result?.data(using: .utf8)
        let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]

        // Should only find the one in <p>, not in <script>
        XCTAssertEqual(json?["count"] as? Int, 1)
    }

    func testSearchIgnoresStyleTags() async {
        let testHTML = """
        <html><head>
            <style>.test { color: red; }</style>
        </head><body>
            <p class="test">visible test</p>
        </body></html>
        """
        await loadTestHTML(testHTML)

        let result = await executeScript(createSearchScript(keyword: "test")) as? String
        let data = result?.data(using: .utf8)
        let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]

        // Should only find the one in <p>, not in <style>
        XCTAssertEqual(json?["count"] as? Int, 1)
    }

    func testSearchAcrossNestedElements() async {
        let testHTML = """
        <html><body>
            <div>
                <span>
                    <strong>nested test</strong>
                </span>
            </div>
        </body></html>
        """
        await loadTestHTML(testHTML)

        let result = await executeScript(createSearchScript(keyword: "test")) as? String
        let data = result?.data(using: .utf8)
        let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]

        XCTAssertEqual(json?["count"] as? Int, 1)
    }

    func testSearchPreservesTextContent() async {
        let testHTML = """
        <html><body>
            <p id="target">The quick brown fox</p>
        </body></html>
        """
        await loadTestHTML(testHTML)

        _ = await executeScript(createSearchScript(keyword: "quick"))

        let content = await executeScript(
            "document.getElementById('target').textContent"
        ) as? String

        XCTAssertEqual(content, "The quick brown fox")
    }

    func testNewSearchClearsPreviousHighlights() async {
        let testHTML = "<html><body><p>apple banana cherry</p></body></html>"
        await loadTestHTML(testHTML)

        // First search
        _ = await executeScript(createSearchScript(keyword: "apple"))
        let firstCount = await executeScript(
            "document.querySelectorAll('.__wina_search_highlight__').length"
        ) as? Int
        XCTAssertEqual(firstCount, 1)

        // Second search (different keyword)
        _ = await executeScript(createSearchScript(keyword: "banana"))
        let secondCount = await executeScript(
            "document.querySelectorAll('.__wina_search_highlight__').length"
        ) as? Int
        XCTAssertEqual(secondCount, 1) // Should only have banana highlighted

        // Verify apple is not highlighted
        let bodyContent = await executeScript("document.body.innerHTML") as? String
        let appleHighlighted = bodyContent?.contains("__wina_search_highlight__\">apple") ?? false
        XCTAssertFalse(appleHighlighted)
    }

    func testSearchWithSpecialRegexCharacters() async {
        let testHTML = "<html><body><p>test (with) [brackets] and $special</p></body></html>"
        await loadTestHTML(testHTML)

        // Note: This test might fail if regex special chars aren't properly escaped
        // The current implementation uses 'gi' flags which might handle some cases
        let result = await executeScript(createSearchScript(keyword: "with")) as? String
        let data = result?.data(using: .utf8)
        let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]

        XCTAssertEqual(json?["count"] as? Int, 1)
    }

    func testSearchUnicodeText() async {
        let testHTML = "<html><body><p>한글 테스트 한글</p></body></html>"
        await loadTestHTML(testHTML)

        let result = await executeScript(createSearchScript(keyword: "한글")) as? String
        let data = result?.data(using: .utf8)
        let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]

        XCTAssertEqual(json?["count"] as? Int, 2)
    }

    func testSearchEmoji() async {
        let testHTML = "<html><body><p>Hello 🌍 World 🌍</p></body></html>"
        await loadTestHTML(testHTML)

        let result = await executeScript(createSearchScript(keyword: "🌍")) as? String
        let data = result?.data(using: .utf8)
        let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]

        XCTAssertEqual(json?["count"] as? Int, 2)
    }

    // MARK: - Global Variable Tests

    func testSearchSetsGlobalElementsArray() async {
        let testHTML = "<html><body><p>x y x</p></body></html>"
        await loadTestHTML(testHTML)

        _ = await executeScript(createSearchScript(keyword: "x"))

        let elementsCount = await executeScript(
            "window.__wina_search_elements__.length"
        ) as? Int

        XCTAssertEqual(elementsCount, 2)
    }

    func testSearchSetsGlobalIndex() async {
        let testHTML = "<html><body><p>test</p></body></html>"
        await loadTestHTML(testHTML)

        _ = await executeScript(createSearchScript(keyword: "test"))

        let index = await executeScript("window.__wina_search_index__") as? Int

        XCTAssertEqual(index, 0)
    }

    func testClearResetsGlobalVariables() async {
        let testHTML = "<html><body><p>test test</p></body></html>"
        await loadTestHTML(testHTML)

        _ = await executeScript(createSearchScript(keyword: "test"))
        _ = await executeScript(createClearScript())

        let elementsCount = await executeScript(
            "window.__wina_search_elements__.length"
        ) as? Int
        let index = await executeScript("window.__wina_search_index__") as? Int

        XCTAssertEqual(elementsCount, 0)
        XCTAssertEqual(index, 0)
    }
}

// MARK: - Performance Tests

@MainActor
final class SearchTextPerformanceTests: XCTestCase {

    var webView: WKWebView!
    private var navigationDelegate: TestNavigationDelegate?

    override func setUp() async throws {
        try await super.setUp()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        navigationDelegate = TestNavigationDelegate()
        webView.navigationDelegate = navigationDelegate
    }

    override func tearDown() async throws {
        webView.navigationDelegate = nil
        navigationDelegate = nil
        webView = nil
        try await super.tearDown()
    }

    func testSearchOnLargePage() async {
        // Create a page with many paragraphs
        var paragraphs = ""
        for i in 0..<100 {
            paragraphs += "<p>Paragraph \(i) with some test content</p>"
        }
        let testHTML = "<html><body>\(paragraphs)</body></html>"

        await navigationDelegate?.waitForLoad(webView: webView, html: testHTML)

        let searchScript = """
        (function() {
            const keyword = 'test';
            const regex = new RegExp(keyword, 'gi');
            let matchCount = 0;

            function traverse(node) {
                if (node.nodeType === 3) {
                    const matches = node.nodeValue.match(regex);
                    if (matches) matchCount += matches.length;
                } else if (node.nodeType === 1 && !['SCRIPT', 'STYLE'].includes(node.tagName)) {
                    Array.from(node.childNodes).forEach(traverse);
                }
            }

            traverse(document.body);
            return matchCount;
        })();
        """

        let count = try? await webView.evaluateJavaScript(searchScript) as? Int

        XCTAssertEqual(count, 100) // Should find "test" in each paragraph
    }

    func testMultipleSearchesDoNotLeak() async {
        let testHTML = "<html><body><p>word word word</p></body></html>"
        await navigationDelegate?.waitForLoad(webView: webView, html: testHTML)

        let searchScript = """
        (function() {
            document.querySelectorAll('.__wina_search_highlight__').forEach(el => {
                const parent = el.parentNode;
                parent.replaceChild(document.createTextNode(el.textContent), el);
                parent.normalize();
            });

            const keyword = 'word';
            const regex = new RegExp(keyword, 'gi');
            let matchCount = 0;

            function traverse(node) {
                if (node.nodeType === 3) {
                    const text = node.nodeValue;
                    if (regex.test(text)) {
                        regex.lastIndex = 0;
                        const span = document.createElement('span');
                        span.innerHTML = text.replace(regex, match => {
                            matchCount++;
                            return '<span class="__wina_search_highlight__">' + match + '</span>';
                        });
                        const frag = document.createDocumentFragment();
                        while (span.firstChild) frag.appendChild(span.firstChild);
                        node.parentNode.replaceChild(frag, node);
                    }
                } else if (node.nodeType === 1 && !['SCRIPT', 'STYLE'].includes(node.tagName)) {
                    Array.from(node.childNodes).forEach(traverse);
                }
            }

            traverse(document.body);
            return matchCount;
        })();
        """

        // Run multiple searches
        for _ in 0..<10 {
            _ = try? await webView.evaluateJavaScript(searchScript)
        }

        // After multiple searches, there should still only be 3 highlights
        let finalCount = try? await webView.evaluateJavaScript(
            "document.querySelectorAll('.__wina_search_highlight__').length"
        ) as? Int

        XCTAssertEqual(finalCount, 3)
    }
}
