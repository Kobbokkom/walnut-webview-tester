import SwiftUI
import WebKit
import XCTest

@testable import wina

final class InfoSettingsSheetTests: XCTestCase {
    func testSafariVCInfoViewUsesBindingForWebViewID() {
        var id = UUID()
        let binding = Binding(get: { id }, set: { id = $0 })
        var view = SafariVCInfoView(webViewID: binding)

        XCTAssertEqual(view.webViewID, id)

        let newID = UUID()
        view.webViewID = newID
        XCTAssertEqual(id, newID)
    }

    func testInfoViewStoresBindingsWhenProvided() {
        var id = UUID()
        var url = "https://example.com"
        let idBinding = Binding(get: { id }, set: { id = $0 })
        let urlBinding = Binding(get: { url }, set: { url = $0 })
        let view = InfoView(navigator: nil, webViewID: idBinding, loadedURL: urlBinding)

        XCTAssertEqual(view.webViewID?.wrappedValue, id)
        XCTAssertEqual(view.loadedURL?.wrappedValue, url)

        let newID = UUID()
        let newURL = "https://apple.com"
        view.webViewID?.wrappedValue = newID
        view.loadedURL?.wrappedValue = newURL

        XCTAssertEqual(id, newID)
        XCTAssertEqual(url, newURL)
    }

    func testLiveSettingsDescriptionCopy() {
        XCTAssertEqual(SettingsCopy.liveSettingsDescription.key, "Apply to save changes")
    }
}

@MainActor
final class EmulationRegressionTests: XCTestCase {
    func testEmulationUsesNativeBooleanMediaQueryEvaluation() async throws {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        await webView.loadHTMLStringAsync("<html><body>test</body></html>", baseURL: nil)
        _ = try await webView.evaluateJavaScript(WebViewScripts.emulationConfigScript(
            colorScheme: "dark", reducedMotion: true, highContrast: true, reducedTransparency: true))
        _ = try await webView.evaluateJavaScript(WebViewScripts.emulationBootstrap)
        let cases: [(String, Bool)] = [
            ("(prefers-color-scheme: dark)", true),
            ("not (prefers-color-scheme: dark)", false),
            ("(prefers-color-scheme: dark) and (min-width: 999999px)", false),
            ("(prefers-color-scheme: light), (min-width: 999999px)", false),
            ("(prefers-color-scheme: light) or (prefers-reduced-motion: reduce)", true),
            ("(  prefers-color-scheme : DARK  )", true),
            ("(prefers-color-scheme: dark) and (unknown-feature: yes)", false),
            ("(prefers-color-scheme: sepia)", false),
            ("screen and (prefers-contrast: more)", true),
            ("not (prefers-reduced-transparency: reduce)", false),
            ("(prefers-reduced-motion)", true),
            ("not (prefers-reduced-motion)", false),
            ("( prefers-contrast )", true),
            ("not (prefers-contrast)", false),
            ("(prefers-reduced-transparency)", true),
            ("not (prefers-reduced-transparency)", false)
        ]
        for (query, expected) in cases {
            let data = try JSONSerialization.data(withJSONObject: query, options: .fragmentsAllowed)
            let literal = try XCTUnwrap(String(data: data, encoding: .utf8))
            let result = try await webView.evaluateJavaScript("window.matchMedia(\(literal)).matches") as? Bool
            XCTAssertEqual(result, expected, query)
        }
        let isNative = try await webView.evaluateJavaScript("window.matchMedia('(prefers-color-scheme: dark)') instanceof MediaQueryList") as? Bool
        XCTAssertEqual(isNative, true)
        let media = try await webView.evaluateJavaScript("window.matchMedia('(prefers-color-scheme: dark)').media") as? String
        XCTAssertEqual(media, "(prefers-color-scheme: dark)")
    }
}

@MainActor
final class SharedInfoCacheRegressionTests: XCTestCase {
    private final class InfoNavigator: WebViewNavigator {
        var invalidatesDuringEvaluation = false
        var userAgent = "first session"

        override func evaluateJavaScript(_ script: String) async -> Any? {
            if invalidatesDuringEvaluation {
                await SharedInfoWebView.shared.setNavigator(self)
            }
            return ["browser": ["userAgent": userAgent]]
        }
    }

