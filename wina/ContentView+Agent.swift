import SafariServices
import SwiftUI
import WebKit

@MainActor
extension ContentView {
    private static let browserTools = [
        AgentTool.definition("walnut_capabilities", "List Walnut tools, the current browser mode, and unavailable tools or actions for that mode."),
        AgentTool.definition("walnut_browser", "Read browser state, open or change the current URL, navigate history, use the callback test page, or wait for a selector.", [
            "action": [
                "type": "string",
                "enum": ["status", "open", "reload", "back", "forward", "initial", "home", "stop", "callback", "wait"]
            ],
            "url": ["type": "string", "description": "HTTP or HTTPS URL for open. Also changes the URL of the active page."],
            "mode": ["type": "string", "enum": ["wkwebview", "safarivc"]],
            "selector": ["type": "string"],
            "cleanStart": ["type": "boolean", "description": "Explicit WKWebView data reset. Requires approval."],
            "recordHistory": ["type": "boolean", "description": "Save this URL to Walnut history."],
            "timeout": ["type": "number", "minimum": 0.1, "maximum": 30]
        ], required: ["action"]),
        AgentTool.definition("walnut_panel", "Read, open or close native developer tool panels.", [
            "action": ["type": "string", "enum": ["status", "open", "close"]],
            "panel": ["type": "string", "enum": DevToolsOverlay.allCases.map(\.rawValue) + ["sources"]]
        ], required: ["action"])
    ]
    private static let agentTools = browserTools + AgentCapture.tools + AgentDevTools.tools + AgentSettings.tools

    static func agentCapabilities(safari: Bool, safariWindow: UIWindow? = nil) -> [String: Any] {
        let screenshotUnavailableReason = safari ? AgentCapture.safariScreenshotUnavailableReason(in: safariWindow) : nil
        var unavailable = AgentDevTools.tools.compactMap { $0["name"] as? String } + ["walnut_panel"]
        if screenshotUnavailableReason != nil { unavailable.append("walnut_screenshot") }
        let unavailableActions = [
            "walnut_browser": ["back", "forward", "initial", "stop", "wait"],
            "preload": ["clear_logs", "logs"],
        ]
        return [
            "tools": agentTools,
            "mode": safari ? "safarivc" : "wkwebview",
            "unavailable": safari ? unavailable.sorted() : [],
            "unavailableActions": safari ? unavailableActions : [:],
            "unavailableReasons": screenshotUnavailableReason.map { ["walnut_screenshot": $0] } ?? [:],
        ]
    }

    private var agentNavigation: AgentNavigation {
        useSafariWebView ? agentSafariNavigation : webViewNavigator.agentNavigation
    }

    private var agentMode: String { useSafariWebView ? "safarivc" : "wkwebview" }

    var ownedAgentRecorder: WebViewRecorder? {
        agentCaptureRecorder.flatMap { $0.isAgentCapture ? $0 : nil }
    }

    var canPresentAgentAnnouncement: Bool {
        agentScenePhase == .active && !showWebView && !showSettings && !showPreloadSettings && !showAbout
            && !showBookmarks && !showInfo && !showAgentConnection && !browserState.showsCallback
            && !showCleanStartOptionsChanged && !showSafariUnsupportedAlert && !textFieldFocused
    }

    func startAgentConnection(rememberedOnly: Bool) {
        agentSession.start(rememberedOnly: rememberedOnly, handler: { name, arguments in
            try await agentCall(name, arguments)
        }, onDisconnect: resetAgentSession)
    }

    func updateAgentConnection(for phase: ScenePhase) {
        if phase == .background {
            stopBackgroundSession()
        } else if phase == .active, UserDefaults.standard.bool(forKey: AgentSession.autoConnectKey) {
            startAgentConnection(rememberedOnly: true)
        }
    }

    func stopBackgroundSession() {
        agentSession.stop()
        stopSafariRecording()
    }

    func stopSafariRecording() {
        safariRecordingIndicator.update(captureView: nil, isRecording: false)
        screenRecorder.stopRecording()
    }

    func dismissAgentCallback() async throws -> Bool {
        try await browserState.sheetPresenter?.dismissCallbackResult() ?? false
    }

