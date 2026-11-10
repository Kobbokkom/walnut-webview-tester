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

    func testPageInteractionScrollsFillsAndClicksToAVisibleResult() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <header style="min-height:125vh"><h1>Test shipment checkout</h1></header>
            <label for="reference">Delivery reference</label>
            <input id="reference">
            <button id="confirm" disabled>Confirm shipment</button>
            <p id="receipt" style="visibility:hidden">Receipt WALNUT-6205</p>
            <script>
            const input = document.querySelector('#reference');
            const button = document.querySelector('#confirm');
            input.addEventListener('input', () => input.dataset.input = input.value);
            input.addEventListener('change', () => {
                button.disabled = input.dataset.input !== 'WK-417' || input.value !== 'WK-417';
            });
            button.addEventListener('click', () => document.querySelector('#receipt').style.visibility = 'visible');
            </script>
            """, frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)

        let initial = try await call("page_interact", ["action": "observe"], navigator)
        let document = try XCTUnwrap(initial["documentId"] as? String)
        let initialElements = try XCTUnwrap(initial["elements"] as? [[String: Any]])
        XCTAssertFalse(initialElements.contains { $0["canFill"] as? Bool == true })
        XCTAssertFalse(try XCTUnwrap(initial["text"] as? String).contains("WALNUT-6205"))

        let scroll = try await call("page_interact", ["action": "scroll", "direction": "down", "documentId": document], navigator)
        let before = try XCTUnwrap((scroll["before"] as? [String: Any])?["y"] as? Double)
        let after = try XCTUnwrap((scroll["after"] as? [String: Any])?["y"] as? Double)
        XCTAssertEqual(scroll["moved"] as? Bool, true)
        XCTAssertGreaterThan(after, before)

        let form = try await call("page_interact", ["action": "observe"], navigator)
        let field = try interactionRef(form, label: "Delivery reference", capability: "canFill")
        let fill = try await applyInteraction(["action": "fill", "documentId": document, "ref": field, "text": "WK-417"], navigator)
        XCTAssertEqual(fill["applied"] as? Bool, true)
        XCTAssertFalse(String(describing: fill).contains("WK-417"), "Do not return the supplied field value")

        let ready = try await call("page_interact", ["action": "observe"], navigator)
        let button = try interactionRef(ready, label: "Confirm shipment", capability: "canClick")
        let click = try await applyInteraction(["action": "click", "documentId": document, "ref": button], navigator)
        XCTAssertEqual(click["applied"] as? Bool, true)
        let result = try await call("page_interact", ["action": "observe"], navigator)
        XCTAssertTrue(try XCTUnwrap(result["text"] as? String).contains("Receipt WALNUT-6205"))
    }

    func testPageInteractionKeepsValuesPrivateAndRejectsUnapprovedOrChangedTargets() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <label for="reference">Delivery reference</label><input id="reference" value="fixture-private-reference">
            <label for="pass">Passcode</label><input id="pass" type="password" value="fixture-private-passcode">
            <label for="comment">Comment</label><textarea id="comment">fixture-private-comment</textarea>
            <form id="checkout" action="https://example.invalid/confirm"></form>
            <form id="other" action="https://example.invalid/confirm"></form>
            <button id="confirm" form="checkout" type="submit"
                onclick="event.preventDefault(); document.body.dataset.clicked = 'yes'">Confirm shipment</button>
            """, frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        do {
            _ = try await call("page_interact", ["action": "observe"], navigator, authorize: { _ in false })
            XCTFail("Sharing page text requires approval")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The iPhone did not approve this action.")
        }
        let page = try await call("page_interact", ["action": "observe"], navigator)
        let document = try XCTUnwrap(page["documentId"] as? String)
        XCTAssertFalse(String(describing: page).contains("fixture-private-"))
        let elements = try XCTUnwrap(page["elements"] as? [[String: Any]])
        XCTAssertFalse(elements.contains { $0["label"] as? String == "Passcode" && $0["canFill"] as? Bool == true })
        let field = try interactionRef(page, label: "Delivery reference", capability: "canFill")

        do {
            _ = try await call(
                "page_interact", ["action": "fill", "documentId": document, "ref": field, "text": "denied value"],
                navigator, authorize: { _ in false }
            )
            XCTFail("Filling a page field requires approval")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The iPhone did not approve this action.")
        }
        let currentValue = try await webView.evaluateJavaScript("document.querySelector('#reference').value")
        XCTAssertEqual(currentValue as? String, "fixture-private-reference")

        let button = try interactionRef(page, label: "Confirm shipment", capability: "canClick")
        var replacedDuringApproval = false
        do {
            _ = try await call("page_interact", ["action": "click", "documentId": document, "ref": button], navigator) { _ in
                let replacement = try? await webView.evaluateJavaScript("""
                    const button = document.querySelector('#confirm');
                    button.replaceWith(button.cloneNode(true));
                    true;
                    """)
                replacedDuringApproval = replacement as? Bool == true
                return true
            }
            XCTFail("Approval for a detached element must not click its replacement")
        } catch {
            XCTAssertTrue(replacedDuringApproval)
        }

        let freshPage = try await call("page_interact", ["action": "observe"], navigator)
        let movedButton = try interactionRef(freshPage, label: "Confirm shipment", capability: "canClick")
        var movedDuringApproval = false
        do {
            _ = try await call("page_interact", ["action": "click", "documentId": document, "ref": movedButton], navigator) { _ in
                let changed = try? await webView.evaluateJavaScript("""
                    document.querySelector('#confirm').setAttribute('form', 'other');
                    true;
                    """)
                movedDuringApproval = changed as? Bool == true
                return true
            }
            XCTFail("Approval for one form must not apply to an identical destination in another form")
        } catch {
            XCTAssertTrue(movedDuringApproval)
        }
        let clicked = try await webView.evaluateJavaScript("document.body.dataset.clicked || ''")
        XCTAssertEqual(clicked as? String, "")
    }

    func testPageInteractionRejectsInvalidFillAndReportsWhenThePageRevertsIt() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <label for="reference">Delivery reference</label><input id="reference" maxlength="6" value="locked">
            <script>
            const input = document.querySelector('#reference');
            input.addEventListener('input', () => {
                input.dataset.received = input.value;
                input.value = 'locked';
            });
            </script>
            """, frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let page = try await call("page_interact", ["action": "observe"], navigator)
        let document = try XCTUnwrap(page["documentId"] as? String)
        let field = try interactionRef(page, label: "Delivery reference", capability: "canFill")
        var arguments: [String: Any] = ["action": "fill", "documentId": document, "ref": field, "text": "too long"]
        do {
            _ = try await call("page_interact", arguments, navigator) { _ in
                XCTFail("A known invalid fill must fail before approval")
                return true
            }
            XCTFail("A fill must respect maxlength")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("length"), error.localizedDescription)
        }
        let before = try await webView.evaluateJavaScript("document.querySelector('#reference').dataset.received || ''")
        XCTAssertEqual(before as? String, "")

        arguments["text"] = "NEW-1"
        let result = try await applyInteraction(arguments, navigator)
        XCTAssertEqual(result["applied"] as? Bool, false)
        XCTAssertEqual(result["outcome"] as? String, "pageChangedValue")
        XCTAssertEqual(result["observeAgain"] as? Bool, true)
        XCTAssertFalse(String(describing: result).contains("NEW-1"))
        let dispatched = try await webView.evaluateJavaScript("document.querySelector('#reference').dataset.received")
        XCTAssertEqual(dispatched as? String, "NEW-1")
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

    private func interactionRef(_ page: [String: Any], label: String, capability: String) throws -> String {
        let rows = try XCTUnwrap(page["elements"] as? [[String: Any]])
        let row = rows.first { $0["label"] as? String == label && $0[capability] as? Bool == true }
        return try XCTUnwrap(row?["ref"] as? String, "Missing enabled \(label) in \(rows)")
    }

    private func applyInteraction(_ arguments: [String: Any], _ navigator: WebViewNavigator) async throws -> [String: Any] {
        do {
            return try await call("page_interact", arguments, navigator)
        } catch {
            throw AgentError("\(arguments["action"] ?? "action"): \(error.localizedDescription)")
        }
    }

    private func load(_ html: String, frame: CGRect = .zero) async -> WKWebView {
        let webView = WKWebView(frame: frame)
        let loaded = expectation(description: "Fixture loaded")
        let delegate = NavigationDelegate(loaded: loaded)
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 15)
        withExtendedLifetime(delegate) {}
        return webView
    }
}
