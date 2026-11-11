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

        override func callAsyncJavaScriptReportingErrors(_ script: String, contentWorld: WKContentWorld) async throws -> Any? {
            let value = try await super.callAsyncJavaScriptReportingErrors(script, contentWorld: contentWorld)
            resultBytes = (value as? String)?.utf8.count ?? 0
            return value
        }
    }

    private final class CancellingPointerNavigator: WebViewNavigator {
        var cancelAfterEvaluation = false
        private(set) var didShowPointer = false

        override func evaluateJavaScriptReportingErrors(_ script: String, contentWorld: WKContentWorld) async throws -> Any? {
            let value = try await super.evaluateJavaScriptReportingErrors(script, contentWorld: contentWorld)
            if cancelAfterEvaluation {
                withUnsafeCurrentTask { $0?.cancel() }
            }
            return value
        }

        override func showAgentPointer(x: Double, y: Double) {
            didShowPointer = true
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

    func testPageInteractionMovesClicksAndPressesKeysAtTheFocusedControl() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <label for="reference">Delivery reference</label>
            <input id="reference" style="position:fixed;left:20px;top:80px;width:200px;height:32px">
            <p id="result" style="position:fixed;left:20px;top:140px">Waiting for key</p>
            <script>
            const input = document.querySelector('#reference');
            for (const name of ['pointermove', 'mousemove', 'click']) {
                input.addEventListener(name, event => input.dataset[name] = `${event.clientX},${event.clientY}`);
            }
            input.addEventListener('input', event => input.dataset.edit = `${event.inputType}:${input.value}`);
            input.addEventListener('keydown', event => input.dataset.keydown = `${event.key}/${event.code}`);
            input.addEventListener('keyup', event => {
                document.querySelector('#result').textContent = `Received ${input.dataset.keydown} then ${event.key}/${event.code}`;
            });
            </script>
            """, frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let page = try await call("page_interact", ["action": "observe"], navigator)
        let document = try XCTUnwrap(page["documentId"] as? String)

        let move = try await applyInteraction(["action": "move", "documentId": document, "x": 60, "y": 90], navigator)
        XCTAssertEqual(move["applied"] as? Bool, true)
        let moves = try await webView.evaluateJavaScript("[input.dataset.pointermove, input.dataset.mousemove].join('|')")
        XCTAssertEqual(moves as? String, "60,90|60,90")

        let click = try await applyInteraction(["action": "click_at", "documentId": document, "x": 90, "y": 100], navigator)
        XCTAssertEqual(click["applied"] as? Bool, true)
        let clicked = try await webView.evaluateJavaScript("[document.activeElement.id, input.dataset.click].join('|')")
        XCTAssertEqual(clicked as? String, "reference|90,100")

        let type = try await applyInteraction(["action": "press", "documentId": document, "key": "A", "code": "KeyA"], navigator)
        XCTAssertEqual(type["applied"] as? Bool, true)
        let typed = try await webView.evaluateJavaScript("[input.value, input.dataset.edit].join('|')")
        XCTAssertEqual(typed as? String, "A|insertText:A")

        let backspace = try await applyInteraction(["action": "press", "documentId": document, "key": "Backspace"], navigator)
        XCTAssertEqual(backspace["applied"] as? Bool, true)
        let removed = try await webView.evaluateJavaScript("[input.value, input.dataset.edit].join('|')")
        XCTAssertEqual(removed as? String, "|deleteContentBackward:")

        let press = try await applyInteraction(["action": "press", "documentId": document, "key": "Escape", "code": "Escape"], navigator)
        XCTAssertEqual(press["applied"] as? Bool, true)
        let result = try await call("page_interact", ["action": "observe"], navigator)
        XCTAssertTrue(try XCTUnwrap(result["text"] as? String).contains("Received Escape/Escape then Escape/Escape"))
    }

    func testCoordinateClickDoesNotActivateReplacementAtTheSamePoint() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <button id="submit" style="position:fixed;left:20px;top:80px;width:200px;height:32px"
                onclick="document.body.dataset.clicked = 'yes'">Confirm shipment</button>
            """, frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let page = try await call("page_interact", ["action": "observe"], navigator)
        let document = try XCTUnwrap(page["documentId"] as? String)
        var replacedDuringApproval = false

        do {
            _ = try await call("page_interact", ["action": "click_at", "documentId": document, "x": 90, "y": 100], navigator) { _ in
                let replacement = try? await webView.evaluateJavaScript("""
                    const button = document.querySelector('#submit');
                    button.replaceWith(button.cloneNode(true));
                    true;
                    """)
                replacedDuringApproval = replacement as? Bool == true
                return true
            }
            XCTFail("Approval for a coordinate click must not activate a replacement control")
        } catch {
            XCTAssertTrue(replacedDuringApproval, error.localizedDescription)
        }
        let clicked = try await webView.evaluateJavaScript("document.body.dataset.clicked || ''")
        XCTAssertEqual(clicked as? String, "")
    }

    func testCancelledPointerMoveDoesNotShowCursor() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <button style="position:fixed;left:20px;top:80px;width:200px;height:32px">Target</button>
            """, frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        defer { withExtendedLifetime(webView) {} }
        let navigator = CancellingPointerNavigator()
        navigator.attach(to: webView)
        let page = try await call("page_interact", ["action": "observe"], navigator)
        let document = try XCTUnwrap(page["documentId"] as? String)
        let move = Task {
            _ = try await call("page_interact", ["action": "move", "documentId": document, "x": 60, "y": 90], navigator) { _ in
                navigator.cancelAfterEvaluation = true
                return true
            }
        }

        do {
            _ = try await move.value
            XCTFail("A cancelled move must not report success")
        } catch {
            XCTAssertTrue(error is CancellationError, error.localizedDescription)
        }
        XCTAssertFalse(navigator.didShowPointer)
    }

    func testPageInteractionKeepsValuesPrivateAndRejectsUnapprovedOrChangedTargets() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <label for="reference">Delivery reference</label><input id="reference" value="fixture-private-reference">
            <label for="pass">Passcode</label><input id="pass" type="password" value="fixture-private-passcode">
            <label for="comment">Comment</label><textarea id="comment">fixture-private-comment</textarea>
            <label><input type="checkbox" value="fixture-private-checkbox">Gift wrap</label>
            <input type="radio" name="shipping" aria-label="Express shipping" value="fixture-private-radio">
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
        _ = try interactionRef(page, label: "Gift wrap", capability: "canClick")
        _ = try interactionRef(page, label: "Express shipping", capability: "canClick")
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

extension AgentPageRegressionTests {
    func testSelectSupportsExactValuesAndRejectsDisabledOrChangedOptions() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <label for="shipping">Shipping method</label>
            <select id="shipping" onchange="this.dataset.changed = this.value">
                <option value="standard">Standard</option>
                <option value=" express ">Express</option>
                <optgroup label="Unavailable" disabled><option value="blocked">Blocked</option></optgroup>
            </select>
            """, frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let page = try await call("page_interact", ["action": "observe"], navigator)
        let document = try XCTUnwrap(page["documentId"] as? String)
        let field = try interactionRef(page, label: "Shipping method", capability: "canSelect")
        let controls = try XCTUnwrap(page["elements"] as? [[String: Any]])
        let choices = try XCTUnwrap(controls.first?["options"] as? [[String: Any]])
        XCTAssertEqual(choices[1]["value"] as? String, " express ")
        XCTAssertEqual(choices[2]["disabled"] as? Bool, true)
        var arguments: [String: Any] = ["action": "select", "documentId": document, "ref": field, "values": ["blocked"]]
        do {
            _ = try await call("page_interact", arguments, navigator) { _ in
                XCTFail("A disabled option must fail before approval")
                return true
            }
            XCTFail("A disabled optgroup must not be selected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("disabled"), error.localizedDescription)
        }
        arguments["values"] = [" express "]
        let selected = try await applyInteraction(arguments, navigator)
        XCTAssertEqual(selected["applied"] as? Bool, true)
        XCTAssertFalse(String(describing: selected).contains("express"))
        let changed = try await webView.evaluateJavaScript("shipping.value + '|' + shipping.dataset.changed")
        XCTAssertEqual(changed as? String, " express | express ")

        let fresh = try await call("page_interact", ["action": "observe"], navigator)
        arguments["ref"] = try interactionRef(fresh, label: "Shipping method", capability: "canSelect")
        arguments["values"] = ["standard"]
        do {
            _ = try await call("page_interact", arguments, navigator) { _ in
                _ = try? await webView.evaluateJavaScript("shipping.options[0].textContent = 'Different delivery'; void 0;")
                return true
            }
            XCTFail("An option changed during approval must invalidate the selection")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("changed"), error.localizedDescription)
        }
        let value = try await webView.evaluateJavaScript("shipping.value")
        XCTAssertEqual(value as? String, " express ")
    }

    func testSelectDisambiguatesDuplicateValuesByObservedIndex() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <label for="shipping">Shipping method</label>
            <select id="shipping" onchange="this.dataset.changed = this.selectedIndex">
                <option value="duplicate">First delivery</option>
                <option value="duplicate">Second delivery</option>
            </select>
            """, frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let page = try await call("page_interact", ["action": "observe"], navigator)
        let document = try XCTUnwrap(page["documentId"] as? String)
        let field = try interactionRef(page, label: "Shipping method", capability: "canSelect")
        let controls = try XCTUnwrap(page["elements"] as? [[String: Any]])
        let choices = try XCTUnwrap(controls.first?["options"] as? [[String: Any]])
        XCTAssertEqual(choices.compactMap { $0["index"] as? Int }, [0, 1])
        XCTAssertEqual(choices.compactMap { $0["value"] as? String }, ["duplicate", "duplicate"])

        var arguments: [String: Any] = ["action": "select", "documentId": document, "ref": field, "values": ["duplicate"]]
        do {
            _ = try await call("page_interact", arguments, navigator) { _ in
                XCTFail("An ambiguous value must fail before approval")
                return true
            }
            XCTFail("A duplicate value needs its option index")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Use optionIndexes"), error.localizedDescription)
        }

        arguments.removeValue(forKey: "values")
        arguments["optionIndexes"] = [1]
        do {
            _ = try await call("page_interact", arguments, navigator) { prompt in
                XCTAssertTrue(prompt.contains("[1] \"Second delivery\" (value \"duplicate\")"), prompt)
                _ = try? await webView.evaluateJavaScript("const option = shipping.options[1]; option.replaceWith(option.cloneNode(true)); void 0;")
                return true
            }
            XCTFail("An identical-looking replacement must not inherit approval")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("selected options changed"), error.localizedDescription)
        }

        let fresh = try await call("page_interact", ["action": "observe"], navigator)
        arguments["ref"] = try interactionRef(fresh, label: "Shipping method", capability: "canSelect")
        let result = try await call("page_interact", arguments, navigator) { prompt in
            XCTAssertTrue(prompt.contains("[1] \"Second delivery\" (value \"duplicate\")"), prompt)
            return true
        }
        XCTAssertEqual(result["applied"] as? Bool, true)
        let value = try await webView.evaluateJavaScript("[shipping.selectedIndex, shipping.value, shipping.dataset.changed].join('|')")
        XCTAssertEqual(value as? String, "1|duplicate|1")
    }

    func testSelectPaginationAndMultipleSelectionReportPageRejection() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <label for="items">Shipment items</label><select id="items" multiple size="4"></select>
            <script>
            for (let index = 0; index < 205; index++) items.add(new Option('Item ' + index, 'item-' + index));
            items.addEventListener('change', () => { if (items.options[101].selected) items.options[101].selected = false; });
            </script>
            """, frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let page = try await call("page_interact", ["action": "observe", "optionOffset": 100], navigator)
        let document = try XCTUnwrap(page["documentId"] as? String)
        let field = try interactionRef(page, label: "Shipment items", capability: "canSelect")
        let controls = try XCTUnwrap(page["elements"] as? [[String: Any]])
        let choices = try XCTUnwrap(controls.first?["options"] as? [[String: Any]])
        XCTAssertEqual(choices.first?["value"] as? String, "item-100")
        XCTAssertEqual(controls.first?["nextOptionOffset"] as? Int, 200)
        let result = try await applyInteraction([
            "action": "select", "documentId": document, "ref": field, "values": ["item-100", "item-101"]
        ], navigator)
        XCTAssertEqual(result["applied"] as? Bool, false)
        XCTAssertEqual(result["outcome"] as? String, "pageChangedValue")
        let value = try await webView.evaluateJavaScript("Array.from(items.selectedOptions, option => option.value).join(',')")
        XCTAssertEqual(value as? String, "item-100")
    }

    func testContenteditableFillKeepsOldTextPrivateAndHonorsBeforeInput() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <div id="editor" contenteditable="true" aria-label="Delivery note" style="min-height:60px">
                <b>fixture-private-editor-content</b>
            </div>
            <script>
            editor.addEventListener('beforeinput', event => { if (event.data === 'blocked') event.preventDefault(); });
            editor.addEventListener('input', event => editor.dataset.input = event.inputType);
            editor.addEventListener('change', () => editor.dataset.changed = 'yes');
            </script>
            """, frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let page = try await call("page_interact", ["action": "observe"], navigator)
        let document = try XCTUnwrap(page["documentId"] as? String)
        XCTAssertFalse(String(describing: page).contains("fixture-private-editor-content"))
        let field = try interactionRef(page, label: "Delivery note", capability: "canFill")
        let result = try await applyInteraction([
            "action": "fill", "documentId": document, "ref": field, "text": "<b>Plain delivery note</b>"
        ], navigator)
        XCTAssertEqual(result["applied"] as? Bool, true)
        let value = try await webView.evaluateJavaScript("[editor.textContent, editor.children.length, editor.dataset.input, editor.dataset.changed].join('|')")
        XCTAssertEqual(value as? String, "<b>Plain delivery note</b>|0|insertReplacementText|yes")
        let fresh = try await call("page_interact", ["action": "observe"], navigator)
        let ref = try interactionRef(fresh, label: "Delivery note", capability: "canFill")
        let blocked = try await applyInteraction(["action": "fill", "documentId": document, "ref": ref, "text": "blocked"], navigator)
        XCTAssertEqual(blocked["applied"] as? Bool, false)
        XCTAssertEqual(blocked["outcome"] as? String, "defaultPrevented")
        let unchanged = try await webView.evaluateJavaScript("editor.textContent")
        XCTAssertEqual(unchanged as? String, "<b>Plain delivery note</b>")
    }

    func testNestedScrollTargetsOnlyTheObservedRegion() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <div id="region" aria-label="Shipment list" style="height:160px;overflow-y:auto">
                <div style="height:800px">Shipment list contents</div>
            </div>
            """, frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let page = try await call("page_interact", ["action": "observe"], navigator)
        let document = try XCTUnwrap(page["documentId"] as? String)
        let region = try interactionRef(page, label: "Shipment list", capability: "canScroll")
        let result = try await call("page_interact", ["action": "scroll", "documentId": document, "ref": region, "direction": "down"], navigator)
        XCTAssertEqual(result["moved"] as? Bool, true)
        let positions = try await webView.evaluateJavaScript("[scrollY, region.scrollTop].join('|')")
        XCTAssertEqual(positions as? String, "0|128")
    }

    func testScrollOnlySensitiveFieldRejectsCoordinateClickAndKeys() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <textarea id="secret" autocomplete="current-password" aria-label="Protected credential"
                style="position:fixed;left:10px;top:10px;width:150px;height:34px;overflow-y:scroll"
                onclick="document.body.dataset.clicked='yes'" onkeydown="document.body.dataset.key=event.key">Fixture
            second line
            third line
            fourth line
            fifth line</textarea>
            """, frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let page = try await call("page_interact", ["action": "observe"], navigator)
        let document = try XCTUnwrap(page["documentId"] as? String)
        let region = try interactionRef(page, label: "Protected credential", capability: "canScroll")
        let focused = try await webView.evaluateJavaScript("secret.focus(); secret.scrollTop = 0; document.activeElement.id")
        XCTAssertEqual(focused as? String, "secret")

        for var arguments in [["action": "click_at", "x": 30, "y": 25], ["action": "press", "key": "Escape"]] as [[String: Any]] {
            arguments["documentId"] = document
            do {
                _ = try await call("page_interact", arguments, navigator) { _ in
                    XCTFail("An unsupported control must fail before approval")
                    return true
                }
                XCTFail("Scrolling capability must not authorize input events")
            } catch {
                XCTAssertEqual(error.localizedDescription, "This control does not support the requested input.")
            }
        }

        let events = try await webView.evaluateJavaScript("[document.body.dataset.clicked, document.body.dataset.key].join('|')")
        XCTAssertEqual(events as? String, "|")
        let scroll = try await call("page_interact", ["action": "scroll", "documentId": document, "ref": region, "direction": "down"], navigator)
        XCTAssertEqual(scroll["moved"] as? Bool, true)
    }

    func testSameOriginFrameRequiresItsObservedDocumentAndRejectsReplacedDocument() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <iframe id="delivery" style="width:300px;height:220px" srcdoc="
                <label for='reference'>Frame reference</label><input id='reference'>"></iframe>
            <iframe id="isolated" sandbox srcdoc="<button>Inaccessible</button>"></iframe>
            """, frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let main = try await call("page_interact", ["action": "observe"], navigator)
        let document = try XCTUnwrap(main["documentId"] as? String)
        let page = try await call("page_interact", ["action": "observe", "framePath": ["#delivery"]], navigator)
        let frameDocument = try XCTUnwrap(page["frameDocumentId"] as? String)
        let field = try interactionRef(page, label: "Frame reference", capability: "canFill")
        var arguments: [String: Any] = [
            "action": "fill", "documentId": document, "framePath": ["#delivery"], "frameDocumentId": frameDocument,
            "ref": field, "text": "FRAME-417"
        ]
        let result = try await applyInteraction(arguments, navigator)
        XCTAssertEqual(result["applied"] as? Bool, true)
        let value = try await webView.evaluateJavaScript("delivery.contentDocument.querySelector('input').value")
        XCTAssertEqual(value as? String, "FRAME-417")

        _ = try await webView.callAsyncJavaScript("""
            const frame = document.querySelector('#delivery');
            await new Promise(resolve => {
                frame.onload = resolve;
                frame.srcdoc = '<iframe id="nested" style="height:120px" srcdoc="&lt;label for=reference&gt;Nested reference&lt;/label&gt;&lt;input id=reference&gt;"></iframe>';
            });
            return true;
            """, arguments: [:], in: nil, contentWorld: .page)
        arguments["action"] = "click_at"
        arguments["x"] = 30
        arguments["y"] = 20
        arguments.removeValue(forKey: "ref")
        arguments.removeValue(forKey: "text")
        do {
            _ = try await call("page_interact", arguments, navigator) { _ in
                XCTFail("A replaced frame must fail before approval")
                return true
            }
            XCTFail("A stale frame document must not be targeted")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("frame document changed"), error.localizedDescription)
        }
        let nested = try await call("page_interact", ["action": "observe", "framePath": ["#delivery", "#nested"]], navigator)
        let nestedDocument = try XCTUnwrap(nested["frameDocumentId"] as? String)
        let nestedField = try interactionRef(nested, label: "Nested reference", capability: "canFill")
        let nestedFill = try await applyInteraction([
            "action": "fill", "documentId": document, "framePath": ["#delivery", "#nested"],
            "frameDocumentId": nestedDocument, "ref": nestedField, "text": "NESTED-417"
        ], navigator)
        XCTAssertEqual(nestedFill["applied"] as? Bool, true)
        let nestedValue = try await webView.evaluateJavaScript("delivery.contentDocument.querySelector('#nested').contentDocument.querySelector('input').value")
        XCTAssertEqual(nestedValue as? String, "NESTED-417")
        do {
            _ = try await call("page_interact", ["action": "observe", "framePath": ["#isolated"]], navigator)
            XCTFail("A sandboxed cross-origin frame must not be inspected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("inaccessible"), error.localizedDescription)
        }
    }

    func testFrameInputRejectsRotatedWrapperAndPreservesAxisAlignedScaling() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <div id="wrapper" style="position:fixed;left:200px;top:50px;transform-origin:0 0;transform:scale(0.8,1.2)">
                <iframe id="delivery" style="display:block;width:200px;height:120px;border:0" srcdoc="
                    <button style='position:fixed;left:10px;top:10px;width:60px;height:60px'
                        onclick='document.body.dataset.clicked=1'>Ship</button>"></iframe>
            </div>
            <div id="cover" style="position:fixed;left:175px;top:65px;width:10px;height:10px;background:white;z-index:1"></div>
            """, frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let framePath = ["#delivery"]
        let observe: [String: Any] = ["action": "observe", "framePath": framePath]
        let page = try await call("page_interact", observe, navigator)
        _ = try interactionRef(page, label: "Ship", capability: "canClick")
        let arguments: [String: Any] = [
            "action": "click_at", "documentId": try XCTUnwrap(page["documentId"] as? String),
            "framePath": framePath, "frameDocumentId": try XCTUnwrap(page["frameDocumentId"] as? String),
            "x": 20, "y": 20
        ]
        var prompted = false
        do {
            _ = try await call("page_interact", arguments, navigator) { _ in
                prompted = true
                _ = try? await webView.evaluateJavaScript("wrapper.style.transform = 'rotate(90deg)'; void 0;")
                return true
            }
            XCTFail("Rotation during approval must stop the click")
        } catch {
            XCTAssertTrue(prompted)
            XCTAssertTrue(error.localizedDescription.contains("cannot be mapped"), error.localizedDescription)
        }
        let covered = try await webView.evaluateJavaScript("""
            [document.elementFromPoint(180, 70)?.id, delivery.contentDocument.body.dataset.clicked ?? ''].join('|')
            """)
        XCTAssertEqual(covered as? String, "cover|")

        _ = try await webView.evaluateJavaScript("wrapper.style.transform = 'none'; wrapper.style.rotate = '90deg'; void 0;")
        do {
            _ = try await call("page_interact", arguments, navigator) { _ in
                XCTFail("An individually rotated ancestor must fail before approval")
                return true
            }
            XCTFail("The individual rotate property must also be checked")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("cannot be mapped"), error.localizedDescription)
        }

        _ = try await webView.evaluateJavaScript("""
            wrapper.style.rotate = '0deg'; wrapper.style.scale = '0.8 1.2'; wrapper.style.translate = '5px 4px'; void 0;
            """)
        let scaled = try await call("page_interact", observe, navigator)
        _ = try interactionRef(scaled, label: "Ship", capability: "canClick")
        let result = try await applyInteraction(arguments, navigator)
        XCTAssertEqual(result["applied"] as? Bool, true)
        let clicked = try await webView.evaluateJavaScript("delivery.contentDocument.body.dataset.clicked")
        XCTAssertEqual(clicked as? String, "1")
    }

    func testFrameInputUsesPaddedContentBoxForCoverageAndScaling() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <iframe id="delivery" style="position:fixed;left:20px;top:40px;width:180.5px;height:110.25px;
                padding:20.5px 30.25px;border:2.5px solid black;transform-origin:0 0;object-position:right bottom"
                srcdoc="<button style='position:fixed;left:10px;top:10px;width:80px;height:80px'
                    onclick='document.body.dataset.clicked=1'>Ship</button>"></iframe>
            <div id="cover" style="position:fixed;left:70px;top:80px;width:10px;height:10px;background:white;z-index:1"></div>
            """, frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let framePath = ["#delivery"]
        let observe: [String: Any] = ["action": "observe", "framePath": framePath]
        let page = try await call("page_interact", observe, navigator)
        _ = try interactionRef(page, label: "Ship", capability: "canClick")
        let arguments: [String: Any] = [
            "action": "click_at", "documentId": try XCTUnwrap(page["documentId"] as? String),
            "framePath": framePath, "frameDocumentId": try XCTUnwrap(page["frameDocumentId"] as? String),
            "x": 20, "y": 20
        ]
        let covered = try await webView.evaluateJavaScript("""
            (() => {
                const style = getComputedStyle(delivery);
                return document.elementFromPoint(40 + parseFloat(style.borderLeftWidth) + 30.25,
                    60 + parseFloat(style.borderTopWidth) + 20.5)?.id;
            })()
            """)
        XCTAssertEqual(covered as? String, "cover")
        do {
            _ = try await call("page_interact", arguments, navigator) { _ in
                XCTFail("A covered point in the padded frame must fail before approval")
                return true
            }
            XCTFail("A point covered at its padded position must not receive a click")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("frame is covered"), error.localizedDescription)
        }
        let before = try await webView.evaluateJavaScript("delivery.contentDocument.body.dataset.clicked ?? ''")
        XCTAssertEqual(before as? String, "")

        let measured = try await webView.evaluateJavaScript("""
            (() => {
                cover.hidden = true;
                delivery.style.boxSizing = 'border-box';
                delivery.style.transform = 'scale(1.25, 1.5)';
                const style = getComputedStyle(delivery);
                return [
                    (20 + (20 + 30.25 + parseFloat(style.borderLeftWidth)) * 1.25 - visualViewport.offsetLeft) / visualViewport.width,
                    (40 + (20 + 20.5 + parseFloat(style.borderTopWidth)) * 1.5 - visualViewport.offsetTop) / visualViewport.height
                ];
            })()
            """)
        let expected = try XCTUnwrap(measured as? [Double])
        let result = try await applyInteraction(arguments, navigator)
        XCTAssertEqual(result["applied"] as? Bool, true)
        let point = try XCTUnwrap(result["pointer"] as? [String: Double])
        XCTAssertEqual(try XCTUnwrap(point["unitX"]), expected[0], accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(point["unitY"]), expected[1], accuracy: 0.0001)
        let clicked = try await webView.evaluateJavaScript("delivery.contentDocument.body.dataset.clicked")
        XCTAssertEqual(clicked as? String, "1")
    }

    func testFrameInputRejectsCoveredCoordinatesAndUnfocusedKeys() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <iframe id="delivery" style="position:fixed;left:0;top:0;width:300px;height:220px;border:0" srcdoc="
                <button style='position:fixed;left:10px;top:10px;width:140px;height:80px'
                    onclick='document.body.dataset.clicked=1' onpointermove='document.body.dataset.moved=1'>Shipment</button>
                <input id='frameField' style='position:fixed;left:10px;top:110px;width:140px;height:24px'
                    onkeydown='document.body.dataset.key=event.key'>"></iframe>
            <div id="cover" style="position:fixed;left:0;top:0;width:300px;height:30px;background:white;z-index:1"></div>
            <input id="rootField" style="position:fixed;left:20px;top:260px">
            """, frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let page = try await call("page_interact", ["action": "observe", "framePath": ["#delivery"]], navigator)
        _ = try interactionRef(page, label: "Shipment", capability: "canClick")
        let scope: [String: Any] = [
            "documentId": try XCTUnwrap(page["documentId"] as? String), "framePath": ["#delivery"],
            "frameDocumentId": try XCTUnwrap(page["frameDocumentId"] as? String)
        ]
        func args(_ action: [String: Any]) -> [String: Any] {
            scope.merging(action) { _, new in new }
        }
        func rejectBeforeApproval(_ arguments: [String: Any], message: String) async {
            do {
                _ = try await call("page_interact", arguments, navigator) { _ in
                    XCTFail("An unavailable target must be rejected before approval")
                    return true
                }
                XCTFail("The target was unavailable")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains(message), error.localizedDescription)
            }
        }
        await rejectBeforeApproval(args(["action": "click_at", "x": 20, "y": 15]), message: "frame is covered")
        let before = try await webView.evaluateJavaScript("delivery.contentDocument.body.dataset.clicked || ''")
        XCTAssertEqual(before as? String, "")
        var prompted = false
        do {
            _ = try await call("page_interact", args(["action": "move", "x": 20, "y": 40]), navigator) { _ in
                prompted = true
                _ = try? await webView.evaluateJavaScript("cover.style.height = '45px'; void 0;")
                return true
            }
            XCTFail("A point covered during approval must not receive the move")
        } catch {
            XCTAssertTrue(prompted)
            XCTAssertTrue(error.localizedDescription.contains("frame is covered"), error.localizedDescription)
        }
        let moved = try await webView.evaluateJavaScript("delivery.contentDocument.body.dataset.moved || ''")
        XCTAssertEqual(moved as? String, "")
        let clicked = try await applyInteraction(args(["action": "click_at", "x": 20, "y": 55]), navigator)
        XCTAssertEqual(clicked["applied"] as? Bool, true)
        let clickMarker = try await webView.evaluateJavaScript("delivery.contentDocument.body.dataset.clicked")
        XCTAssertEqual(clickMarker as? String, "1")

        _ = try await webView.evaluateJavaScript("rootField.focus(); void 0;")
        let press = args(["action": "press", "key": "Escape"])
        await rejectBeforeApproval(press, message: "Focus a visible control")
        let focused = try await webView.evaluateJavaScript("delivery.contentDocument.querySelector('#frameField').focus(); document.activeElement.id")
        XCTAssertEqual(focused as? String, "delivery")
        _ = try await webView.evaluateJavaScript("cover.style.height = '140px'; void 0;")
        await rejectBeforeApproval(press, message: "Focus a visible control")
        _ = try await webView.evaluateJavaScript("cover.style.height = '30px'; void 0;")
        let result = try await applyInteraction(press, navigator)
        XCTAssertEqual(result["applied"] as? Bool, true)
        let key = try await webView.evaluateJavaScript("delivery.contentDocument.body.dataset.key")
        XCTAssertEqual(key as? String, "Escape")
    }

    func testPageInteractionRejectsEditingKeysWithoutSelectionButAllowsFillAndEscape() async throws {
        let webView = await load("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <label for="email">Email address</label>
            <input id="email" type="email" value="first@example.invalid"
                onkeydown="this.dataset.key = event.key">
            """, frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let page = try await call("page_interact", ["action": "observe"], navigator)
        let document = try XCTUnwrap(page["documentId"] as? String)
        let field = try interactionRef(page, label: "Email address", capability: "canFill")
        let focused = try await webView.evaluateJavaScript("document.getElementById('email').focus(); document.activeElement.id")
        XCTAssertEqual(focused as? String, "email")

        for key in ["A", "Space", "Backspace", "Delete"] {
            do {
                _ = try await call("page_interact", ["action": "press", "documentId": document, "key": key], navigator) { _ in
                    XCTFail("Unsupported email editing must fail before approval")
                    return true
                }
                XCTFail("An editing key must not guess the selection position")
            } catch {
                XCTAssertEqual(error.localizedDescription, "This field does not expose its selection. Use fill to replace its value.")
            }
        }
        let beforeFill = try await webView.evaluateJavaScript("document.activeElement.value + '|' + (document.activeElement.dataset.key || '')")
        XCTAssertEqual(beforeFill as? String, "first@example.invalid|")

        let fill = try await applyInteraction(["action": "fill", "documentId": document, "ref": field, "text": "next@example.invalid"], navigator)
        XCTAssertEqual(fill["applied"] as? Bool, true)
        let escape = try await applyInteraction(["action": "press", "documentId": document, "key": "Escape"], navigator)
        XCTAssertEqual(escape["applied"] as? Bool, true)
        let afterEscape = try await webView.evaluateJavaScript("document.activeElement.value + '|' + document.activeElement.dataset.key")
        XCTAssertEqual(afterEscape as? String, "next@example.invalid|Escape")
    }
}