    private func resetAgentSession() {
        AgentEngineInspection.revoke(webViewNavigator)
        webViewNavigator.hideAgentPointer()
        if let recorder = ownedAgentRecorder {
            recorder.stopRecording()
            recorder.discardAgentRecording()
        }
        agentCaptureRecorder = nil
        webViewNavigator.agentLogSettings = AgentLogSettings()
        if let defaults = agentCaptureDefaults {
            webViewNavigator.consoleManager.isCapturing = defaults.console
            webViewNavigator.networkManager.isCapturing = defaults.network
            webViewNavigator.resourceManager.isCapturing = defaults.resources
        }
        agentCaptureDefaults = nil
        webViewNavigator.agentTrackingEnabled = false
        let settings = AgentBrowserSettings.shared
        let savedPrivate = UserDefaults.standard.bool(forKey: "privateBrowsing")
        let wasPrivate = settings.isolatesPreloadCookies || settings.value("privateBrowsing", fallback: savedPrivate)
        if showWebView && !useSafariWebView && wasPrivate && !savedPrivate {
            returnHome()
        }
        let rebuild = settings.browserRevision(safari: useSafariWebView)
        settings.reset()
        if rebuild == settings.browserRevision(safari: useSafariWebView) {
            if showWebView && !useSafariWebView {
                webViewNavigator.installEmulation(configScript: WebViewScripts.emulationConfigScript(agentSettings: nil))
            }
            return
        }
        if useSafariWebView {
            if (try? requireSafariPresentationAvailable()) != nil { recreateAgentBrowser() }
        } else if !agentSession.isRunning {
            recreateAgentBrowser()
        }
    }

    private func agentCall(_ name: String, _ arguments: [String: Any]) async throws -> Any {
        guard !Task.isCancelled else { throw CancellationError() }
        if agentCaptureDefaults == nil {
            agentCaptureDefaults = (
                webViewNavigator.consoleManager.isCapturing,
                webViewNavigator.networkManager.isCapturing,
                webViewNavigator.resourceManager.isCapturing
            )
        }
        guard let tool = Self.agentTools.first(where: { $0["name"] as? String == name }) else {
            throw AgentError("Unknown Walnut tool.")
        }
        if name == "menus", let menu = arguments["menu"] as? String,
           ["safari_toolbar", "safari_app_bar"].contains(menu) {
            throw AgentError("SafariVC uses Safari’s system toolbar. Walnut menu layout settings apply to WKWebView.")
        }
        try AgentTool.validate(arguments, using: tool)
        if name == "walnut_screenshot" {
            var envelope = agentPageEvidence()
            let screenshot = try await agentScreenshot(saveToPhotos: arguments["saveToPhotos"] as? Bool ?? false, evidence: envelope)
            envelope["data"] = screenshot
            return envelope
        }
        let pageAction = name == "page_interact" && ["scroll", "click", "fill", "select", "move", "click_at", "press"].contains(arguments["action"] as? String ?? "")
        let logExport = ["console_list", "network_list"].contains(name) && ["text", "json"].contains(arguments["format"] as? String ?? "")
        let fixedTarget = pageAction || logExport || ["storage_write", "storage_clear"].contains(name) ? agentPageEvidence() : nil
        let result = try await performAgentCall(name, arguments)
        var envelope = fixedTarget ?? agentPageEvidence()
        if name == "performance_read", let measurement = result as? [String: Any],
           let measuredDocument = measurement["documentId"] as? String,
           measuredDocument != envelope["documentId"] as? String {
            throw AgentError("The active WKWebView document changed. Try again.")
        }
        envelope["data"] = result
        return envelope
    }

    private func agentPageEvidence() -> [String: Any] {
        let navigation = agentNavigation
        let hasSafariDismissal = useSafariWebView && navigation.phase == "dismissed"
        let evidence: [String: Any] = showWebView || hasSafariDismissal ? navigation.evidence : ["phase": "idle"]
        var envelope: [String: Any] = ["runId": navigation.runID.uuidString, "mode": agentMode]
        envelope["navigation"] = evidence
        if let document = navigation.documentID, showWebView {
            envelope["documentId"] = document.uuidString
        }
        if showWebView {
            var settings = AgentSettings.configuredBrowserSettings(safari: useSafariWebView)
            if useSafariWebView, let controller = navigation.captureController as? SFSafariViewController {
                settings["safariEntersReaderIfAvailable"] = controller.configuration.entersReaderIfAvailable
                settings["safariBarCollapsingEnabled"] = controller.configuration.barCollapsingEnabled
            } else if !useSafariWebView {
                settings["privateBrowsing"] = effectivePrivateBrowsing
                envelope["userAgentOverride"] = webViewNavigator.agentEffectiveUserAgent
                envelope["webViewState"] = webViewNavigator.agentWebViewState
                if webViewNavigator.emulationNeedsNavigation { envelope["emulationNeedsNavigation"] = true }
            }
            envelope["configuredBrowserSettings"] = settings
        }
        return envelope
    }

