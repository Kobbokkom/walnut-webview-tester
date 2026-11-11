import Network
import WebKit
import XCTest
@testable import wina

@MainActor
final class AgentSourceResourceTests: XCTestCase {
    func testHTMLSourceIdentifiesLiveDOMSerialization() async throws {
        let webView = WKWebView(frame: .zero)
        await webView.loadHTMLStringAsync("<p>initial fixture</p>", baseURL: nil)
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        _ = try await webView.evaluateJavaScript("document.querySelector('p').textContent = 'updated fixture'; void 0;")
        let result = try await AgentDevTools.call(
            "sources_list", arguments: ["section": "html", "query": "updated fixture"], navigator: navigator,
            storage: StorageManager(), console: ConsoleSession(), authorize: { _ in true }
        )
        let html = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(html["retrieval"] as? String, "live-dom")
        let entries = try XCTUnwrap(html["entries"] as? [[String: Any]])
        XCTAssertTrue(entries.contains { ($0["text"] as? String)?.contains("updated fixture") == true })
        XCTAssertFalse(entries.contains { ($0["text"] as? String)?.contains("initial fixture") == true })
        withExtendedLifetime(webView) {}
    }

    func testExternalSourceReadsRespectCORSAndKeepPagination() async throws {
        let source = "/*" + String(repeating: "a", count: 20_000) + "needle-😀*/window.loaded = true;"
        let sameOrigin = try await server(source, type: "text/javascript")
        let allowed = try await server("window.allowed = 'external needle';", type: "text/javascript", cors: true)
        let denied = try await server("window.denied = 'private source';", type: "text/javascript")
        let styles = try await server(".external { color: rgb(1, 2, 3); }", type: "text/css", cors: true)
        defer { [sameOrigin, allowed, denied, styles].forEach { $0.cancel() } }
        let base = try url(sameOrigin)
        let webView = WKWebView(frame: .zero)
        await webView.loadHTMLStringAsync("""
            <link rel="stylesheet" href="\(try url(styles))">
            <script src="\(base)"></script>
            <script src="\(try url(allowed))"></script>
            <script src="\(try url(denied))"></script>
            """, baseURL: base)
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)

        let matched = try await detail("script", index: 0, navigator: navigator, values: ["query": "needle"])
        XCTAssertEqual(matched["retrieval"] as? String, "requested-resource")
        let row = try XCTUnwrap((matched["entries"] as? [[String: Any]])?.first)
        XCTAssertEqual(row["textOffset"] as? Int, 20_002)
        XCTAssertTrue(try XCTUnwrap(row["value"] as? String).hasPrefix("needle-😀"))
        let paged = try await detail("script", index: 0, navigator: navigator)
        let first = try XCTUnwrap((paged["entries"] as? [[String: Any]])?.first)
        XCTAssertEqual(first["nextTextOffset"] as? Int, 8192)
        let allowedSource = try await detail("script", index: 1, navigator: navigator)
        XCTAssertEqual((allowedSource["entries"] as? [[String: Any]])?.first?["value"] as? String, "window.allowed = 'external needle';")

        do {
            _ = try await detail("script", index: 2, navigator: navigator)
            XCTFail("A loaded no-CORS script does not grant source access")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Source is unavailable under this page's CORS or network policy.")
        }

