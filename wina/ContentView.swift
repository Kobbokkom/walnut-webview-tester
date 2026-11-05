//
//  ContentView.swift
//  wina
//
//  Created by 박지원 on 12/6/25.
//

import SwiftUI
import SwiftUIBackports
import WebKit

struct ContentView: View {
    // MARK: - State Properties (internal for extension access)

    @State var urlText: String = ""
    @State var showDropdown: Bool = false
    @State var showSettings: Bool = false
    @State var showBookmarks: Bool = false
    @State var showInfo: Bool = false
    @State private var devToolsState = DevToolsOverlayState()
    @State private var showURLInput: Bool = false
    @State var showPreloadSettings: Bool = false
    @State var preloadProfileBeforeSettings: WebViewPreloadProfile = .defaultSavedSetup
    @State private var urlInputText: String = ""
    @State var showAbout: Bool = false
    @State var urlValidationState: URLValidationState = .empty
    @State var useSafariWebView: Bool = false
    @State var showWebView: Bool = false
    @State private var loadedURL = ""
    @State private var webViewID = UUID()
    @State var validationTask: Task<Void, Never>?
    @State private var webViewNavigator = WebViewNavigator()
    @State private var screenRecorder = WebViewRecorder()
    @State private var storageManager = StorageManager()
    @State private var showSafariUnsupportedAlert = false
    @State private var safariUnsupportedURL = ""
    @FocusState var textFieldFocused: Bool

    // Shared URL storage
    var urlStorage: URLStorageManager { URLStorageManager.shared }

    // Quick options (synced with Settings)
    @AppStorage("cleanStart") var cleanStart = true
    @AppStorage("privateBrowsing") var privateBrowsing = false
    // SafariVC: Use callback test page instead of manual URL
    @State var useCallbackTestPage: Bool = false
    @AppStorage("colorSchemeOverride") private var colorSchemeOverride: String?

    // Safari configuration settings (for onChange detection)
    @AppStorage("safariEntersReaderIfAvailable") private var safariEntersReaderIfAvailable = false
    @AppStorage("safariBarCollapsingEnabled") private var safariBarCollapsingEnabled = true

    // Eruda mode (third-party in-page console)
    @AppStorage("erudaModeEnabled") private var erudaModeEnabled = false
    @AppStorage(PreloadProfileStore.activeProfileKey) var preloadActiveProfileData = Data()

    // WebView size settings (for fullscreen detection)
    @AppStorage("webViewWidthRatio") private var webViewWidthRatio: Double = 1.0
    @AppStorage("webViewHeightRatio") private var webViewHeightRatio: Double = 0.82
    @AppStorage("safariWidthRatio") private var safariWidthRatio: Double = 1.0
    @AppStorage("safariHeightRatio") private var safariHeightRatio: Double = 0.82

    // Bars are expanded (fixed position) when WebView is NOT fullscreen
    // Fullscreen = both width and height at 99%+ (matches isFullSize in WebViewContainer)
    private var shouldBarsBeExpanded: Bool {
        let widthRatio = useSafariWebView ? safariWidthRatio : webViewWidthRatio
        let heightRatio = useSafariWebView ? safariHeightRatio : webViewHeightRatio
        let isFullSize = widthRatio >= 0.99 && heightRatio >= 0.99
        return !isFullSize
    }

