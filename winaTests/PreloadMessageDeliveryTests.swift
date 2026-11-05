import SwiftUI
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

    private final class RequestObserver: NSObject, WKScriptMessageHandler {
        let coordinator: WKWebViewCoordinator
        let onRequest: () -> Void

        init(coordinator: WKWebViewCoordinator, onRequest: @escaping () -> Void) {
            self.coordinator = coordinator
            self.onRequest = onRequest
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            coordinator.userContentController(userContentController, didReceive: message)
            onRequest()
        }
    }

    func testBridgeRespondsInTheRequestingIframe() async throws {
        let (webView, _, _) = bridgeWebView(delayMilliseconds: 25)
        await webView.loadHTMLStringAsync("""
        <iframe srcdoc="<script>
            window.addEventListener('message', event => {
                if (event.data === 'request') window.webkit.messageHandlers.request.postMessage({ type: 'child' });
            });
            window.addEventListener('nativeReply', event => {
                parent.postMessage({ type: 'child-reply', ok: event.detail.ok }, '*');
            });
        </script>"></iframe>
        """, baseURL: URL(string: "https://example.com"))

        let result = try await webView.callAsyncJavaScript("""
        let topReplies = 0;
        window.addEventListener('nativeReply', () => topReplies++);
        const reply = new Promise(resolve => {
            window.addEventListener('message', event => {
                if (event.data?.type === 'child-reply') resolve(event.data.ok);
            });
            setTimeout(() => resolve(false), 1500);
        });
        document.querySelector('iframe').contentWindow.postMessage('request', '*');
        const childReceived = await reply;
        return [childReceived, topReplies === 0];
        """, arguments: [:], in: nil, contentWorld: .page) as? [Bool]
        XCTAssertEqual(result, [true, true])
    }

    func testReplacingAnIframeCancelsItsPendingReplyWithoutCancelingMainFrame() async throws {
        let delayMilliseconds = 1000
        let queued = expectation(description: "Child request queued in the real coordinator")
        let (webView, navigator, coordinator) = bridgeWebView(delayMilliseconds: delayMilliseconds) { queued.fulfill() }
        await webView.loadHTMLStringAsync("""
        <iframe srcdoc="<script>
            window.addEventListener('message', () => window.webkit.messageHandlers.request.postMessage({ type: 'child' }));
        </script>"></iframe>
        """, baseURL: URL(string: "https://example.com"))
        webView.navigationDelegate = coordinator
        _ = try await webView.evaluateJavaScript("document.querySelector('iframe').contentWindow.postMessage('request', '*');")
        await fulfillment(of: [queued], timeout: 3)
        XCTAssertEqual(coordinator.pendingBridgeResponseWorkItemCount, 1)

        coordinator.schedulePreloadBridgeResponse(
            "window.mainFrameReply = true; document.body;", channel: "main", delayMilliseconds: delayMilliseconds
        )
        _ = try await webView.callAsyncJavaScript("""
        const child = document.querySelector('iframe');
        await new Promise(resolve => {
            child.onload = resolve;
            child.srcdoc = `<script>window.addEventListener('nativeReply', () => window.oldReply = true);</script>`;
        });
        """, arguments: [:], in: nil, contentWorld: .page)
        let mainResponded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            navigator.preloadBridgeLogManager.entries.contains { $0.channel == "main" && $0.direction == .responded }
        }, object: nil)
        await fulfillment(of: [mainResponded], timeout: 3)

        let delivered = try await webView.evaluateJavaScript("""
        [window.mainFrameReply === true, document.querySelector('iframe').contentWindow.oldReply === true]
        """) as? [Bool]
        XCTAssertEqual(delivered, [true, false])
        XCTAssertFalse(navigator.preloadBridgeLogManager.entries.contains { $0.channel == "request" && $0.direction == .responded })
    }

    private func bridgeWebView(
        delayMilliseconds: Int, onRequest: (() -> Void)? = nil
    ) -> (WKWebView, WebViewNavigator, WKWebViewCoordinator) {
        let rule = BridgeResponseRule(
            response: BridgeResponse(target: .customEvent, bodyTemplate: #"{"ok":true}"#, eventName: "nativeReply"),
            delayMilliseconds: delayMilliseconds
        )
        let profile = WebViewPreloadProfile(isEnabled: true, bridgeChannels: [BridgeChannel(responseRules: [rule])])
        let navigator = WebViewNavigator()
        let coordinator = WKWebViewCoordinator(isLoading: .constant(false), navigator: navigator, preloadProfile: profile)
        let configuration = WKWebViewConfiguration()
        let handler: WKScriptMessageHandler = if let onRequest {
            RequestObserver(coordinator: coordinator, onRequest: onRequest)
        } else {
            coordinator
        }
        configuration.userContentController.add(handler, name: "request")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        coordinator.observeWebView(webView)
        return (webView, navigator, coordinator)
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
