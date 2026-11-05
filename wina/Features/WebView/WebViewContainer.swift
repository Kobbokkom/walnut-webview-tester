//
//  WebViewContainer.swift
//  wina
//
//  WebView container with WKWebView and SafariViewController support.
//

import SwiftUI
import WebKit
import SafariServices
import os

// MARK: - WebView Container

struct WebViewContainer: View {
    let urlString: String
    let useSafari: Bool
    @Binding var webViewID: UUID
    let navigator: WebViewNavigator?

    // Loading State
    @State private var isLoading: Bool = true

    // Core Settings
    @AppStorage("allowsContentJavaScript") private var allowsContentJavaScript: Bool = true
    @AppStorage("allowZoom") private var allowZoom: Bool = false
    @AppStorage("minimumFontSize") private var minimumFontSize: Double = 0

    // Media Settings
    @AppStorage("mediaAutoplay") private var mediaAutoplay: Bool = false
    @AppStorage("inlineMediaPlayback") private var inlineMediaPlayback: Bool = true
    @AppStorage("allowsAirPlay") private var allowsAirPlay: Bool = true
    @AppStorage("allowsPictureInPicture") private var allowsPictureInPicture: Bool = true

    // Navigation & Gestures
    @AppStorage("allowsBackForwardGestures") private var allowsBackForwardGestures: Bool = false
    @AppStorage("allowsLinkPreview") private var allowsLinkPreview: Bool = true

    // Content Settings
    @AppStorage("suppressesIncrementalRendering") private var suppressesIncrementalRendering: Bool = false
    @AppStorage("javaScriptCanOpenWindows") private var javaScriptCanOpenWindows: Bool = false
    @AppStorage("fraudulentWebsiteWarning") private var fraudulentWebsiteWarning: Bool = true
    @AppStorage("textInteractionEnabled") private var textInteractionEnabled: Bool = true
    @AppStorage("elementFullscreenEnabled") private var elementFullscreenEnabled: Bool = false

    // Data Detectors
    @AppStorage("detectPhoneNumbers") private var detectPhoneNumbers: Bool = false
    @AppStorage("detectLinks") private var detectLinks: Bool = false
    @AppStorage("detectAddresses") private var detectAddresses: Bool = false
    @AppStorage("detectCalendarEvents") private var detectCalendarEvents: Bool = false

    // Privacy & Security
    @AppStorage("privateBrowsing") private var privateBrowsing: Bool = false
    @AppStorage("upgradeToHTTPS") private var upgradeToHTTPS: Bool = true

    // Content Mode
    @AppStorage("preferredContentMode") private var preferredContentMode: Int = 0

    // User Agent
    @AppStorage("customUserAgent") private var customUserAgent: String = ""

    // WKWebView Size
    @AppStorage("webViewWidthRatio") private var webViewWidthRatio: Double = 1.0
    @AppStorage("webViewHeightRatio") private var webViewHeightRatio: Double = 0.82

    // SafariVC Size (separate settings)
    @AppStorage("safariWidthRatio") private var safariWidthRatio: Double = 1.0
    @AppStorage("safariHeightRatio") private var safariHeightRatio: Double = 0.82

    private var currentWidthRatio: Double {
        useSafari ? safariWidthRatio : webViewWidthRatio
    }

    private var currentHeightRatio: Double {
        useSafari ? safariHeightRatio : webViewHeightRatio
    }

    private var isFullSize: Bool {
        currentWidthRatio >= 0.99 && currentHeightRatio >= 0.99
    }