    private var preferredScheme: ColorScheme? {
        switch colorSchemeOverride {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var filteredURLs: [String] {
        urlStorage.filteredHistory(query: urlText)
    }

    private var preloadProfile: WebViewPreloadProfile {
        _ = preloadActiveProfileData
        return PreloadProfileStore.activeProfile()
    }

    var isPreloadProfileEnabled: Bool {
        preloadProfile.isEnabled
    }

    var preloadProfileSummary: String {
        preloadProfile.localizedEnabledSummary
    }

    let urlParts = [
        "https://", "http://",
        "www.", "m.",
        ".com",
        "192.168.", ":8080", ":3000",
    ]
    @Environment(\.webViewContainerSize) private var containerSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var browserSize: CGSize = .zero

    private var shouldDockDevTools: Bool {
        horizontalSizeClass == .regular && showWebView && !useSafariWebView && !erudaModeEnabled
    }

    var inputWidth: CGFloat { min(340, max(0, containerSize.width - 32)) }

    var body: some View {
        GeometryReader { geometry in
            let frames = DevToolsWorkspaceLayout.frames(in: geometry.size, division: activeDivision(in: geometry))
            let hasPanel = shouldDockDevTools && devToolsState.selectedTool != nil
            let browserFrame = hasPanel ? frames.browser : CGRect(origin: .zero, size: geometry.size)
            ZStack(alignment: .topLeading) {
                browserContent
                    .frame(width: browserFrame.width, height: browserFrame.height)
                    .onGeometryChange(for: CGSize.self) { proxy in
                        CGSize(width: proxy.size.width, height: proxy.size.height + proxy.safeAreaInsets.bottom)
                    } action: { size in
                        let previousHeight = browserSize.height
                        browserSize = size
                        webViewHeightRatio = BarConstants.heightRatioAfterResize(
                            widthRatio: webViewWidthRatio, heightRatio: webViewHeightRatio,
                            from: previousHeight, to: size.height
                        )
                        safariHeightRatio = BarConstants.heightRatioAfterResize(
                            widthRatio: safariWidthRatio, heightRatio: safariHeightRatio,
                            from: previousHeight, to: size.height
                        )
                    }
                    .position(x: browserFrame.midX, y: browserFrame.midY)
                if hasPanel, let tool = devToolsState.selectedTool {
                    DevToolsPanel(state: devToolsState) {
                        devToolsContent(for: tool)
                            .environment(\.closeDevTools, { devToolsState.close(tool) })
                    }
                    .frame(width: frames.tools.width, height: frames.tools.height)
                    .position(x: frames.tools.midX, y: frames.tools.midY)
                }
            }
        }
        .environment(\.webViewContainerSize, browserSize == .zero ? containerSize : browserSize)
        .onChange(of: shouldDockDevTools, initial: true) { _, docked in
            devToolsState.isDocked = docked
        }
        .sheet(isPresented: $showSettings) {
            if useSafariWebView {
                SafariVCSettingsView(webViewID: $webViewID)
                    .fullSizeSheet()
                    .preferredColorScheme(preferredScheme)
            } else {
                LoadedSettingsView(
                    webViewID: $webViewID,
                    loadedURL: $loadedURL,
                    navigator: webViewNavigator
                )
                .fullSizeSheet()
                .preferredColorScheme(preferredScheme)
            }
        }
        .sheet(
            isPresented: $showPreloadSettings,
            onDismiss: applyPreloadSettingsChangeIfNeeded
        ) {
            PreloadProfileSettingsView()
                .fullSizeSheet()
                .preferredColorScheme(preferredScheme)
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksSheet(
                bookmarkedURLs: urlStorage.bookmarks,
                onSelect: { url in
                    if showWebView {
                        urlInputText = url
                        showURLInput = true
                    } else {
                        urlText = url
                        textFieldFocused = true
                    }
                },
                onDelete: { url in
                    urlStorage.removeBookmark(url)
                },
                onAdd: { url in
                    urlStorage.addBookmark(url)
                },
                currentURL: {
                    if showWebView {
                        if useSafariWebView {
                            return loadedURL
                        }
                        return webViewNavigator.currentURL?.absoluteString ?? ""
                    }
                    return urlText
                }()
            )
            .preferredColorScheme(preferredScheme)
        }
        .sheet(isPresented: $showInfo) {
            if useSafariWebView {
                SafariVCInfoView(webViewID: $webViewID)
                    .fullSizeSheet()
                    .preferredColorScheme(preferredScheme)
            } else {
                // Pass navigator only when WebView is loaded (for live page testing)
                InfoView(
                    navigator: showWebView ? webViewNavigator : nil,
                    webViewID: showWebView ? $webViewID : nil,
                    loadedURL: showWebView ? $loadedURL : nil
                )
                .fullSizeSheet()
                .preferredColorScheme(preferredScheme)
            }
        }
        .sheet(isPresented: devToolsState.presentationBinding(for: .console)) {
            devToolsContent(for: .console)
                .devToolsSheet()
                .preferredColorScheme(preferredScheme)
        }
        .sheet(isPresented: devToolsState.presentationBinding(for: .network)) {
            devToolsContent(for: .network)
                .devToolsSheet()
                .preferredColorScheme(preferredScheme)
        }
        .sheet(isPresented: devToolsState.presentationBinding(for: .storage)) {
            devToolsContent(for: .storage)
                .devToolsSheet()
                .preferredColorScheme(preferredScheme)
        }
        .sheet(isPresented: devToolsState.presentationBinding(for: .performance)) {
            devToolsContent(for: .performance)
                .devToolsSheet()
                .preferredColorScheme(preferredScheme)
        }
        .sheet(isPresented: devToolsState.presentationBinding(for: .editor)) {
            devToolsContent(for: .editor)
                .devToolsSheet()
                .preferredColorScheme(preferredScheme)
        }
        .sheet(isPresented: devToolsState.presentationBinding(for: .accessibility)) {
            devToolsContent(for: .accessibility)
                .devToolsSheet()
                .preferredColorScheme(preferredScheme)
        }
        .sheet(isPresented: devToolsState.presentationBinding(for: .snippets)) {
            devToolsContent(for: .snippets)
                .devToolsSheet()
                .preferredColorScheme(preferredScheme)
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
                .preferredColorScheme(preferredScheme)
        }
        .alert("Unsupported URL", isPresented: $showSafariUnsupportedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("SafariVC supports only http and https URLs.\n\n\(safariUnsupportedURL)")
        }
        // Recreate SafariVC when configuration settings change
        .onChange(of: safariEntersReaderIfAvailable) { _, _ in
            if useSafariWebView && showWebView {
                webViewID = UUID()
            }
        }
        .onChange(of: safariBarCollapsingEnabled) { _, _ in
            if useSafariWebView && showWebView {
                webViewID = UUID()
            }
        }
        // Eruda mode: inject/destroy when toggled
        .onChange(of: erudaModeEnabled) { _, newValue in
            guard showWebView && !useSafariWebView else { return }
            Task {
                if newValue {
                    await webViewNavigator.injectEruda()
                } else {
                    await webViewNavigator.destroyEruda()
                }
            }
        }
    }

    private func activeDivision(in geometry: GeometryProxy) -> CGRect? {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            return geometry.reservedRegions(kind: .division).first?.frame
        }
        #endif
        return nil
    }

    private var browserContent: some View {
        ZStack {
            if showWebView {
                // WebView screen
                WebViewContainer(
                    urlString: loadedURL,
                    useSafari: useSafariWebView,
                    webViewID: $webViewID,
                    navigator: useSafariWebView ? nil : webViewNavigator
                )
                .ignoresSafeArea(edges: .bottom)
            } else {
                // URL input screen
                urlInputView
            }

            // Menu bars
            if showWebView {
                OverlayMenuBars(
                    showWebView: showWebView,
                    hasBookmarks: !urlStorage.bookmarks.isEmpty,
                    useSafariVC: useSafariWebView,
                    isOverlayMode: !shouldBarsBeExpanded,
                    erudaModeEnabled: erudaModeEnabled,
                    hasDockedDevTools: shouldDockDevTools && devToolsState.selectedTool != nil,
                    onHome: {
                        // Close all DevTools overlays with single call
                        devToolsState.closeAll()

                        // Close other sheets
                        showSettings = false
                        showBookmarks = false
                        showInfo = false
                        showURLInput = false
                        urlInputText = ""

                        // Clear initial URL tracking
                        webViewNavigator.clearInitialURL()

                        withAnimation(.easeOut(duration: 0.2)) {
                            showWebView = false
                        }
                    },
                    onURLChange: { newURL in
                        guard validateSafariURLIfNeeded(newURL) else { return }
                        // Add to history
                        urlStorage.addToHistory(newURL)

                        // Load in same WebView instance (preserves history)
                        if !useSafariWebView {
                            webViewNavigator.loadURL(newURL)
                        } else {
                            // SafariVC needs recreation
                            loadedURL = newURL
                            webViewID = UUID()
                        }
                    },
                    navigator: useSafariWebView ? nil : webViewNavigator,
                    recorder: screenRecorder,
                    urlStorage: urlStorage,
                    showURLInput: $showURLInput,
                    urlInputText: $urlInputText,
                    showSettings: $showSettings,
                    showBookmarks: $showBookmarks,
                    showInfo: $showInfo,
                    devToolsState: devToolsState
                )
            } else if !showWebView {
                topBar
            }
        }
        .overlay {
            if devToolsState.isOpen(.searchText) {
                SearchTextOverlay(
                    navigator: webViewNavigator,
                    isPresented: devToolsState.binding(for: .searchText),
                    bottomPaddingCalculator: searchOverlayBottomPadding
                )
            }
        }
    }

    @ViewBuilder
    private func devToolsContent(for tool: DevToolsOverlay) -> some View {
        switch tool {
        case .console:
            ConsoleView(consoleManager: webViewNavigator.consoleManager, navigator: webViewNavigator)
        case .network:
            NetworkView(networkManager: webViewNavigator.networkManager, resourceManager: webViewNavigator.resourceManager)
        case .storage:
            StorageView(storageManager: storageManager, navigator: webViewNavigator)
        case .performance:
            PerformanceView(
                performanceManager: webViewNavigator.performanceManager,
                onCollect: { Task { await collectPerformanceData(webViewNavigator, isReload: false) } },
                onReload: { Task { await collectPerformanceData(webViewNavigator, isReload: true) } }
            )
        case .editor:
            SourcesView(navigator: webViewNavigator)
        case .accessibility:
            AccessibilityAuditView(navigator: webViewNavigator)
        case .snippets:
            SnippetsView(navigator: webViewNavigator)
        case .searchText:
            EmptyView()
        }
    }

    // MARK: - Search Overlay Position

    private func searchOverlayBottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        let gapAboveBar: CGFloat = 8
        let barTopPadding = BarConstants.barHeight - (safeAreaBottom * BarConstants.bottomBarSafeAreaRatio)
        return max(12, barTopPadding + gapAboveBar)
    }

