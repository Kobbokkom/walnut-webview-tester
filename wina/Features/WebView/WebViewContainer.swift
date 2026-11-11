//
//  WebViewContainer.swift
//  wina
//
//  WKWebView container.
//

import SwiftUI
import WebKit
import os

// MARK: - WebView Container

struct WebViewContainer: View {
    @Environment(\.agentBrowserSettings) private var agentSettings
    let urlString: String
    @Binding var webViewID: UUID
    let navigator: WebViewNavigator?

    // Loading State
    @State private var isLoading: Bool = true

    // Core Settings
    @AppStorage("allowsContentJavaScript") private var storedAllowsContentJavaScript = true
    private var allowsContentJavaScript: Bool {
        agentSettings?.value("allowsContentJavaScript", fallback: storedAllowsContentJavaScript) ?? storedAllowsContentJavaScript
    }
    @AppStorage("allowZoom") private var storedAllowZoom = false
    private var allowZoom: Bool {
        agentSettings?.value("allowZoom", fallback: storedAllowZoom) ?? storedAllowZoom
    }
    @AppStorage("minimumFontSize") private var storedMinimumFontSize = 0.0
    private var minimumFontSize: Double {
        agentSettings?.value("minimumFontSize", fallback: storedMinimumFontSize) ?? storedMinimumFontSize
    }

    // Media Settings
    @AppStorage("mediaAutoplay") private var storedMediaAutoplay = false
    private var mediaAutoplay: Bool {
        agentSettings?.value("mediaAutoplay", fallback: storedMediaAutoplay) ?? storedMediaAutoplay
    }
    @AppStorage("inlineMediaPlayback") private var storedInlineMediaPlayback = true
    private var inlineMediaPlayback: Bool {
        agentSettings?.value("inlineMediaPlayback", fallback: storedInlineMediaPlayback) ?? storedInlineMediaPlayback
    }
    @AppStorage("allowsAirPlay") private var storedAllowsAirPlay = true
    private var allowsAirPlay: Bool {
        agentSettings?.value("allowsAirPlay", fallback: storedAllowsAirPlay) ?? storedAllowsAirPlay
    }
    @AppStorage("allowsPictureInPicture") private var storedAllowsPictureInPicture = true
    private var allowsPictureInPicture: Bool {
        agentSettings?.value("allowsPictureInPicture", fallback: storedAllowsPictureInPicture) ?? storedAllowsPictureInPicture
    }

    // Navigation & Gestures
    @AppStorage("allowsBackForwardGestures") private var storedAllowsBackForwardGestures = false
    private var allowsBackForwardGestures: Bool {
        agentSettings?.value("allowsBackForwardGestures", fallback: storedAllowsBackForwardGestures) ?? storedAllowsBackForwardGestures
    }
    @AppStorage("allowsLinkPreview") private var storedAllowsLinkPreview = true
    private var allowsLinkPreview: Bool {
        agentSettings?.value("allowsLinkPreview", fallback: storedAllowsLinkPreview) ?? storedAllowsLinkPreview
    }

    // Content Settings
    @AppStorage("suppressesIncrementalRendering") private var storedSuppressesIncrementalRendering = false
    private var suppressesIncrementalRendering: Bool {
        agentSettings?.value("suppressesIncrementalRendering", fallback: storedSuppressesIncrementalRendering) ?? storedSuppressesIncrementalRendering
    }
    @AppStorage("javaScriptCanOpenWindows") private var storedJavaScriptCanOpenWindows = false
    private var javaScriptCanOpenWindows: Bool {
        agentSettings?.value("javaScriptCanOpenWindows", fallback: storedJavaScriptCanOpenWindows) ?? storedJavaScriptCanOpenWindows
    }
    @AppStorage("fraudulentWebsiteWarning") private var storedFraudulentWebsiteWarning = true
    private var fraudulentWebsiteWarning: Bool {
        agentSettings?.value("fraudulentWebsiteWarning", fallback: storedFraudulentWebsiteWarning) ?? storedFraudulentWebsiteWarning
    }
    @AppStorage("textInteractionEnabled") private var storedTextInteractionEnabled = true
    private var textInteractionEnabled: Bool {
        agentSettings?.value("textInteractionEnabled", fallback: storedTextInteractionEnabled) ?? storedTextInteractionEnabled
    }
    @AppStorage("elementFullscreenEnabled") private var storedElementFullscreenEnabled = false
    private var elementFullscreenEnabled: Bool {
        agentSettings?.value("elementFullscreenEnabled", fallback: storedElementFullscreenEnabled) ?? storedElementFullscreenEnabled
    }