    var body: some View {
        GeometryReader { geometry in
            let webViewWidth = geometry.size.width * currentWidthRatio
            let webViewHeight = geometry.size.height * currentHeightRatio

            ZStack {
                // Background (only shown when size is less than 100%)
                if !isFullSize {
                    Color(uiColor: .systemGroupedBackground)
                        .ignoresSafeArea()

                    // Checkerboard pattern (to indicate transparent area)
                    CheckerboardPattern()
                        .ignoresSafeArea()
                }

                // WebView
                if useSafari {
                    SafariWebView(urlString: normalizedURL)
                        .id(webViewID)
                        .frame(width: webViewWidth, height: webViewHeight)
                        .clipShape(RoundedRectangle(cornerRadius: isFullSize ? 0 : 12))
                        .shadow(color: .black.opacity(isFullSize ? 0 : 0.15), radius: 8, y: 2)
                        // Offset up to balance gap between top bar and bottom bar (only in non-fullscreen mode)
                        // Uses safe area ratio with fallback for devices without safe area (e.g. SE)
                        .offset(y: isFullSize ? 0 : -10)
                } else {
                    WKWebViewRepresentable(
                        urlString: normalizedURL,
                        configuration: webViewConfiguration,
                        isLoading: $isLoading,
                        navigator: navigator
                    )
                    .id(webViewID)
                    .frame(width: webViewWidth, height: webViewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: isFullSize ? 0 : 12))
                    .shadow(color: .black.opacity(isFullSize ? 0 : 0.15), radius: 8, y: 2)
                    // Offset up to balance gap between top bar and bottom bar (only in non-fullscreen mode)
                    // Uses safe area ratio with fallback for devices without safe area (e.g. SE)
                    .offset(y: isFullSize ? 0 : -10)
                    .overlay(alignment: .top) {
                        // Subtle top loading bar
                        if isLoading {
                            LoadingProgressBar()
                        }
                    }
                    .overlay {
                        // Screenshot flash effect
                        if navigator?.showScreenshotFlash == true {
                            Color.white
                                .opacity(0.7)
                                .clipShape(RoundedRectangle(cornerRadius: isFullSize ? 0 : 12))
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        // Screenshot saved toast
                        if navigator?.showScreenshotSavedToast == true {
                            CopiedFeedbackToast(message: "Saved to Photos")
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
    }

    private var normalizedURL: String {
        URLValidator.normalizeURL(urlString)
    }

    private var webViewConfiguration: WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()

        // Core
        prefs.allowsContentJavaScript = allowsContentJavaScript
        config.defaultWebpagePreferences = prefs
        config.ignoresViewportScaleLimits = allowZoom
        config.preferences.javaScriptCanOpenWindowsAutomatically = javaScriptCanOpenWindows
        config.preferences.isFraudulentWebsiteWarningEnabled = fraudulentWebsiteWarning
        config.preferences.minimumFontSize = CGFloat(SettingsFormatter.validMinimumFontSize(minimumFontSize))

        // Media
        if mediaAutoplay {
            config.mediaTypesRequiringUserActionForPlayback = []
        } else {
            config.mediaTypesRequiringUserActionForPlayback = .all
        }
        config.allowsInlineMediaPlayback = inlineMediaPlayback
        config.allowsAirPlayForMediaPlayback = allowsAirPlay
        config.allowsPictureInPictureMediaPlayback = allowsPictureInPicture

        // Content Mode
        switch preferredContentMode {
        case 1:
            prefs.preferredContentMode = .mobile
        case 2:
            prefs.preferredContentMode = .desktop
        default:
            prefs.preferredContentMode = .recommended
        }

        // Data Detectors
        var dataDetectorTypes: WKDataDetectorTypes = []
        if detectPhoneNumbers { dataDetectorTypes.insert(.phoneNumber) }
        if detectLinks { dataDetectorTypes.insert(.link) }
        if detectAddresses { dataDetectorTypes.insert(.address) }
        if detectCalendarEvents { dataDetectorTypes.insert(.calendarEvent) }
        config.dataDetectorTypes = dataDetectorTypes

        // Privacy
        if privateBrowsing {
            config.websiteDataStore = .nonPersistent()
        }
        config.upgradeKnownHostsToHTTPS = upgradeToHTTPS

        // Suppresses Incremental Rendering
        config.suppressesIncrementalRendering = suppressesIncrementalRendering

        return config
    }
}

// MARK: - WKWebView Representable

struct WKWebViewRepresentable: UIViewRepresentable {
    let urlString: String
    let configuration: WKWebViewConfiguration
    @Binding var isLoading: Bool
    let navigator: WebViewNavigator?

    // Navigation & Gestures
    @AppStorage("allowsBackForwardGestures") private var allowsBackForwardGestures: Bool = false
    @AppStorage("allowsLinkPreview") private var allowsLinkPreview: Bool = true
    @AppStorage("textInteractionEnabled") private var textInteractionEnabled: Bool = true

    // Display
    @AppStorage("pageZoom") private var pageZoom: Double = 1.0
    @AppStorage("underPageBackgroundColor") private var underPageBackgroundColorHex: String = ""

    // Features
    @AppStorage("findInteractionEnabled") private var findInteractionEnabled: Bool = false

    // User Agent
    @AppStorage("customUserAgent") private var customUserAgent: String = ""

    // Emulation
    @AppStorage("emulationColorScheme") private var emulationColorScheme: String = "system"
    @AppStorage("emulationReducedMotion") private var emulationReducedMotion: Bool = false
    @AppStorage("emulationHighContrast") private var emulationHighContrast: Bool = false
    @AppStorage("emulationReducedTransparency") private var emulationReducedTransparency: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isLoading: $isLoading,
            navigator: navigator,
            preloadProfile: PreloadProfileStore.activeProfile()
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        // Add console and network hook scripts and message handlers to configuration
        let userContentController = configuration.userContentController
        let preloadProfile = context.coordinator.preloadProfile

        // User preload bridge channels
        for channelName in preloadProfile.enabledBridgeChannelNames {
            userContentController.add(context.coordinator, name: channelName)
        }

        let preloadScriptSource = PreloadScriptBuilder.bootstrapScript(for: preloadProfile)
        if !preloadScriptSource.isEmpty {
            let preloadScript = WKUserScript(
                source: preloadScriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            userContentController.addUserScript(preloadScript)
        }

        for customScript in PreloadScriptBuilder.customScripts(for: preloadProfile) {
            let script = WKUserScript(
                source: customScript.source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: customScript.forMainFrameOnly
            )
            userContentController.addUserScript(script)
        }

        // Console hook
        userContentController.add(context.coordinator, name: "consoleLog")
        let consoleScript = WKUserScript(
            source: WebViewScripts.consoleHook,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(consoleScript)

        // Network hook
        userContentController.add(context.coordinator, name: "networkRequest")
        let networkScript = WKUserScript(
            source: WebViewScripts.networkHook,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(networkScript)

        // Resource timing hook
        userContentController.add(context.coordinator, name: "resourceTiming")
        let resourceScript = WKUserScript(
            source: WebViewScripts.resourceTimingHook,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(resourceScript)

        // Performance observer hook (for LCP, CLS)
        let performanceScript = WKUserScript(
            source: WebViewScripts.performanceObserver,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(performanceScript)

        // Emulation: config script first, then bootstrap (order matters)
        let emulationConfigScript = WKUserScript(
            source: WebViewScripts.emulationConfigScript(
                colorScheme: emulationColorScheme,
                reducedMotion: emulationReducedMotion,
                highContrast: emulationHighContrast,
                reducedTransparency: emulationReducedTransparency
            ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(emulationConfigScript)

        let emulationBootstrapScript = WKUserScript(
            source: WebViewScripts.emulationBootstrap,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(emulationBootstrapScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = allowsBackForwardGestures
        webView.allowsLinkPreview = allowsLinkPreview

        webView.isInspectable = true

        webView.configuration.preferences.isTextInteractionEnabled = textInteractionEnabled

        // Page zoom
        webView.pageZoom = pageZoom

        // Under page background color
        if let color = UIColor(hex: underPageBackgroundColorHex) {
            webView.underPageBackgroundColor = color
        }

        // Find interaction
        webView.isFindInteractionEnabled = findInteractionEnabled

        if !customUserAgent.isEmpty {
            webView.customUserAgent = customUserAgent
        }

        // Set up KVO for loading progress
        context.coordinator.observeWebView(webView)

        // Attach navigator for external control
        context.coordinator.navigator?.attach(to: webView)
        // AppBar refresh 경로에서도 coordinator reload 전략이 동작하도록 연결합니다.
        context.coordinator.navigator?.setReloadPreparationHandler { [weak coordinator = context.coordinator] in
            coordinator?.prepareForManualReloadRequest()
        }

        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            PreloadCookieApplicator.apply(
                profile: preloadProfile,
                url: url,
                cookieStore: webView.configuration.websiteDataStore.httpCookieStore
            ) {
                webView.load(request)
            }
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Dynamic properties - can be updated without recreating WebView
        webView.allowsBackForwardNavigationGestures = allowsBackForwardGestures
        webView.allowsLinkPreview = allowsLinkPreview
        webView.configuration.preferences.isTextInteractionEnabled = textInteractionEnabled

        // Page zoom
        webView.pageZoom = pageZoom

        // Under page background color
        if let color = UIColor(hex: underPageBackgroundColorHex) {
            webView.underPageBackgroundColor = color
        } else {
            webView.underPageBackgroundColor = nil
        }

        // Find interaction
        webView.isFindInteractionEnabled = findInteractionEnabled

        if !customUserAgent.isEmpty {
            webView.customUserAgent = customUserAgent
        } else {
            webView.customUserAgent = nil
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // Explicit cleanup before deallocation
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        // Remove message handlers to prevent retain cycle
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "consoleLog")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "networkRequest")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "resourceTiming")
        for channelName in coordinator.preloadProfile.enabledBridgeChannelNames {
            uiView.configuration.userContentController.removeScriptMessageHandler(forName: channelName)
        }
        coordinator.invalidateObservation()
        coordinator.navigator?.detach()
    }

    // MARK: - Coordinator

    typealias Coordinator = WKWebViewCoordinator
}

// MARK: - Loading Progress Bar

private struct LoadingProgressBar: View {
    @State private var animationOffset: CGFloat = -1

    var body: some View {
        GeometryReader { geometry in
            let barWidth = geometry.size.width * 0.3

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .accentColor.opacity(0.8), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: barWidth, height: 3)
                .offset(x: animationOffset * (geometry.size.width + barWidth) - barWidth / 2)
        }
        .frame(height: 3)
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                animationOffset = 1
            }
        }
    }
}

// MARK: - Checkerboard Pattern

private struct CheckerboardPattern: View {
    let squareSize: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            let rows = Int(ceil(size.height / squareSize))
            let cols = Int(ceil(size.width / squareSize))

            for row in 0..<rows {
                for col in 0..<cols where (row + col).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(col) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(Path(rect), with: .color(.secondary.opacity(0.08)))
                }
            }
        }
    }
}

// MARK: - Safari WebView

struct SafariWebView: UIViewControllerRepresentable {
    let urlString: String

    // Configuration settings (require recreation)
    @AppStorage("safariEntersReaderIfAvailable") var entersReaderIfAvailable = false
    @AppStorage("safariBarCollapsingEnabled") var barCollapsingEnabled = true

    // Runtime-changeable settings
    @AppStorage("safariDismissButtonStyle") var dismissButtonStyle = 0
    @AppStorage("safariControlTintColorHex") var controlTintColorHex = ""
    @AppStorage("safariBarTintColorHex") var barTintColorHex = ""

    func makeUIViewController(context: Context) -> SFSafariViewController {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return SFSafariViewController(url: URL(string: "https://example.com")!)
        }
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = entersReaderIfAvailable
        config.barCollapsingEnabled = barCollapsingEnabled
        let vc = SFSafariViewController(url: url, configuration: config)

        // Apply runtime settings
        applyRuntimeSettings(to: vc)

        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // Only runtime-changeable properties can be updated
        applyRuntimeSettings(to: uiViewController)
    }

    private func applyRuntimeSettings(to vc: SFSafariViewController) {
        // Dismiss button style
        switch dismissButtonStyle {
        case 1: vc.dismissButtonStyle = .close
        case 2: vc.dismissButtonStyle = .cancel
        default: vc.dismissButtonStyle = .done
        }

        if #unavailable(iOS 26.0) {
            if let color = UIColor(hex: controlTintColorHex) {
                vc.preferredControlTintColor = color
            }
            if let color = UIColor(hex: barTintColorHex) {
                vc.preferredBarTintColor = color
            }
        }
    }
}

#Preview {
    @Previewable @State var id = UUID()
    WebViewContainer(urlString: "https://apple.com", useSafari: false, webViewID: $id, navigator: nil)
}