    // MARK: - URL Actions (internal for extension access)

    func submitURL() {
        // Handle callback test page mode
        let targetURL: String
        if useCallbackTestPage {
            targetURL = CallbackTestManager.testPageURL.absoluteString
        } else {
            guard !urlText.isEmpty else { return }
            guard validateSafariURLIfNeeded(urlText) else { return }
            // Add to history via shared storage
            urlStorage.addToHistory(urlText)
            targetURL = urlText
        }

        // Normalize URL for initialURL tracking (must match the scheme the
        // WebView actually loads, so "go to initial" matches the loaded page)
        let normalized = URLValidator.normalizeURL(targetURL)
        let initialURLValue = URL(string: normalized)

        // Clean Start: clear all website data and DevTools logs before loading
        if cleanStart {
            Task {
                // 1. Clear all WKWebView website data (cookies, localStorage, cache, etc.)
                let dataStore = WKWebsiteDataStore.default()
                let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
                let records = await dataStore.dataRecords(ofTypes: allTypes)
                await dataStore.removeData(ofTypes: allTypes, for: records)

                await MainActor.run {
                    // 2. Clear all DevTools data
                    webViewNavigator.consoleManager.clear()
                    webViewNavigator.networkManager.clear()
                    webViewNavigator.resourceManager.clear()
                    webViewNavigator.performanceManager.clear()
                    webViewNavigator.accessibilityManager.clear()
                    storageManager.clear()

                    // 3. Create fresh navigator instance for completely new session
                    webViewNavigator.detach()
                    webViewNavigator = WebViewNavigator()

                    // Set initial URL for "go to initial" feature
                    if let url = initialURLValue {
                        webViewNavigator.setInitialURL(url)
                    }

                    loadedURL = targetURL
                    webViewID = UUID()  // Force new WebView instance
                    withAnimation(.easeOut(duration: 0.2)) {
                        showWebView = true
                    }
                }
            }
        } else {
            // Set initial URL for "go to initial" feature
            if let url = initialURLValue {
                webViewNavigator.setInitialURL(url)
            }

            loadedURL = targetURL
            withAnimation(.easeOut(duration: 0.2)) {
                showWebView = true
            }
        }
    }

