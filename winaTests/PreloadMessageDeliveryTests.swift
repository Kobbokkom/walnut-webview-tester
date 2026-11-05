import WebKit
import XCTest
@testable import wina

@MainActor
final class PreloadMessageDeliveryTests: XCTestCase {
    private final class CaptureHandler: NSObject, WKScriptMessageHandler {
        var messages: [[String: Any]] = []
        var onControlMessage: (() -> Void)?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            messages.append(body)
            if (body["data"] as? [String: String])?["type"] == "pageControl" {
                onControlMessage?()
            }
        }
    }

    func testNativeResponsesSurviveStructuredCloneWithoutRecaptureOrPayloadChanges() async throws {
        let configuration = WKWebViewConfiguration()
        let handler = CaptureHandler()
        let controller = configuration.userContentController
        controller.add(handler, name: PreloadBridgeConstants.postMessageCaptureChannel)
        controller.addUserScript(WKUserScript(
            source: PreloadScriptBuilder.bootstrapScript(for: WebViewPreloadProfile(
                isEnabled: true, capturesWindowPostMessage: true)),
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        defer { controller.removeAllScriptMessageHandlers() }
        await webView.loadHTMLStringAsync("<html><body>bridge fixture</body></html>", baseURL: URL(string: "https://example.com"))
        _ = try await webView.evaluateJavaScript("""
        window.observed = [];
        window.origins = [];
        window.sources = [];
        window.addEventListener('message', function(event) {
            observed.push(event.data); origins.push(event.origin); sources.push(event.source === window);
        });
        """)
        let control = expectation(description: "Page message after native responses was captured")
        handler.onControlMessage = { control.fulfill() }
        _ = try await webView.evaluateJavaScript("""
        window.postMessage({type:'nativeResponse',nested:{value:1}}, '*');
        window.postMessage({type:'pageCollision',__winaPreloadNativePostMessageToken:'original'}, '*');
        """)
        let payloads = [#"{"type":"nativeResponse","nested":{"value":1}}"#,
                        #"[{"type":"nativeArray"}]"#, #""nativeString""#,
                        #"{"type":"nativeCollision","__winaPreloadNativePostMessageToken":"original"}"#]
        for payload in payloads {
            let script = PreloadScriptBuilder.responseScript(
                for: BridgeResponse(target: .postMessage, bodyTemplate: payload),
                message: [:], channel: "request")
            _ = try await webView.evaluateJavaScript(script)
        }
        _ = try await webView.evaluateJavaScript("window.postMessage({type:'pageControl'}, '*')")
        await fulfillment(of: [control], timeout: 5)
        XCTAssertEqual(handler.messages.count, 3, "Identical genuine page messages must remain captured")
        let observed = try await webView.evaluateJavaScript("JSON.stringify(window.observed)") as? String
        XCTAssertEqual(observed, #"[{"type":"nativeResponse","nested":{"value":1}},{"type":"pageCollision","__winaPreloadNativePostMessageToken":"original"},{"type":"nativeResponse","nested":{"value":1}},[{"type":"nativeArray"}],"nativeString",{"type":"nativeCollision","__winaPreloadNativePostMessageToken":"original"},{"type":"pageControl"}]"#)
        let unchangedDelivery = try await webView.evaluateJavaScript("sources.every(Boolean) && origins.every(origin => origin === origins[origins.length - 1])") as? Bool
        XCTAssertEqual(unchangedDelivery, true)
    }

    func testFailedNativePostDoesNotConsumeAGenuinePageMessage() async throws {
        let configuration = WKWebViewConfiguration()
        let handler = CaptureHandler()
        let controller = configuration.userContentController
        controller.add(handler, name: PreloadBridgeConstants.postMessageCaptureChannel)
        controller.addUserScript(WKUserScript(
            source: PreloadScriptBuilder.bootstrapScript(for: WebViewPreloadProfile(
                isEnabled: true, capturesWindowPostMessage: true)),
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        defer { controller.removeAllScriptMessageHandlers() }
        await webView.loadHTMLStringAsync("<html><body>bridge fixture</body></html>", baseURL: URL(string: "https://example.com"))
        let response = PreloadScriptBuilder.responseScript(
            for: BridgeResponse(target: .postMessage, bodyTemplate: #"{"type":"failedNative"}"#),
            message: [:], channel: "request")
        let failed = try await webView.evaluateJavaScript("""
        (function() {
            const post = window.postMessage;
            window.postMessage = function() { throw new Error('delivery failed'); };
            try { \(response) return false; }
            catch (_) { return true; }
            finally { window.postMessage = post; }
        })();
        """) as? Bool
        XCTAssertEqual(failed, true)
        let control = expectation(description: "Page control after failed native send")
        handler.onControlMessage = { control.fulfill() }
        _ = try await webView.evaluateJavaScript("window.postMessage({type:'failedNative'}, '*'); window.postMessage({type:'pageControl'}, '*');")
        await fulfillment(of: [control], timeout: 5)
        XCTAssertEqual(handler.messages.count, 2)
        XCTAssertEqual((handler.messages.first?["data"] as? [String: String])?["type"], "failedNative")
    }
}