    func testReopeningInfoClearsSameNavigatorCaches() async {
        let navigator = InfoNavigator()
        let webView = WKWebView(frame: .zero)
        navigator.attach(to: webView)
        let shared = SharedInfoWebView.shared
        shared.setNavigator(navigator)
        defer { shared.setNavigator(nil); navigator.detach() }
        let first = await WebViewInfo.load { _ in }
        XCTAssertEqual(first.userAgent, "first session")
        navigator.userAgent = "second session"
        shared.setNavigator(navigator)
        XCTAssertNil(shared.cachedWebViewInfo)
        let second = await WebViewInfo.load { _ in }
        XCTAssertEqual(second.userAgent, "second session")
    }

    func testInvalidatedLoadsCannotRepopulateNewSessionCaches() async {
        let navigator = InfoNavigator()
        let webView = WKWebView(frame: .zero)
        navigator.attach(to: webView)
        let shared = SharedInfoWebView.shared
        shared.setNavigator(navigator)
        defer { shared.setNavigator(nil); navigator.detach() }
        navigator.invalidatesDuringEvaluation = true
        _ = await WebViewInfo.load { _ in }
        XCTAssertNil(shared.cachedWebViewInfo)
        _ = await MediaCodecInfo.load { _ in }
        XCTAssertNil(shared.cachedCodecInfo)
        _ = await DisplayInfo.load { _ in }
        XCTAssertNil(shared.cachedDisplayInfo)
        _ = await AccessibilityInfo.load { _ in }
        XCTAssertNil(shared.cachedAccessibilityInfo)
        navigator.invalidatesDuringEvaluation = false
        _ = await WebViewInfo.load { _ in }
        _ = await MediaCodecInfo.load { _ in }
        _ = await DisplayInfo.load { _ in }
        _ = await AccessibilityInfo.load { _ in }
        XCTAssertNotNil(shared.cachedWebViewInfo)
        XCTAssertNotNil(shared.cachedCodecInfo)
        XCTAssertNotNil(shared.cachedDisplayInfo)
        XCTAssertNotNil(shared.cachedAccessibilityInfo)
    }
}

@MainActor
final class EmulationInstallationTests: XCTestCase {
    private final class LoadDelegate: NSObject, WKNavigationDelegate {
        var completion: (() -> Void)?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let action = completion
            completion = nil
            action?()
        }
    }

    func testApplyReplacesInstalledConfigurationAndPreservesOtherHooks() async throws {
        let configuration = WKWebViewConfiguration()
        let controller = configuration.userContentController
        let before = WKUserScript(source: "window.__before = true;", injectionTime: .atDocumentStart, forMainFrameOnly: false)
        let original = WKUserScript(source: WebViewScripts.emulationConfigScript(colorScheme: "system", reducedMotion: false, highContrast: false, reducedTransparency: false), injectionTime: .atDocumentStart, forMainFrameOnly: false)
        let bootstrap = WKUserScript(source: WebViewScripts.emulationBootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        let after = WKUserScript(source: "window.__after = true;", injectionTime: .atDocumentStart, forMainFrameOnly: false)
        [before, original, bootstrap, after].forEach(controller.addUserScript)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 640), configuration: configuration)
        await webView.loadHTMLStringAsync("<html><body>test</body></html>", baseURL: nil)
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        defer { navigator.detach() }
        let delegate = LoadDelegate()
        webView.navigationDelegate = delegate
        let loaded = expectation(description: "Emulation reload completed")
        delegate.completion = { loaded.fulfill() }
        let script = WebViewScripts.emulationConfigScript(colorScheme: "dark", reducedMotion: true, highContrast: true, reducedTransparency: true)
        let historyCount = webView.backForwardList.backList.count
        navigator.applyEmulation(configScript: script)
        XCTAssertEqual(controller.userScripts.count, 4)
        XCTAssertEqual(controller.userScripts.map(\.source), [before.source, script, bootstrap.source, after.source])
        await fulfillment(of: [loaded], timeout: 10)
        XCTAssertEqual(webView.backForwardList.backList.count, historyCount)
        let config = try await webView.evaluateJavaScript("window.__winaEmulationConfig.colorScheme") as? String
        XCTAssertEqual(config, "dark")
        let effects = try await webView.evaluateJavaScript("window.__before && window.__after && window.matchMedia('(prefers-reduced-motion: reduce)').matches && !!document.getElementById('wina-emulation-style')") as? Bool
        XCTAssertEqual(effects, true)
    }
}
