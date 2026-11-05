//
//  WebViewNavigator.swift
//  wina
//
//  WebView navigation controller with KVO observation.
//

import Observation
import Photos
import WebKit

// MARK: - Screenshot Types

enum ScreenshotResult {
    case success
    case permissionDenied
    case failed
}

enum PhotoPermissionStatus {
    case authorized
    case denied
    case notDetermined
}

// MARK: - WebView Navigator

@Observable
class WebViewNavigator {
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var currentURL: URL?
    /// 최초 입력된 URL (네비게이션 시작점)
    private(set) var initialURL: URL?
    var showScreenshotFlash: Bool = false
    var showScreenshotSavedToast: Bool = false
    var showRecordingSavedToast: Bool = false
    let consoleManager = ConsoleManager()
    let networkManager = NetworkManager()
    let performanceManager = PerformanceManager()
    let resourceManager = ResourceManager()
    let accessibilityManager = AccessibilityManager()
    let snippetsManager = SnippetsManager()
    let preloadBridgeLogManager = PreloadBridgeLogManager()
    let recorder = WebViewRecorder()
    // 수동 새로고침 시 coordinator에 reload 준비를 알리는 콜백입니다.
    @ObservationIgnored
    private var reloadPreparationHandler: (() -> Void)?

    // Eruda 설정 키를 한 곳에서 관리합니다.
    private static let erudaModeKey = "erudaModeEnabled"
    // Eruda 로드 여부를 확인하는 JavaScript입니다.
    static let erudaLoadedCheckScript = "typeof eruda !== 'undefined'"
    // Eruda 엔트리 버튼 존재 여부를 확인하는 JavaScript입니다.
    static let erudaEntryButtonCheckScript = "typeof eruda !== 'undefined' && !!document.querySelector('.eruda-entry-btn')"
    // Eruda를 초기화하고 엔트리 버튼을 표시하는 JavaScript입니다.
    static let erudaInitializeScript = """
        if (typeof eruda !== 'undefined' && typeof eruda.init === 'function') {
            eruda.init();
        }
        if (typeof eruda !== 'undefined') {
            try {
                const entryBtn = eruda.get && eruda.get('entryBtn');
                if (entryBtn && typeof entryBtn.show === 'function') {
                    entryBtn.show();
                }
            } catch (_) {}
        }
        """
    // Eruda를 강제로 재초기화하는 JavaScript입니다.
    static let erudaReinitializeScript = """
        if (typeof eruda !== 'undefined') {
            try {
                if (typeof eruda.destroy === 'function') {
                    eruda.destroy();
                }
            } catch (_) {}
            if (typeof eruda.init === 'function') {
                eruda.init();
            }
            try {
                const entryBtn = eruda.get && eruda.get('entryBtn');
                if (entryBtn && typeof entryBtn.show === 'function') {
                    entryBtn.show();
                }
            } catch (_) {}
        }
        """
    // 초기화된 Eruda의 엔트리 버튼을 다시 표시하는 JavaScript입니다.
    static let erudaEnsureEntryVisibleScript = """
        if (typeof eruda !== 'undefined') {
            try {
                const entryBtn = eruda.get && eruda.get('entryBtn');
                if (entryBtn && typeof entryBtn.show === 'function') {
                    entryBtn.show();
                }
            } catch (_) {}
        }
        """
    // Eruda 번들 스크립트는 최초 1회만 읽고 재사용합니다.
    private static let cachedErudaScript: String? = {
        guard let erudaURL = Bundle.main.url(forResource: "eruda.min", withExtension: "js"),
              let script = try? String(contentsOf: erudaURL, encoding: .utf8) else {
            return nil
        }
        return script
    }()

    private weak var webView: WKWebView?
    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?

    var isAttached: Bool {
        webView != nil
    }