    // Data Detectors
    @AppStorage("detectPhoneNumbers") private var storedDetectPhoneNumbers = false
    private var detectPhoneNumbers: Bool {
        agentSettings?.value("detectPhoneNumbers", fallback: storedDetectPhoneNumbers) ?? storedDetectPhoneNumbers
    }
    @AppStorage("detectLinks") private var storedDetectLinks = false
    private var detectLinks: Bool {
        agentSettings?.value("detectLinks", fallback: storedDetectLinks) ?? storedDetectLinks
    }
    @AppStorage("detectAddresses") private var storedDetectAddresses = false
    private var detectAddresses: Bool {
        agentSettings?.value("detectAddresses", fallback: storedDetectAddresses) ?? storedDetectAddresses
    }
    @AppStorage("detectCalendarEvents") private var storedDetectCalendarEvents = false
    private var detectCalendarEvents: Bool {
        agentSettings?.value("detectCalendarEvents", fallback: storedDetectCalendarEvents) ?? storedDetectCalendarEvents
    }

    // Privacy & Security
    @AppStorage("privateBrowsing") private var storedPrivateBrowsing = false
    private var privateBrowsing: Bool {
        agentSettings?.isolatesPreloadCookies == true ||
            (agentSettings?.value("privateBrowsing", fallback: storedPrivateBrowsing) ?? storedPrivateBrowsing)
    }
    @AppStorage("upgradeToHTTPS") private var storedUpgradeToHTTPS = true
    private var upgradeToHTTPS: Bool {
        agentSettings?.value("upgradeToHTTPS", fallback: storedUpgradeToHTTPS) ?? storedUpgradeToHTTPS
    }

    // Content Mode
    @AppStorage("preferredContentMode") private var storedPreferredContentMode = 0
    private var preferredContentMode: Int {
        agentSettings?.value("preferredContentMode", fallback: storedPreferredContentMode) ?? storedPreferredContentMode
    }

    // User Agent
    @AppStorage("customUserAgent") private var storedCustomUserAgent = ""
    private var customUserAgent: String {
        agentSettings?.value("customUserAgent", fallback: storedCustomUserAgent) ?? storedCustomUserAgent
    }

    // WKWebView Size
    @AppStorage("webViewWidthRatio") private var storedWebViewWidthRatio = 1.0
    private var webViewWidthRatio: Double {
        agentSettings?.value("webViewWidthRatio", fallback: storedWebViewWidthRatio) ?? storedWebViewWidthRatio
    }
    @AppStorage("webViewHeightRatio") private var storedWebViewHeightRatio = 0.82
    private var webViewHeightRatio: Double {
        agentSettings?.value("webViewHeightRatio", fallback: storedWebViewHeightRatio) ?? storedWebViewHeightRatio
    }

    private var isFullSize: Bool {
        webViewWidthRatio >= 0.99 && webViewHeightRatio >= 0.99
    }