    private func performAgentCall(_ name: String, _ arguments: [String: Any]) async throws -> Any {
        switch name {
        case "walnut_capabilities":
            return Self.agentCapabilities(safari: useSafariWebView, safariWindow: showWebView ? agentSafariNavigation.captureView?.window : nil)
        case "walnut_browser":
            return try await agentBrowser(arguments)
        case "walnut_panel":
            return try agentPanel(arguments)
        case "callbacks" where arguments["action"] as? String == "dismiss":
            return ["dismissed": try await dismissAgentCallback()]
        case "walnut_recording":
            return try await agentRecording(arguments)
        default:
            if AgentSettings.tools.contains(where: { $0["name"] as? String == name }) {
                return try await callAgentSettings(name, arguments)
            }
            try requireWKWebView()
            return try await AgentDevTools.call(
                name, arguments: arguments, navigator: webViewNavigator, storage: storageManager,
                console: consoleSession, authorize: agentSession.authorize
            )
        }
    }

    private func callAgentSettings(_ name: String, _ arguments: [String: Any]) async throws -> Any {
        let safariRevision = showWebView && useSafariWebView ? webViewID : nil
        let changesSettings = name == "settings_apply" || name == "settings_reset"
        if safariRevision != nil, changesSettings {
            try requireSafariPresentationAvailable()
        }
        let wkNavigator = showWebView && !useSafariWebView ? webViewNavigator : nil
        let wkRevision = webViewID
        let wkDocument = wkNavigator?.documentID
        let previous = agentNavigation.runID
        let settings = AgentBrowserSettings.shared
        let rebuildID = settings.browserRevision(safari: useSafariWebView)
        let wasPrivate = effectivePrivateBrowsing
        let result = try await AgentSettings.call(
            name, arguments: arguments, navigator: wkNavigator,
            validateApplyTarget: {
                if let safariRevision {
                    guard showWebView, useSafariWebView, webViewID == safariRevision else {
                        throw AgentError("The SafariVC page changed while approving the settings. Try again.")
                    }
                    try requireSafariPresentationAvailable()
                } else if let wkNavigator {
                    guard showWebView, !useSafariWebView, webViewID == wkRevision,
                          webViewNavigator === wkNavigator, wkNavigator.documentID == wkDocument,
                          agentNavigation.runID == previous else {
                        throw AgentError("The WKWebView page changed while approving the settings. Try again.")
                    }
                }
            },
            authorize: agentSession.authorize
        )
        var reloaded = false
        closeWKPageIfPrivacyEnded(wasPrivate: wasPrivate)
        if showWebView, settings.browserRevision(safari: useSafariWebView) != rebuildID {
            if useSafariWebView { recreateAgentBrowser() }
            try await waitForAgentNavigation(previous: previous, timeout: 15)
        } else if showWebView && !useSafariWebView {
            webViewNavigator.applyAgentUserAgent()
            if AgentSettings.changesEmulation(name, arguments: arguments) {
                let script = WebViewScripts.emulationConfigScript(agentSettings: settings)
                if let expected = webViewNavigator.applyEmulation(configScript: script, onlyReloadSafeRequest: true) {
                    reloaded = true
                    try await waitForAgentNavigation(previous: previous, timeout: 15, expected: expected)
                }
            }
        }
        guard changesSettings, var metadata = result as? [String: Any] else { return result }
        metadata["browserReloadRequested"] = reloaded
        return metadata
    }

    private func requireWKWebView() throws {
        guard !useSafariWebView else {
            throw AgentError("SafariVC does not expose this operation. Open a page in WKWebView mode.")
        }
        guard showWebView, webViewNavigator.isAttached else { throw AgentError("Open a WKWebView page first.") }
    }

    private func agentPanel(_ arguments: [String: Any]) throws -> [String: Any] {
        try requireWKWebView()
        if arguments["action"] as? String != "status" {
            guard let panel = arguments["panel"] as? String,
                  let overlay = DevToolsOverlay(rawValue: panel == "sources" ? "editor" : panel) else {
                throw AgentError("Specify a developer tool panel.")
            }
            if arguments["action"] as? String == "open" {
                devToolsState.open(overlay)
            } else {
                devToolsState.close(overlay)
            }
        }
        return ["open": devToolsState.active.map(\.rawValue).sorted(), "docked": devToolsState.isDocked]
    }