    func attach(to webView: WKWebView) {
        self.webView = webView

        // Initial state
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        currentURL = webView.url

        // Observe changes (use .initial to get immediate value, .new for updates)
        canGoBackObservation = webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.canGoBack = webView.canGoBack
            }
        }
        canGoForwardObservation = webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.canGoForward = webView.canGoForward
            }
        }
        urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.currentURL = webView.url
                self?.networkManager.pageURL = webView.url
            }
        }
    }

    func detach() {
        recorder.stopRecording()
        canGoBackObservation?.invalidate()
        canGoForwardObservation?.invalidate()
        urlObservation?.invalidate()
        canGoBackObservation = nil
        canGoForwardObservation = nil
        urlObservation = nil
        webView = nil
        reloadPreparationHandler = nil
        canGoBack = false
        canGoForward = false
        currentURL = nil
    }

    /// 수동 새로고침 직전에 실행할 coordinator 콜백을 등록합니다.
    func setReloadPreparationHandler(_ handler: (() -> Void)?) {
        reloadPreparationHandler = handler
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    /// 최초 URL로 돌아갈 수 있는지 여부
    var canGoToInitialURL: Bool {
        guard let initialURL else { return false }
        return currentURL != initialURL
    }

    /// 최초 URL 설정 (웹뷰 최초 로드 시 호출)
    func setInitialURL(_ url: URL) {
        initialURL = url
    }

    /// 최초 URL 초기화 (홈으로 돌아갈 때)
    func clearInitialURL() {
        initialURL = nil
    }

    /// 최초 입력된 URL로 이동
    func goToInitialURL() {
        guard let initialURL else { return }
        webView?.load(URLRequest(url: initialURL))
    }

    func reload() {
        // AppBar 새로고침에서도 coordinator가 동일한 reload 전략을 적용하도록 보장합니다.
        reloadPreparationHandler?()
        webView?.reload()
    }

    func applyEmulation(configScript: String) {
        guard let webView else { return }
        let controller = webView.configuration.userContentController
        // WebKit returns a live NSArray; materialize it before clearing the controller.
        // swiftlint:disable:next array_init
        let scripts = controller.userScripts.map { $0 }
        controller.removeAllUserScripts()
        var replaced = false
        for script in scripts {
            if script.source.hasPrefix(WebViewScripts.emulationConfigMarker) {
                controller.addUserScript(WKUserScript(source: configScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
                replaced = true
            } else {
                controller.addUserScript(script)
            }
        }
        if !replaced {
            controller.addUserScript(WKUserScript(source: configScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
            controller.addUserScript(WKUserScript(source: WebViewScripts.emulationBootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        reload()
    }

    func stopLoading() {
        webView?.stopLoading()
    }

    /// Load a new URL in the same WebView instance
    func loadURL(_ urlString: String) {
        guard let webView else { return }

        // Normalize URL (http for local/private hosts, https otherwise)
        let normalized = URLValidator.normalizeURL(urlString)

        guard let url = URL(string: normalized) else { return }
        webView.load(URLRequest(url: url))
    }

    /// Evaluate JavaScript on the attached WebView
    @MainActor
    func evaluateJavaScript(_ script: String) async -> Any? {
        guard let webView else { return nil }
        return try? await webView.evaluateJavaScript(script)
    }

    /// Evaluate async JavaScript (supports Promises)
    @MainActor
    func callAsyncJavaScript(_ script: String) async -> Any? {
        guard let webView else { return nil }
        return try? await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
    }

    /// Check photo library permission without requesting
    func checkPhotoLibraryPermission() -> PhotoPermissionStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized, .limited:
            return .authorized
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .authorized
        }
    }

    /// Request photo library permission
    func requestPhotoLibraryPermission() async -> Bool {
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return newStatus == .authorized || newStatus == .limited
    }

    /// Take a screenshot of the WebView and save to Photos
    /// Assumes permission is already granted (call checkPhotoLibraryPermission first)
    @MainActor
    func takeScreenshot() async -> ScreenshotResult {
        guard let webView else { return .failed }

        // Double-check permission (in case called directly)
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return .permissionDenied
        }

        // Take snapshot
        guard let image = await captureSnapshot(from: webView) else {
            return .failed
        }

        // Convert to opaque image (removes unnecessary alpha channel)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let opaqueImage = renderer.image { _ in
            image.draw(at: .zero)
        }

        // Save to Photos
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: opaqueImage)
            }
            return .success
        } catch {
            return .failed
        }
    }

    @MainActor
    private func captureSnapshot(from webView: WKWebView) async -> UIImage? {
        await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: nil) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Set a cookie using native WKHTTPCookieStore
    func setCookie(_ cookie: HTTPCookie) async {
        guard let webView else { return }
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        await cookieStore.setCookie(cookie)
    }

    /// Delete a specific cookie by name/domain/path using native WKHTTPCookieStore
    func deleteCookie(name: String, domain: String?, path: String?) async {
        guard let webView else { return }
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = await cookieStore.allCookies()
        for cookie in cookies where cookie.name == name {
            // Narrow by domain/path when provided to avoid over-deleting.
            if let domain, cookie.domain.caseInsensitiveCompare(domain) != .orderedSame {
                continue
            }
            if let path, cookie.path != path {
                continue
            }
            await cookieStore.deleteCookie(cookie)
        }
    }

    /// Delete cookies for a specific domain using native WKHTTPCookieStore
    func deleteCookies(forDomain domain: String) async {
        guard let webView else { return }
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = await cookieStore.allCookies()
        let host = domain.lowercased()

        for cookie in cookies {
            let cookieDomain = cookie.domain.lowercased()
            let matches: Bool

            if cookieDomain.hasPrefix(".") {
                let trimmed = String(cookieDomain.dropFirst())
                matches = host == trimmed || host.hasSuffix(".\(trimmed)")
            } else {
                matches = host == cookieDomain
            }

            if matches {
                await cookieStore.deleteCookie(cookie)
            }
        }
    }

    /// Delete all cookies using native WKHTTPCookieStore
    func deleteAllCookies() async {
        guard let webView else { return }
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = await cookieStore.allCookies()
        for cookie in cookies {
            await cookieStore.deleteCookie(cookie)
        }
    }

    /// Get all cookies with full metadata using native WKHTTPCookieStore
    func getAllCookies() async -> [HTTPCookie] {
        guard let webView else { return [] }
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        return await cookieStore.allCookies()
    }

    // MARK: - Eruda Console

    // 현재 설정값 기준으로 Eruda 상태를 페이지에 동기화합니다.
    func syncErudaWithSettings(forceInit: Bool = false) async {
        guard webView != nil else { return }
        let isEnabled = UserDefaults.standard.bool(forKey: Self.erudaModeKey)
        if isEnabled {
            await injectEruda(forceInit: forceInit)
        } else {
            await destroyEruda()
        }
    }

    /// Inject Eruda console into the current page
    /// Eruda is loaded from bundled JS file to bypass CSP restrictions
    func injectEruda(forceInit: Bool = false) async {
        guard webView != nil else { return }

        // 현재 페이지에 Eruda 스크립트가 이미 로드됐는지 확인합니다.
        var erudaLoaded = await evaluateJavaScript(Self.erudaLoadedCheckScript) as? Bool ?? false

        // 스크립트가 없으면 번들 스크립트를 주입합니다.
        if !erudaLoaded {
            guard let erudaScript = erudaBundleScript() else { return }
            _ = await evaluateJavaScript(erudaScript)
            erudaLoaded = await evaluateJavaScript(Self.erudaLoadedCheckScript) as? Bool ?? false
            guard erudaLoaded else { return }
        }

        // 새로고침 경로에서는 강제 재초기화로 엔트리 버튼 누락을 복구합니다.
        if forceInit {
            _ = await evaluateJavaScript(Self.erudaReinitializeScript)
            return
        }

        // 엔트리 버튼이 없으면 init을 다시 수행하고, 있으면 표시 상태만 복구합니다.
        let hasEntryButton = await evaluateJavaScript(Self.erudaEntryButtonCheckScript) as? Bool ?? false
        if hasEntryButton {
            _ = await evaluateJavaScript(Self.erudaEnsureEntryVisibleScript)
        } else {
            _ = await evaluateJavaScript(Self.erudaInitializeScript)
        }
    }

    /// Hide Eruda console if loaded
    func hideEruda() async {
        _ = await evaluateJavaScript("if (typeof eruda !== 'undefined') eruda.hide();")
    }

    /// Destroy Eruda console completely
    func destroyEruda() async {
        _ = await evaluateJavaScript("if (typeof eruda !== 'undefined') eruda.destroy();")
    }

    // 테스트에서 Eruda 번들 스크립트를 대체할 수 있도록 분리합니다.
    func erudaBundleScript() -> String? {
        Self.cachedErudaScript
    }
}
