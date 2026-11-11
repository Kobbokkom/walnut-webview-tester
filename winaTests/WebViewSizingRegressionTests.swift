import SwiftUI
import WebKit
import XCTest
@testable import wina

@MainActor
final class WebViewSizingRegressionTests: XCTestCase {
    private struct Harness: View {
        let navigator: WebViewNavigator
        @State private var identifier = UUID()

        var body: some View {
            WebViewContainer(urlString: "https://example.invalid/initial",
                             webViewID: identifier, navigator: navigator)
        }
    }

    func testLiveSizingPreservesNativeViewAndPageState() async throws {
        try await withHostedWebView { host, webView, _ in
            await webView.loadHTMLStringAsync("<html><body>resized page</body></html>", baseURL: nil)
            _ = try await webView.evaluateJavaScript("window.pageMarker = 'keep this document'")
            let originalWidth = webView.bounds.width
            UserDefaults.standard.set(0.75, forKey: "webViewWidthRatio")
            UserDefaults.standard.set(0.75, forKey: "webViewHeightRatio")
            for _ in 0..<100 {
                host.view.layoutIfNeeded()
                if let current = findWebView(in: host.view), current.bounds.width < originalWidth * 0.9 { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            try await Task.sleep(for: .milliseconds(200))
            let resized = try XCTUnwrap(findWebView(in: host.view))
            XCTAssertLessThan(resized.bounds.width, originalWidth * 0.9)
            XCTAssertTrue(resized === webView, "Live resizing must keep the current WKWebView")
            let marker = try await resized.evaluateJavaScript("window.pageMarker") as? String
            XCTAssertEqual(marker, "keep this document")
        }
    }

    func testAbsentNativeDefaultsMatchSettingsAndStoredTrueStillApplies() async throws {
        for storedValue in [false, true] {
            try await withHostedWebView(storedControls: storedValue ? true : nil) { _, webView, _ in
                XCTAssertEqual(webView.allowsBackForwardNavigationGestures, storedValue)
                XCTAssertEqual(webView.configuration.ignoresViewportScaleLimits, storedValue)
            }
        }
    }

    func testTextInteractionAppliesToTheExistingNativeView() async throws {
        try await withHostedWebView { host, webView, _ in
            for enabled in [false, true] {
                UserDefaults.standard.set(enabled, forKey: "textInteractionEnabled")
                for _ in 0..<100 {
                    host.view.layoutIfNeeded()
                    if webView.configuration.preferences.isTextInteractionEnabled == enabled { break }
                    try await Task.sleep(for: .milliseconds(20))
                }
                XCTAssertEqual(webView.configuration.preferences.isTextInteractionEnabled, enabled)
                XCTAssertTrue(findWebView(in: host.view) === webView)
            }
        }
    }

    private func withHostedWebView(
        storedControls: Bool? = nil,
        perform: (UIHostingController<Harness>, WKWebView, WebViewNavigator) async throws -> Void
    ) async throws {
        let defaults = UserDefaults.standard
        let keys = ["webViewWidthRatio", "webViewHeightRatio", "allowsBackForwardGestures", "allowZoom", "textInteractionEnabled"]
        let original = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, original) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(1.0, forKey: "webViewWidthRatio")
        defaults.set(1.0, forKey: "webViewHeightRatio")
        for key in ["allowsBackForwardGestures", "allowZoom"] {
            if let storedControls { defaults.set(storedControls, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let navigator = WebViewNavigator()
        let host = UIHostingController(rootView: Harness(navigator: navigator))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            navigator.detach()
            previousKeyWindow?.makeKey()
        }
        for _ in 0..<100 {
            host.view.layoutIfNeeded()
            if let webView = findWebView(in: host.view), webView.bounds.width > 0 {
                webView.stopLoading()
                try await perform(host, webView, navigator)
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("The production WebViewContainer did not create a laid-out WKWebView")
    }

    private func findWebView(in view: UIView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        return view.subviews.lazy.compactMap { self.findWebView(in: $0) }.first
    }
}
