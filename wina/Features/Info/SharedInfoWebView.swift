//
//  SharedInfoWebView.swift
//  wina
//

import os
import SwiftUI
import WebKit

// MARK: - Shared WebView Manager

@MainActor
final class SharedInfoWebView {
    static let shared = SharedInfoWebView()

    var webView: WKWebView?
    var isReady = false
    private(set) var cacheGeneration = 0

    // External WebView navigator (for live page testing)
    private(set) var navigator: WebViewNavigator?

    // Cache
    var cachedWebViewInfo: WebViewInfo?
    var cachedCodecInfo: MediaCodecInfo?
    var cachedDisplayInfo: DisplayInfo?
    var cachedAccessibilityInfo: AccessibilityInfo?

    init(navigator: WebViewNavigator? = nil) {
        self.navigator = navigator
    }

    /// Whether using live WebView from the loaded page
    var isUsingLiveWebView: Bool {
        navigator?.isAttached == true
    }

    /// Current URL when using live WebView
    var currentURL: URL? {
        navigator?.currentURL
    }

    /// Set external navigator for live page testing
    func setNavigator(_ navigator: WebViewNavigator?) {
        self.navigator = navigator
        clearCache()
    }

    func initialize(onStatusUpdate: @escaping (String) -> Void) async {
        // If using live WebView, skip internal WebView initialization
        if isUsingLiveWebView {
            onStatusUpdate("Using loaded page WebView...")
            return
        }

        // Already initialized
        if isReady, webView != nil { return }

        onStatusUpdate("Launching WebView process...")

        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)

        // Load minimal HTML without waiting (non-blocking)
        wv.loadHTMLString("<html><body></body></html>", baseURL: URL(string: "https://example.com"))

        // Brief delay for WebView to initialize
        try? await Task.sleep(for: .milliseconds(100))

        self.webView = wv
        self.isReady = true
    }

    func evaluateJavaScript(_ script: String) async -> Any? {
        // Use live WebView if available
        if let navigator, navigator.isAttached {
            return await navigator.evaluateJavaScript(script)
        }
        // Fallback to internal test WebView
        guard let webView, isReady else { return nil }
        return await webView.evaluateJavaScriptAsync(script)
    }

    func clearCache() {
        cacheGeneration += 1
        cachedWebViewInfo = nil
        cachedCodecInfo = nil
        cachedDisplayInfo = nil
        cachedAccessibilityInfo = nil
    }
}

// MARK: - Prewarm WebView

/// Prewarm WebKit processes in background to reduce cold start latency
@MainActor
func prewarmInfoWebView() async {
    await SharedInfoWebView.shared.initialize { _ in }
}

// MARK: - WKWebView Async Extensions

extension WKWebView {
    func evaluateJavaScriptAsync(_ script: String) async -> Any? {
        await withCheckedContinuation { continuation in
            evaluateJavaScript(script) { result, error in
                if let error = error {
                    Logger().debug("[WKWebView] JavaScript error: \(error.localizedDescription)")
                }
                continuation.resume(returning: result)
            }
        }
    }

    @MainActor
    func loadHTMLStringAsync(_ string: String, baseURL: URL?) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let delegate = WebViewLoadDelegate {
                continuation.resume()
            }
            // Store delegate to prevent deallocation
            objc_setAssociatedObject(self, &WebViewLoadDelegate.associatedKey, delegate, .OBJC_ASSOCIATION_RETAIN)
            self.navigationDelegate = delegate
            self.loadHTMLString(string, baseURL: baseURL)
        }
    }
}

private class WebViewLoadDelegate: NSObject, WKNavigationDelegate {
    static var associatedKey: UInt8 = 0
    private let completion: () -> Void

    init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        completion()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completion()
    }
}
