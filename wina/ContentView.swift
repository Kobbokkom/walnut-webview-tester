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
    @State var devToolsState = DevToolsOverlayState()
    @State private var showURLInput: Bool = false
    @State var showPreloadSettings: Bool = false
    @State var preloadProfileBeforeSettings: WebViewPreloadProfile = .defaultSavedSetup
    @State private var urlInputText: String = ""
    @State var showAbout: Bool = false
    @State var urlValidationState: URLValidationState = .empty
    @State var useSafariWebView: Bool = false
    @State var showWebView: Bool = false
    @State var isPreparingCleanStart = false
    @State private var showCleanStartOptionsChanged = false
    @State var loadedURL = ""
    @State var webViewID = UUID()
    @State var validationTask: Task<Void, Never>?
    @State var webViewNavigator = WebViewNavigator()
    @State var screenRecorder = WebViewRecorder()
    @State var storageManager = StorageManager()
    @State private var storageEditor: StorageEditorTarget?
    @State var consoleSession = ConsoleSession()
    @State private var showSafariUnsupportedAlert = false
    @State private var safariUnsupportedURL = ""
    @FocusState var textFieldFocused: Bool
    @Environment(\.scenePhase) private var agentScenePhase
    @State var agentSession = AgentSession()
    @State var agentSafariNavigation = AgentNavigation()
    @State var agentCaptureRecorder: WebViewRecorder?
    @State var agentCaptureDefaults: (console: Bool, network: Bool, resources: Bool)?
    @State var showAgentConnection = false

    // Shared URL storage
    var urlStorage: URLStorageManager { URLStorageManager.shared }

    // Quick options (synced with Settings)
    @AppStorage("cleanStart") var cleanStart = true
    @AppStorage("privateBrowsing") var privateBrowsing = false
    // SafariVC: Use callback test page instead of manual URL
    @State var useCallbackTestPage: Bool = false
    var isCallbackTestPageActive: Bool { useSafariWebView && useCallbackTestPage }
    @AppStorage("colorSchemeOverride") private var colorSchemeOverride: String?

    // Safari configuration settings (for onChange detection)
    @AppStorage("safariEntersReaderIfAvailable") private var safariEntersReaderIfAvailable = false
    @AppStorage("safariBarCollapsingEnabled") private var safariBarCollapsingEnabled = true

    // Eruda mode (third-party in-page console)
    @AppStorage("erudaModeEnabled") private var erudaModeEnabled = false
    @AppStorage(PreloadProfileStore.activeProfileKey) var preloadActiveProfileData = Data()

    private var agentBrowserSettings: AgentBrowserSettings? {
        agentSession.isRunning ? AgentBrowserSettings.shared : nil
    }

    private var effectiveErudaMode: Bool {
        agentBrowserSettings?.value("erudaModeEnabled", fallback: erudaModeEnabled) ?? erudaModeEnabled
    }

    // WebView size settings (for fullscreen detection)
    @AppStorage("webViewWidthRatio") private var webViewWidthRatio: Double = 1.0
    @AppStorage("webViewHeightRatio") private var webViewHeightRatio: Double = 0.82
    @AppStorage("safariWidthRatio") private var safariWidthRatio: Double = 1.0
    @AppStorage("safariHeightRatio") private var safariHeightRatio: Double = 0.82

    // Bars are expanded (fixed position) when WebView is NOT fullscreen
    // Fullscreen = both width and height at 99%+ (matches isFullSize in WebViewContainer)
    private var shouldBarsBeExpanded: Bool {
        let widthRatio = useSafariWebView
            ? agentBrowserSettings?.value("safariWidthRatio", fallback: safariWidthRatio) ?? safariWidthRatio
            : agentBrowserSettings?.value("webViewWidthRatio", fallback: webViewWidthRatio) ?? webViewWidthRatio
        let heightRatio = useSafariWebView
            ? agentBrowserSettings?.value("safariHeightRatio", fallback: safariHeightRatio) ?? safariHeightRatio
            : agentBrowserSettings?.value("webViewHeightRatio", fallback: webViewHeightRatio) ?? webViewHeightRatio
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
        let saved = PreloadProfileStore.activeProfile()
        return agentBrowserSettings?.preloadProfile(fallback: saved) ?? saved
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
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var browserSize: CGSize = .zero

    var inputWidth: CGFloat { min(340, max(0, containerSize.width - 32)) }

    var body: some View {
        GeometryReader { geometry in
            let fold = foldRegion(in: geometry)
            let hasRoomForPanel = verticalSizeClass == .regular || fold.isPresent
            let canDock = !UIDevice.current.isIPad && horizontalSizeClass == .regular && hasRoomForPanel
                && showWebView && !useSafariWebView && !effectiveErudaMode
            // The editor belongs to the current presentation until the user saves or cancels.
            let docked = storageEditor == nil ? canDock : devToolsState.isDocked
            let frames = DevToolsWorkspaceLayout.frames(in: geometry.size, division: fold.activeFrame)
            let hasPanel = docked && devToolsState.selectedTool != nil
            let browserFrame = hasPanel ? frames.browser : CGRect(origin: .zero, size: geometry.size)
            ZStack(alignment: .topLeading) {
                browserContent(hasDockedDevTools: hasPanel)
                    .frame(width: browserFrame.width, height: browserFrame.height)
                    .onGeometryChange(for: CGSize.self) { proxy in
                        CGSize(width: proxy.size.width, height: proxy.size.height + proxy.safeAreaInsets.bottom)
                    } action: { size in
                        browserSize = size
                    }
                    .position(x: browserFrame.midX, y: browserFrame.midY)
                if hasPanel, let tool = devToolsState.selectedTool {
                    DevToolsPanel(state: devToolsState) {
                        devToolsContent(for: tool)
                            .environment(\.closeDevTools, { devToolsState.close(tool) })
                    }
                    .frame(width: frames.tools.width, height: frames.tools.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .position(x: frames.tools.midX, y: frames.tools.midY)
                }
            }
            .onChange(of: docked, initial: true) { _, newValue in
                devToolsState.isDocked = newValue
            }
        }
        .environment(\.agentBrowserSettings, agentBrowserSettings)
        .overlay(alignment: .top) {
            if showWebView && agentSession.isRunning {
                let isRecording = agentCaptureRecorder?.isRecording == true
                GlassIconButton(
                    icon: isRecording ? "record.circle.fill" : "network",
                    color: isRecording ? .red : .green,
                    accessibilityLabel: isRecording ? "Mac Agent recording" : "Mac Agent"
                ) {
                    showAgentConnection = true
                }
                .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showAgentConnection) {
            AgentConnectionView(session: agentSession, start: startAgentConnection)
                .preferredColorScheme(preferredScheme)
        }
        .background {
            AgentApprovalPresenter(request: agentSession.approval, resolve: agentSession.resolveApproval)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onChange(of: agentScenePhase) { _, phase in
            if phase == .background { agentSession.stop() }
        }
        .onDisappear { agentSession.stop() }
        .onChange(of: ObjectIdentifier(webViewNavigator)) { _, _ in
            webViewNavigator.agentTrackingEnabled = agentSession.isConnected
        }
        .onChange(of: agentSession.isConnected) { _, connected in
            webViewNavigator.agentTrackingEnabled = connected
        }
        .onChange(of: AgentBrowserSettings.shared.rebuildID) { _, _ in
            if agentSession.isRunning && !useSafariWebView { recreateAgentBrowser() }
        }
        .onChange(of: AgentBrowserSettings.shared.safariRebuildID) { _, _ in
            if agentSession.isRunning && useSafariWebView { recreateAgentBrowser() }
        }
        .alert("Browser options changed", isPresented: $showCleanStartOptionsChanged) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your browsing options and open the URL again.")
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
        .onChange(of: effectiveErudaMode) { _, newValue in
            guard showWebView && !useSafariWebView else { return }
            Task {
                if newValue {
                    await webViewNavigator.injectEruda()
                } else {
                    await webViewNavigator.destroyEruda()
                }
            }
        }
        .environment(\.webViewContainerSize, browserSize == .zero ? containerSize : browserSize)
    }

    private func foldRegion(in geometry: GeometryProxy) -> (isPresent: Bool, activeFrame: CGRect?) {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            let regions = geometry.reservedRegions(kind: .division, options: .includeInactive)
            return (!regions.isEmpty, regions.first(where: \.isActive)?.frame)
        }
        #endif
        return (false, nil)
    }

    private func browserContent(hasDockedDevTools: Bool) -> some View {
        ZStack {
            if showWebView {
                // WebView screen
                WebViewContainer(
                    urlString: loadedURL,
                    useSafari: useSafariWebView,
                    webViewID: $webViewID,
                    navigator: useSafariWebView ? nil : webViewNavigator,
                    safariNavigation: agentSafariNavigation
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
                    erudaModeEnabled: effectiveErudaMode,
                    hasDockedDevTools: hasDockedDevTools,
                    onHome: returnHome,
                    onURLChange: { navigateDisplayedURL($0) },
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
        .disabled(isPreparingCleanStart)
    }

    @ViewBuilder
    private func devToolsContent(for tool: DevToolsOverlay) -> some View {
        switch tool {
        case .console:
            ConsoleView(consoleManager: webViewNavigator.consoleManager, navigator: webViewNavigator, session: consoleSession)
        case .network:
            NetworkView(networkManager: webViewNavigator.networkManager, resourceManager: webViewNavigator.resourceManager)
        case .storage:
            StorageView(storageManager: storageManager, navigator: webViewNavigator, editor: $storageEditor)
        case .performance:
            PerformanceView(
                performanceManager: webViewNavigator.performanceManager,
                documentID: webViewNavigator.documentID,
                onCollect: { Task { await webViewNavigator.performanceManager.collect(using: webViewNavigator, reload: false) } },
                onReload: { Task { await webViewNavigator.performanceManager.collect(using: webViewNavigator, reload: true) } }
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

    @discardableResult
    func submitURL() -> Bool {
        guard !isPreparingCleanStart else { return false }

        let isCallback = isCallbackTestPageActive
        let targetURL: String
        if isCallback {
            targetURL = CallbackTestManager.testPageURL.absoluteString
        } else {
            validateURL()
            guard urlValidationState == .valid, validateSafariURLIfNeeded(urlText) else { return false }
            targetURL = urlText
        }

        if effectiveCleanStart && !useSafariWebView {
            isPreparingCleanStart = true
            Task { @MainActor in
                await completeCleanStart(targetURL)
            }
        } else {
            openSubmittedURL(targetURL, recordsHistory: !isCallback)
        }
        return true
    }

    func openSubmittedURL(_ targetURL: String, recordsHistory: Bool) {
        if recordsHistory { urlStorage.addToHistory(targetURL) }
        if let url = URL(string: URLValidator.normalizeURL(targetURL)) {
            webViewNavigator.setInitialURL(url)
        }
        loadedURL = targetURL
        withAnimation(.easeOut(duration: 0.2)) { showWebView = true }
    }

    func validateSafariURLIfNeeded(_ url: String) -> Bool {
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

extension ContentView {
    var effectiveCleanStart: Bool {
        agentBrowserSettings?.value("cleanStart", fallback: cleanStart) ?? cleanStart
    }

    var effectivePrivateBrowsing: Bool {
        agentRequiresPrivateBrowsing ||
            (agentBrowserSettings?.value("privateBrowsing", fallback: privateBrowsing) ?? privateBrowsing)
    }

    var agentRequiresPrivateBrowsing: Bool { agentBrowserSettings?.isolatesPreloadCookies == true }

    func setLocalCleanStart(_ value: Bool) {
        cleanStart = value
        agentBrowserSettings?.reset(keys: ["cleanStart"])
    }

    func setLocalPrivateBrowsing(_ value: Bool) {
        privateBrowsing = value
        agentBrowserSettings?.reset(keys: ["privateBrowsing"])
    }

    func recreateAgentBrowser() {
        guard showWebView else { return }
        if !useSafariWebView, let url = webViewNavigator.currentURL { loadedURL = url.absoluteString }
        webViewID = UUID()
    }

    func returnHome() {
        screenRecorder.stopRecording()
        webViewNavigator.recorder.stopRecording()
        devToolsState.closeAll()
        consoleSession = ConsoleSession()
        showSettings = false
        showBookmarks = false
        showInfo = false
        showURLInput = false
        urlInputText = ""
        webViewNavigator.clearInitialURL()
        withAnimation(.easeOut(duration: 0.2)) { showWebView = false }
    }

    func navigateDisplayedURL(
        _ url: String,
        recordsHistory: Bool = true,
        onNavigation: ((WKNavigation?) -> Void)? = nil
    ) -> Bool {
        guard validateSafariURLIfNeeded(url) else { return false }
        if recordsHistory { urlStorage.addToHistory(url) }
        if useSafariWebView {
            loadedURL = url
            webViewID = UUID()
        } else {
            let navigation = webViewNavigator.loadURL(url)
            onNavigation?(navigation)
        }
        return true
    }

    @discardableResult
    func completeCleanStart(_ targetURL: String, recordsHistory: Bool = true) async -> Bool {
        defer { isPreparingCleanStart = false }
        guard !Task.isCancelled else { return false }
        let usesPrivateStore = effectivePrivateBrowsing
        let navigator = webViewNavigator
        let startedInSafari = useSafariWebView
        let closePage = !usesPrivateStore && showWebView && !startedInSafari
        let expectedPageVisibility = showWebView && !closePage
        let originalViewID = webViewID
        func browserUnchanged() -> Bool {
            usesPrivateStore == effectivePrivateBrowsing && startedInSafari == useSafariWebView &&
                expectedPageVisibility == showWebView && originalViewID == webViewID
        }
        if closePage {
            // Wait for SwiftUI to dismantle the active view before WebKit removes its data.
            let session = consoleSession
            returnHome()
            consoleSession = session
            let deadline = ContinuousClock.now + .seconds(5)
            while navigator.isAttached && browserUnchanged() && ContinuousClock.now < deadline && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(25))
            }
            guard !Task.isCancelled else { return false }
            guard !navigator.isAttached, browserUnchanged() else {
                showCleanStartOptionsChanged = true
                return false
            }
        }
        if !usesPrivateStore {
            await WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast
            )
        }

        guard !Task.isCancelled else { return false }
        guard browserUnchanged() else {
            showCleanStartOptionsChanged = true
            return false
        }
        navigator.consoleManager.clear()
        navigator.networkManager.clear()
        navigator.resourceManager.clear()
        navigator.performanceManager.clear()
        navigator.accessibilityManager.clear()
        storageManager.clear()
        let logSettings = navigator.agentLogSettings
        navigator.detach()
        webViewNavigator = WebViewNavigator()
        if agentSession.isConnected {
            webViewNavigator.agentLogSettings = logSettings
            webViewNavigator.agentTrackingEnabled = true
            webViewNavigator.consoleManager.isCapturing = navigator.consoleManager.isCapturing
            webViewNavigator.networkManager.isCapturing = navigator.networkManager.isCapturing
            webViewNavigator.resourceManager.isCapturing = navigator.resourceManager.isCapturing
        }
        useSafariWebView = false
        webViewID = UUID()
        openSubmittedURL(targetURL, recordsHistory: recordsHistory)
        return true
    }
}