    var body: some View {
        GeometryReader { geometry in
            let webViewWidth = geometry.size.width * webViewWidthRatio
            let webViewHeight = geometry.size.height * BarConstants.effectiveHeightRatio(webViewHeightRatio, for: geometry.size.height)

            ZStack {
                // Background (only shown when size is less than 100%)
                if !isFullSize {
                    Color(uiColor: .systemGroupedBackground)
                        .ignoresSafeArea()

                    // Checkerboard pattern (to indicate transparent area)
                    CheckerboardPattern()
                        .ignoresSafeArea()
                }

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
        config.preferences.isElementFullscreenEnabled = elementFullscreenEnabled
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
    @Environment(\.agentBrowserSettings) private var agentSettings
    let urlString: String
    let configuration: WKWebViewConfiguration
    @Binding var isLoading: Bool
    let navigator: WebViewNavigator?

    // Navigation & Gestures
    @AppStorage("allowsBackForwardGestures") private var storedAllowsBackForwardGestures = false
    private var allowsBackForwardGestures: Bool {
        agentSettings?.value("allowsBackForwardGestures", fallback: storedAllowsBackForwardGestures) ?? storedAllowsBackForwardGestures
    }
    @AppStorage("allowsLinkPreview") private var storedAllowsLinkPreview = true
    private var allowsLinkPreview: Bool {
        agentSettings?.value("allowsLinkPreview", fallback: storedAllowsLinkPreview) ?? storedAllowsLinkPreview
    }
    @AppStorage("textInteractionEnabled") private var storedTextInteractionEnabled = true
    private var textInteractionEnabled: Bool {
        agentSettings?.value("textInteractionEnabled", fallback: storedTextInteractionEnabled) ?? storedTextInteractionEnabled
    }

    // Display
    @AppStorage("pageZoom") private var storedPageZoom = 1.0
    private var pageZoom: Double {
        agentSettings?.value("pageZoom", fallback: storedPageZoom) ?? storedPageZoom
    }
    @AppStorage("underPageBackgroundColor") private var storedUnderPageBackgroundColorHex = ""
    private var underPageBackgroundColorHex: String {
        agentSettings?.value("underPageBackgroundColor", fallback: storedUnderPageBackgroundColorHex) ?? storedUnderPageBackgroundColorHex
    }

    // Features
    @AppStorage("findInteractionEnabled") private var storedFindInteractionEnabled = false
    private var findInteractionEnabled: Bool {
        agentSettings?.value("findInteractionEnabled", fallback: storedFindInteractionEnabled) ?? storedFindInteractionEnabled
    }

    // User Agent
    @AppStorage("customUserAgent") private var storedCustomUserAgent = ""
    private var customUserAgent: String {
        agentSettings?.value("customUserAgent", fallback: storedCustomUserAgent) ?? storedCustomUserAgent
    }

    // Emulation
    @AppStorage("emulationColorScheme") private var storedEmulationColorScheme = "system"
    private var emulationColorScheme: String {
        agentSettings?.value("emulationColorScheme", fallback: storedEmulationColorScheme) ?? storedEmulationColorScheme
    }
    @AppStorage("emulationReducedMotion") private var storedEmulationReducedMotion = false
    private var emulationReducedMotion: Bool {
        agentSettings?.value("emulationReducedMotion", fallback: storedEmulationReducedMotion) ?? storedEmulationReducedMotion
    }
    @AppStorage("emulationHighContrast") private var storedEmulationHighContrast = false
    private var emulationHighContrast: Bool {
        agentSettings?.value("emulationHighContrast", fallback: storedEmulationHighContrast) ?? storedEmulationHighContrast
    }
    @AppStorage("emulationReducedTransparency") private var storedEmulationReducedTransparency = false
    private var emulationReducedTransparency: Bool {
        agentSettings?.value("emulationReducedTransparency", fallback: storedEmulationReducedTransparency) ?? storedEmulationReducedTransparency
    }

    func makeCoordinator() -> Coordinator {
        let saved = PreloadProfileStore.activeProfile()
        return Coordinator(
            isLoading: $isLoading,
            navigator: navigator,
            preloadProfile: agentSettings?.preloadProfile(fallback: saved) ?? saved
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
        coordinator.navigator?.detach(from: uiView)
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

#Preview {
    @Previewable @State var id = UUID()
    WebViewContainer(urlString: "https://apple.com", webViewID: $id, navigator: nil)
}