    private func validateSafariURLIfNeeded(_ url: String) -> Bool {
        guard useSafariWebView else { return true }
        guard URLValidator.isSupportedSafariURL(url) else {
            safariUnsupportedURL = url
            showSafariUnsupportedAlert = true
            return false
        }
        return true
    }

    func removeURL(_ url: String) {
        urlStorage.removeFromHistory(url)
    }

    func validateURL() {
        guard !urlText.isEmpty else {
            urlValidationState = .empty
            return
        }
        urlValidationState = URLValidator.isValidURL(urlText) ? .valid : .invalid
    }

    // MARK: - Performance Data Collection

    /// Collect performance data with proper page load detection
    @MainActor
    private func collectPerformanceData(_ navigator: WebViewNavigator, isReload: Bool) async {
        let manager = navigator.performanceManager
        manager.isLoading = true
        manager.lastError = nil

        if isReload {
            manager.clear()
            navigator.reload()
            // Wait for page load with polling (max 10s)
            let maxAttempts = 20
            for _ in 0..<maxAttempts {
                try? await Task.sleep(for: .milliseconds(500))
                // Check if page load is complete
                if let ready = await navigator.evaluateJavaScript(
                    "document.readyState === 'complete' && performance.getEntriesByType('navigation')[0]?.loadEventEnd > 0"
                ) as? Bool, ready {
                    break
                }
            }
        }

        // Collect performance data
        if let result = await navigator.evaluateJavaScript(PerformanceManager.collectionScript) as? String {
            manager.parseData(from: result)
            // Verify we got valid data (navigation timing should have loadEventTime > 0)
            if manager.data.navigation == nil && manager.data.paints.isEmpty {
                manager.lastError = "Page load incomplete. Try refreshing again."
            }
        } else {
            manager.lastError = "Failed to collect performance data. Make sure a page is loaded."
        }

        manager.isLoading = false
    }

    private func applyPreloadSettingsChangeIfNeeded() {
        guard !useSafariWebView,
            showWebView,
            preloadProfileBeforeSettings != PreloadProfileStore.activeProfile()
        else {
            return
        }

        webViewID = UUID()
    }

    func openPreloadSettingsFromHome() {
        preloadProfileBeforeSettings = PreloadProfileStore.activeProfile()
        showPreloadSettings = true
    }

    func enablePreloadProfileFromHome() {
        var profile = PreloadProfileStore.activeProfile()
        guard !profile.isEnabled else { return }

        profile.isEnabled = true
        PreloadProfileStore.saveActiveProfile(profile)

        if !useSafariWebView, showWebView {
            webViewID = UUID()
        }
    }

    func disablePreloadProfileFromHome() {
        var profile = PreloadProfileStore.activeProfile()
        guard profile.isEnabled else { return }

        profile.isEnabled = false
        PreloadProfileStore.saveActiveProfile(profile)

        if !useSafariWebView, showWebView {
            webViewID = UUID()
        }
    }
}

#Preview {
    ContentView()
}
