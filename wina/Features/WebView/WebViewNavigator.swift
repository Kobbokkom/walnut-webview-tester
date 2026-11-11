//
//  WebViewNavigator.swift
//  wina
//
//  WebView navigation controller with KVO observation.
//

import Observation
import Photos
import UIKit
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
    private(set) var documentID = UUID()
    /// 최초 입력된 URL (네비게이션 시작점)
    private(set) var initialURL: URL?
    var showScreenshotFlash: Bool = false
    var showScreenshotSavedToast: Bool = false
    let consoleManager = ConsoleManager()
    let networkManager = NetworkManager()
    let performanceManager = PerformanceManager()
    let resourceManager = ResourceManager()
    let accessibilityManager = AccessibilityManager()
    let snippetsManager = SnippetsManager()
    let preloadBridgeLogManager = PreloadBridgeLogManager()
    let recorder = WebViewRecorder()
    let agentNavigation = AgentNavigation()
    var agentLogSettings = AgentLogSettings()
    @ObservationIgnored var agentInspectorGrant: AgentInspectorGrant?

    func setAgentDocument(_ documentID: UUID?) {
        consoleManager.agentDocumentID = documentID
        networkManager.agentDocumentID = documentID
        resourceManager.agentDocumentID = documentID
    }

    var agentIsLoading: Bool { webView?.isLoading ?? false }

    var agentEffectiveUserAgent: String? { webView?.customUserAgent }

    var agentWebViewState: [String: Any]? {
        guard let webView else { return nil }
        return [
            "pageZoom": webView.pageZoom,
            "widthPoints": webView.bounds.width,
            "heightPoints": webView.bounds.height,
            "privateBrowsing": !webView.configuration.websiteDataStore.isPersistent,
            "allowsBackForwardGestures": webView.allowsBackForwardNavigationGestures,
            "allowsLinkPreview": webView.allowsLinkPreview,
            "textInteractionEnabled": webView.configuration.preferences.isTextInteractionEnabled,
            "findInteractionEnabled": webView.isFindInteractionEnabled
        ]
    }

    func applyAgentUserAgent() {
        let value = AgentBrowserSettings.shared.value(
            "customUserAgent", fallback: UserDefaults.standard.string(forKey: "customUserAgent") ?? ""
        )
        webView?.customUserAgent = value.isEmpty ? nil : value
    }

    func agentScreenshot() async -> UIImage? {
        guard let webView else { return nil }
        return await captureSnapshot(from: webView)
    }

    func showAgentPointer(x: Double, y: Double) {
        guard let webView, (0...1).contains(x), (0...1).contains(y) else { return }
        let pointer: AgentPointerView
        if let agentPointerView {
            pointer = agentPointerView
        } else {
            pointer = AgentPointerView(frame: webView.bounds)
            pointer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            pointer.clipsToBounds = true
            pointer.isUserInteractionEnabled = false
            pointer.accessibilityElementsHidden = true
            webView.addSubview(pointer)
            agentPointerView = pointer
        }
        pointer.position = CGPoint(x: x, y: y)
    }

    func hideAgentPointer() {
        agentPointerView?.removeFromSuperview()
        agentPointerView = nil
    }

    @ObservationIgnored
    private var agentPointerView: AgentPointerView?

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

    var attachedPageURL: URL? { webView?.url }

    func attach(to webView: WKWebView) {
        self.webView = webView
        documentDidChange(in: webView)

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

    func documentDidChange(in webView: WKWebView) {
        guard self.webView === webView else { return }
        hideAgentPointer()
        agentInspectorGrant = nil
        documentID = UUID()
        setAgentDocument(agentTrackingEnabled ? documentID : nil)
        performanceManager.clear()
    }

    var agentTrackingEnabled = false {
        didSet { setAgentDocument(agentTrackingEnabled ? documentID : nil) }
    }

    func detach(from previousWebView: WKWebView? = nil) {
        if let previousWebView, webView !== previousWebView { return }
        hideAgentPointer()
        AgentEngineInspection.revoke(self)
        setAgentDocument(nil)
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
        documentID = UUID()
        performanceManager.clear()
    }

    /// 수동 새로고침 직전에 실행할 coordinator 콜백을 등록합니다.
    func setReloadPreparationHandler(_ handler: (() -> Void)?) {
        reloadPreparationHandler = handler
    }

    @discardableResult
    func goBack() -> WKNavigation? {
        webView?.goBack()
    }

    @discardableResult
    func goForward() -> WKNavigation? {
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
    @discardableResult
    func goToInitialURL() -> WKNavigation? {
        guard let initialURL else { return nil }
        return webView?.load(URLRequest(url: initialURL))
    }

    @discardableResult
    func reload() -> WKNavigation? {
        // AppBar 새로고침에서도 coordinator가 동일한 reload 전략을 적용하도록 보장합니다.
        reloadPreparationHandler?()
        return webView?.reload()
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
    @discardableResult
    func loadURL(_ urlString: String) -> WKNavigation? {
        guard let webView else { return nil }

        // Normalize URL (http for local/private hosts, https otherwise)
        let normalized = URLValidator.normalizeURL(urlString)

        guard let url = URL(string: normalized) else { return nil }
        return webView.load(URLRequest(url: url))
    }

    /// Evaluate JavaScript on the attached WebView
    @MainActor
    func evaluateJavaScript(_ script: String) async -> Any? {
        try? await evaluateJavaScriptReportingErrors(script)
    }

    @MainActor
    func evaluateJavaScriptReportingErrors(_ script: String, contentWorld: WKContentWorld = .page) async throws -> Any? {
        guard let webView else { throw AgentError("The WKWebView is disconnected.") }
        return try await webView.evaluateJavaScript(script, contentWorld: contentWorld)
    }

    /// Evaluate async JavaScript (supports Promises)
    @MainActor
    func callAsyncJavaScript(_ script: String) async -> Any? {
        try? await callAsyncJavaScriptReportingErrors(script)
    }

    @MainActor
    func callAsyncJavaScriptReportingErrors(_ script: String, contentWorld: WKContentWorld = .page) async throws -> Any? {
        guard let webView else { throw AgentError("The WKWebView is disconnected.") }
        return try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: contentWorld
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
        guard !webView.bounds.isEmpty else { return nil }
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        let snapshot: UIImage? = await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, _ in
                continuation.resume(returning: image)
            }
        }
        if let snapshot, Self.hasVisiblePixels(snapshot) { return snapshot }
        guard webView.window != nil, !Task.isCancelled else { return nil }
        var rendered = false
        let bounds = CGRect(origin: .zero, size: webView.bounds.size)
        let fallback = UIGraphicsImageRenderer(size: bounds.size).image { _ in
            rendered = webView.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        return rendered && Self.hasVisiblePixels(fallback) ? fallback : nil
    }

    static func hasVisiblePixels(_ image: UIImage) -> Bool {
        guard let pixels = image.cgImage else { return false }
        switch pixels.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return true
        default: break
        }
        let rgba = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let mask = CGContext(data: nil, width: pixels.width, height: pixels.height,
                                   bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: rgba) else { return false }
        let bounds = CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
        mask.clear(bounds)
        mask.draw(pixels, in: bounds)
        guard let bytes = mask.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        for row in 0..<mask.height {
            let start = row * mask.bytesPerRow
            for offset in stride(from: start + 3, to: start + mask.width * 4, by: 4) where bytes[offset] > 0 {
                return true
            }
        }
        return false
    }

    var attachedCookieStore: (any StorageCookieStore)? {
        webView?.configuration.websiteDataStore.httpCookieStore
    }

    // MARK: - Eruda Console

    // 현재 설정값 기준으로 Eruda 상태를 페이지에 동기화합니다.
    func syncErudaWithSettings(forceInit: Bool = false) async {
        guard webView != nil else { return }
        let saved = UserDefaults.standard.bool(forKey: Self.erudaModeKey)
        let isEnabled = agentTrackingEnabled ? AgentBrowserSettings.shared.value(Self.erudaModeKey, fallback: saved) : saved
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

private final class AgentPointerView: UIView {
    var position: CGPoint = .zero {
        didSet { setNeedsLayout() }
    }

    private lazy var cursor: CAShapeLayer = {
        let outline = UIBezierPath()
        outline.move(to: .zero)
        outline.addLine(to: CGPoint(x: 0, y: 17))
        outline.addLine(to: CGPoint(x: 5, y: 12))
        outline.addLine(to: CGPoint(x: 8, y: 18))
        outline.addLine(to: CGPoint(x: 11, y: 17))
        outline.addLine(to: CGPoint(x: 8, y: 11))
        outline.addLine(to: CGPoint(x: 15, y: 11))
        outline.close()
        let shape = CAShapeLayer()
        shape.anchorPoint = .zero
        shape.bounds.size = CGSize(width: 16, height: 19)
        shape.path = outline.cgPath
        shape.fillColor = UIColor.white.cgColor
        shape.strokeColor = UIColor.black.cgColor
        shape.lineJoin = .round
        layer.addSublayer(shape)
        return shape
    }()

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursor.position = CGPoint(x: bounds.width * position.x, y: bounds.height * position.y)
        CATransaction.commit()
    }
}