    private func agentBrowser(_ arguments: [String: Any]) async throws -> [String: Any] {
        let action = arguments["action"] as? String ?? "status"
        let timeout = arguments["timeout"] as? Double ?? 15
        let previousRun = agentNavigation.runID
        switch action {
        case "status":
            break
        case "home":
            if showWebView && useSafariWebView { try requireSafariPresentationAvailable() }
            returnHome()
        case "open", "callback":
            let previousURL = !useSafariWebView && showWebView ? webViewNavigator.currentURL : nil
            let (previous, expected) = try await openAgentURL(arguments, callback: action == "callback")
            try await waitForAgentNavigation(previous: previous, timeout: timeout, expected: expected, previousURL: previousURL)
        case "wait":
            try await agentWaitForSelector(arguments["selector"] as? String, timeout: timeout)
        case "reload", "back", "forward", "initial", "stop":
            try await navigateAgentHistory(action, previous: previousRun, timeout: timeout)
        default:
            throw AgentError("Unknown browser action.")
        }
        var state: [String: Any] = [
            "open": showWebView,
            "canGoBack": !useSafariWebView && webViewNavigator.canGoBack,
            "canGoForward": !useSafariWebView && webViewNavigator.canGoForward
        ]
        if showWebView, !useSafariWebView, let url = webViewNavigator.currentURL {
            state["currentURL"] = AgentNavigation.redactedURL(url)
        }
        return state
    }

    private func openAgentURL(_ arguments: [String: Any], callback: Bool) async throws -> (UUID, WKNavigation?) {
        let settings = AgentBrowserSettings.shared
        let newSafari = callback || ((arguments["mode"] as? String).map { $0 == "safarivc" } ?? useSafariWebView)
        if newSafari || (showWebView && useSafariWebView) { try requireSafariPresentationAvailable() }
        let callbackPage = callback || (newSafari && settings.value("useCallbackTestPage", fallback: useCallbackTestPage))
        let candidate = callbackPage ? CallbackTestManager.testPageURL.absoluteString : arguments["url"] as? String ?? ""
        guard URLValidator.isValidURL(candidate),
              let url = URL(string: URLValidator.normalizeURL(candidate)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
            throw AgentError("Provide a valid HTTP or HTTPS URL.")
        }
        let recordsHistory = !callbackPage && arguments["recordHistory"] as? Bool == true
        let previous = newSafari ? agentSafariNavigation.runID : webViewNavigator.agentNavigation.runID
        let safariRevision = showWebView && useSafariWebView ? webViewID : nil
        var expected: WKNavigation?
        if arguments["cleanStart"] as? Bool == true {
            guard !newSafari, !isPreparingCleanStart else { throw AgentError("Clean Start requires an available WKWebView.") }
            guard await agentSession.authorize("Clear WKWebView website data and development logs before opening the URL?") else {
                throw AgentError("Clean Start was denied.")
            }
            try Task.checkCancellation()
            if let safariRevision {
                guard showWebView, useSafariWebView, webViewID == safariRevision else {
                    throw AgentError("The SafariVC page changed while approving Clean Start. Try again.")
                }
                try requireSafariPresentationAvailable()
            }
            guard !isPreparingCleanStart else { throw AgentError("Another Clean Start is in progress.") }
            isPreparingCleanStart = true
            guard await completeCleanStart(url.absoluteString, recordsHistory: recordsHistory) else {
                try Task.checkCancellation()
                throw AgentError("Browser options changed during Clean Start. Check the current settings and retry.")
            }
        } else if showWebView && useSafariWebView == newSafari && !callbackPage {
            let opened = navigateDisplayedURL(url.absoluteString, recordsHistory: recordsHistory) { expected = $0 }
            guard opened else { throw AgentError("Unsupported URL.") }
        } else {
            devToolsState.closeAll()
            useSafariWebView = newSafari
            webViewID = UUID()
            openSubmittedURL(url.absoluteString, recordsHistory: recordsHistory)
        }
        return (previous, expected)
    }