        let css = try await detail("stylesheet", index: 0, navigator: navigator)
        XCTAssertEqual(css["retrieval"] as? String, "requested-resource")
        XCTAssertEqual(css["raw"] as? String, ".external { color: rgb(1, 2, 3); }")
        XCTAssertEqual((css["rules"] as? [[String: Any]])?.first?["selector"] as? String, ".external")
        let sheetCount = try await webView.evaluateJavaScript("document.styleSheets.length")
        XCTAssertEqual(sheetCount as? Int, 1)
        withExtendedLifetime(webView) {}
    }

    func testExternalSourceRequiresApprovalAndRejectsOversizedResponse() async throws {
        let listener = try await startHTTPServer { connection in
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/javascript\r\nContent-Length: 8388609\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
        defer { listener.cancel() }
        let webView = WKWebView(frame: .zero)
        await webView.loadHTMLStringAsync("<script></script>", baseURL: try url(listener))
        _ = try await webView.evaluateJavaScript("document.scripts[0].src = '/large.js'; void 0")
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        do {
            _ = try await AgentDevTools.call(
                "sources_detail", arguments: ["kind": "script", "index": 0], navigator: navigator,
                storage: StorageManager(), console: ConsoleSession(), authorize: { _ in false }
            )
            XCTFail("External source access must require approval")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The iPhone did not approve this action.")
        }
        do {
            _ = try await detail("script", index: 0, navigator: navigator)
            XCTFail("Large sources must fail before buffering the body")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Source exceeds the 8 MiB retrieval limit.")
        }
        withExtendedLifetime(webView) {}
    }

    func testSourceReplacementOrCredentialChangeDuringApprovalDoesNotRequestIt() async throws {
        let unexpectedRequest = expectation(description: "No source request after its approval scope changes")
        unexpectedRequest.isInverted = true
        let listener = try await startHTTPServer { connection in
            unexpectedRequest.fulfill()
            connection.cancel()
        }
        defer { listener.cancel() }
        let base = try url(listener)
        let webView = WKWebView(frame: .zero)
        await webView.loadHTMLStringAsync(
            "<script type='application/json' src='\(base)?token=private-fixture#secret-fragment'></script>", baseURL: base
        )
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let document = navigator.documentID

        for change in [
            "script.replaceWith(script.cloneNode(true))",
            "script.setAttribute('crossorigin', 'use-credentials')",
            "script.src = '/other-source?token=another-fixture'"
        ] {
            do {
                _ = try await AgentDevTools.call(
                    "sources_detail", arguments: ["kind": "script", "index": 0], navigator: navigator,
                    storage: StorageManager(), console: ConsoleSession(), authorize: { prompt in
                        XCTAssertTrue(prompt.contains(base.absoluteString))
                        XCTAssertFalse(prompt.contains("private-fixture"))
                        XCTAssertFalse(prompt.contains("secret-fragment"))
                        do {
                            _ = try await webView.evaluateJavaScript("{ const script = document.scripts[0]; \(change); }; void 0;")
                            return true
                        } catch {
                            XCTFail("Could not change the fixture source during approval: \(error.localizedDescription)")
                            return false
                        }
                    }
                )
                XCTFail("A changed source must be selected and approved again")
            } catch {
                XCTAssertEqual(error.localizedDescription, "The selected source changed. Refresh Sources and select it again.")
            }
        }
        XCTAssertEqual(navigator.documentID, document)
        await fulfillment(of: [unexpectedRequest], timeout: 0.25)
        withExtendedLifetime(webView) {}
    }

    func testNativeSourcePreviewUsesDisplayedSelectionAndCapsText() async throws {
        let source = "/*" + String(repeating: "a", count: 55_000) + "*/"
        let webView = WKWebView(frame: .zero)
        await webView.loadHTMLStringAsync("<script>\(source)</script>", baseURL: nil)
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let manager = SourcesManager()
        manager.setNavigator(navigator)
        await manager.fetchScripts()
        let selection = try XCTUnwrap(manager.scripts.first?.selection)
        let script = ScriptDetailView.contentScript(index: 0, expected: selection)
        let before = try await navigator.callAsyncJavaScriptReportingErrors("return \(script)", contentWorld: .defaultClient)
        let preview = try XCTUnwrap(AgentDevTools.parseJSON(before) as? [String: Any])
        XCTAssertEqual((preview["content"] as? String)?.count, 50_000)
        XCTAssertEqual(preview["truncated"] as? Bool, true)

        _ = try await webView.evaluateJavaScript("document.scripts[0].replaceWith(document.createElement('script')); void 0;")
        let after = try await navigator.callAsyncJavaScriptReportingErrors("return \(script)", contentWorld: .defaultClient)
        let stale = try XCTUnwrap(AgentDevTools.parseJSON(after) as? [String: Any])
        XCTAssertEqual(stale["error"] as? String, "The selected source changed. Refresh Sources and select it again.")
        withExtendedLifetime(webView) {}
    }

    private func server(_ content: String, type: String, cors: Bool = false) async throws -> NWListener {
        try await startHTTPServer { connection in
            let headers = cors ? "Access-Control-Allow-Origin: *\r\n" : ""
            let response = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nCache-Control: no-store\r\n\(headers)Content-Length: \(content.utf8.count)\r\nConnection: close\r\n\r\n" + content
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private func url(_ listener: NWListener) throws -> URL {
        try XCTUnwrap(URL(string: "http://127.0.0.1:\(XCTUnwrap(listener.port).rawValue)/source"))
    }

    private func detail(_ kind: String, index: Int, navigator: WebViewNavigator, values: [String: Any] = [:]) async throws -> [String: Any] {
        let result = try await AgentDevTools.call(
            "sources_detail", arguments: values.merging(["kind": kind, "index": index]) { _, value in value },
            navigator: navigator, storage: StorageManager(), console: ConsoleSession(), authorize: { _ in true }
        )
        return try XCTUnwrap(result as? [String: Any])
    }
}
