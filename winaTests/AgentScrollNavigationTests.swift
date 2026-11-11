import WebKit
import XCTest
@testable import wina

@MainActor
final class AgentScrollNavigationTests: XCTestCase {
    private final class ReplacingScrollNavigator: WebViewNavigator {
        var onScrollResult: (() -> Void)?

        override func callAsyncJavaScriptReportingErrors(_ script: String, contentWorld: WKContentWorld) async throws -> Any? {
            let value = try await super.callAsyncJavaScriptReportingErrors(script, contentWorld: contentWorld)
            onScrollResult?()
            return value
        }
    }

    func testScrollRejectsAReplacedDocument() async throws {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        await webView.loadHTMLStringAsync("<div style='height:2000px'>Scrollable page</div>", baseURL: nil)
        let navigator = ReplacingScrollNavigator()
        navigator.attach(to: webView)
        let document = navigator.documentID
        navigator.onScrollResult = { [weak navigator] in navigator?.documentDidChange(in: webView) }

        do {
            _ = try await scroll(using: navigator)
            XCTFail("A scroll result must belong to the active document")
        } catch {
            XCTAssertNotEqual(navigator.documentID, document)
            XCTAssertTrue(error.localizedDescription.contains("document changed"), error.localizedDescription)
        }
    }

    func testScrollRejectsAProvisionalNavigationBeforeCommit() async throws {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        await webView.loadHTMLStringAsync("<div style='height:2000px'>Scrollable page</div>", baseURL: nil)
        defer { withExtendedLifetime(webView) {} }
        let navigator = ReplacingScrollNavigator()
        navigator.attach(to: webView)
        let document = navigator.documentID
        let runID = navigator.agentNavigation.runID
        navigator.onScrollResult = { [weak navigator] in navigator?.agentNavigation.start(NSObject(), url: nil) }

        do {
            _ = try await scroll(using: navigator)
            XCTFail("A scroll result must belong to the active navigation run")
        } catch {
            XCTAssertEqual(navigator.documentID, document)
            XCTAssertNotEqual(navigator.agentNavigation.runID, runID)
            XCTAssertTrue(error.localizedDescription.contains("navigation interrupted"), error.localizedDescription)
        }
    }

    func testScrollAdvancesToTheNextMandatorySnapPoint() async throws {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        await webView.loadHTMLStringAsync("""
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                html { scroll-snap-type: y mandatory; }
                body { margin: 0; }
                section { height: 650px; scroll-snap-align: start; }
                aside { height: 650px; }
            </style>
            <section>First panel</section><aside></aside>
            <section>Second panel</section><aside></aside><section>Third panel</section>
            """, baseURL: nil)
        defer { withExtendedLifetime(webView) {} }
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)

        let result = try await scroll(using: navigator)
        XCTAssertEqual(result["moved"] as? Bool, true)
        let after = try XCTUnwrap((result["after"] as? [String: Any])?["y"] as? Double)
        XCTAssertGreaterThan(after, 0)
    }

    private func scroll(using navigator: WebViewNavigator) async throws -> [String: Any] {
        let result = try await AgentDevTools.call(
            "page_interact", arguments: ["action": "scroll", "direction": "down", "documentId": navigator.documentID.uuidString],
            navigator: navigator, storage: StorageManager(), console: ConsoleSession(), authorize: { _ in true }
        )
        return try XCTUnwrap(result as? [String: Any])
    }
}