    private func navigateAgentHistory(_ action: String, previous: UUID, timeout: Double) async throws {
        if useSafariWebView && showWebView && action == "reload" {
            try requireSafariPresentationAvailable()
            webViewID = UUID()
            try await waitForAgentNavigation(previous: previous, timeout: timeout)
            return
        }
        try requireWKWebView()
        let previousURL = webViewNavigator.currentURL
        let expected: WKNavigation?
        switch action {
        case "reload":
            webViewNavigator.applyAgentUserAgent()
            expected = webViewNavigator.reload()
        case "back":
            guard webViewNavigator.canGoBack else { throw AgentError("No back history.") }
            expected = webViewNavigator.goBack()
        case "forward":
            guard webViewNavigator.canGoForward else { throw AgentError("No forward history.") }
            expected = webViewNavigator.goForward()
        case "initial":
            guard webViewNavigator.initialURL != nil else { throw AgentError("No initial URL.") }
            expected = webViewNavigator.goToInitialURL()
        default:
            webViewNavigator.stopLoading()
            return
        }
        try await waitForAgentNavigation(
            previous: previous, timeout: timeout, expected: expected, previousURL: action == "reload" ? nil : previousURL
        )
    }

    private func waitForAgentNavigation(
        previous: UUID,
        timeout: Double,
        expected: WKNavigation? = nil,
        previousURL: URL? = nil
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(timeout)
        let safari = useSafariWebView
        while clock.now < deadline {
            try Task.checkCancellation()
            guard showWebView, useSafariWebView == safari else {
                throw AgentError("The browser changed before the requested load finished.")
            }
            let navigation = agentNavigation
            if navigation.runID != previous {
                if let expected, !navigation.matches(expected) {
                    throw AgentError("A different navigation interrupted the requested load.")
                }
                if navigation.isTerminal { return }
            } else if !useSafariWebView, let previousURL, let currentURL = webViewNavigator.currentURL,
                      currentURL != previousURL, !webViewNavigator.agentIsLoading {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw AgentError("Navigation timed out. Read browser status to check the current run.")
    }

    private func agentWaitForSelector(_ selector: String?, timeout: Double) async throws {
        try requireWKWebView()
        guard let selector, !selector.isEmpty,
              let encoded = try? JSONEncoder().encode(selector),
              let quoted = String(data: encoded, encoding: .utf8) else {
            throw AgentError("Provide a CSS selector.")
        }
        let document = webViewNavigator.documentID
        if selector.range(of: #"^#[a-zA-Z][a-zA-Z0-9_-]*$"#, options: .regularExpression) == nil {
            guard await agentSession.authorize("Check the current page for elements matching this selector?\n\n" + selector) else {
                throw AgentError("Selector inspection was denied.")
            }
        }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(timeout)
        while clock.now < deadline {
            guard document == webViewNavigator.documentID else { throw AgentError("The page changed while waiting.") }
            let match = await webViewNavigator.evaluateJavaScript("!!document.querySelector(\(quoted))") as? Bool == true
            try Task.checkCancellation()
            guard document == webViewNavigator.documentID else { throw AgentError("The page changed while waiting.") }
            if match { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw AgentError("Selector was not found before the timeout.")
    }

    private func agentScreenshot(saveToPhotos: Bool, evidence: [String: Any]) async throws -> [String: Any] {
        guard showWebView else { throw AgentError("Open a test page first.") }
        let safari = useSafariWebView
        let viewID = webViewID
        let runID = agentNavigation.runID
        let navigator = safari ? nil : webViewNavigator
        let documentID = navigator?.documentID
        let url = navigator?.attachedPageURL ?? agentNavigation.url
        let safariController = safari ? agentSafariNavigation.captureController : nil
        let safariView = safariController?.viewIfLoaded
        let safariWindow = safariView?.window
        if safari {
            if let reason = AgentCapture.safariScreenshotUnavailableReason(in: safariWindow) {
                throw AgentError(reason)
            }
            guard safariWindow != nil, agentNavigation.isTerminal else {
                throw AgentError("Wait for SafariVC to finish opening the test page.")
            }
        } else {
            try requireWKWebView()
            guard agentNavigation.documentID != nil, navigator?.agentIsLoading == false else {
                throw AgentError("Wait for the WKWebView test page to load.")
            }
        }

        @MainActor func validateTarget() throws {
            try Task.checkCancellation()
            let sameView = safari ? agentSafariNavigation.captureController === safariController && safariView?.window === safariWindow
                : webViewNavigator === navigator && navigator?.documentID == documentID && navigator?.agentIsLoading == false
            guard showWebView, useSafariWebView == safari, webViewID == viewID, agentNavigation.runID == runID, sameView,
                  (navigator?.attachedPageURL ?? agentNavigation.url) == url else {
                throw AgentError("The test page changed while approving or capturing the screenshot. Try again.")
            }
            if safariController?.presentedViewController != nil {
                throw AgentError("Close other Safari sheets before taking a screenshot.")
            }
        }

        let source: AgentCapture.ScreenshotSource
        if let safariWindow {
            source = .safariDisplay {
                try await AgentCapture.captureSafariDisplay(in: safariWindow, validateTarget: validateTarget)
            }
        } else if let navigator {
            source = .wkWebView(navigator)
        } else {
            throw AgentError("The test page is no longer visible.")
        }
        let photosNote = saveToPhotos ? " Walnut will also save the approved screenshot to Photos." : ""
        let prompt = safari ? "Capture one image of this device’s entire display with SafariVC visible? Approve in the iOS picker, then review the image before sharing."
            : "Share a screenshot of the WKWebView test page with the connected Mac and its agent?" + photosNote
        guard await agentSession.authorize(prompt) else {
            throw AgentError("Screenshot capture was denied in Walnut.")
        }
        return try await AgentCapture.screenshot(source: source, saveToPhotos: saveToPhotos, evidence: evidence) { image in
            await agentSession.authorize("Share this display screenshot with the connected Mac and its agent?" + photosNote, preview: image)
        } validateTarget: {
            try validateTarget()
        }
    }

    private func agentRecording(_ arguments: [String: Any]) async throws -> Any {
        let save = arguments["saveToPhotos"] as? Bool ?? false

        let ownedRecorder = ownedAgentRecorder
        let recorder = ownedRecorder ?? (useSafariWebView ? screenRecorder : webViewNavigator.recorder)
        switch arguments["action"] as? String {
        case "start":
            guard showWebView else { throw AgentError("Open a test page first.") }
            let revision = webViewID
            let safari = useSafariWebView
            let photosNote = save ? " Walnut will also save the video to Photos." : ""
            let prompt = "Record the app screen and share the video with the connected Mac and its agent?"
            let systemNote = " If iOS asks separately, approve screen capture on the iPhone."
            guard await agentSession.authorize(prompt + systemNote + photosNote) else {
                throw AgentError("Recording was denied.")
            }
            if save { try await AgentCapture.requirePhotos() }
            try Task.checkCancellation()
            guard showWebView, webViewID == revision, useSafariWebView == safari else {
                throw AgentError("The test page changed while approving the recording. Try again.")
            }
            if safari {
                guard let controller = agentSafariNavigation.captureController, controller.viewIfLoaded?.window != nil,
                      controller.presentedViewController == nil else {
                    throw AgentError("Open SafariVC and close other sheets before recording.")
                }
            }
            let activeRecorder = useSafariWebView ? screenRecorder : webViewNavigator.recorder
            guard activeRecorder.state == .idle, (ownedRecorder?.state ?? .idle) == .idle else {
                throw AgentError("A screen recording is already active.")
            }
            guard let start = activeRecorder.beginRecording(retainForAgent: true, saveToPhotos: save) else {
                throw AgentError(activeRecorder.startFailure ?? "Recording could not start.")
            }
            if ownedRecorder !== activeRecorder { ownedRecorder?.discardAgentRecording() }
            agentCaptureRecorder = activeRecorder
            if arguments["waitForStart"] as? Bool != false {
                let started = await start.value
                try Task.checkCancellation()
                if !started {
                    let detail = activeRecorder.startFailure.map { ": \($0)" } ?? "."
                    throw AgentError("Recording could not start\(detail)")
                }
            }
            return AgentCapture.recordingStatus(activeRecorder)
        case "stop":
            guard let ownedRecorder else { throw AgentError("No agent recording to stop.") }
            ownedRecorder.stopRecording()
        case "read":
            guard let ownedRecorder else { throw AgentError("No agent recording to read.") }
            return try AgentCapture.readRecording(ownedRecorder, offset: arguments["offset"] as? Int ?? 0)
        case "status" where agentCaptureRecorder != nil && ownedRecorder == nil:
            return [
                "state": "idle", "duration": 0, "available": false,
                "error": "A local recording replaced the agent recording."
            ] as [String: Any]
        default:
            break
        }
        return AgentCapture.recordingStatus(recorder)
    }
}
