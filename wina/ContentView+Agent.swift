import SwiftUI
import WebKit

@MainActor
extension ContentView {
    private static let browserTools = [
        AgentTool.definition("walnut_capabilities", "List available Walnut MCP tools and the current browser mode."),
        AgentTool.definition("walnut_browser", "Read browser state, open or navigate a page, use the callback test page, or wait for a selector.", [
            "action": [
                "type": "string",
                "enum": ["status", "open", "reload", "back", "forward", "initial", "home", "stop", "callback", "wait"]
            ],
            "url": ["type": "string"],
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

    private var agentNavigation: AgentNavigation {
        useSafariWebView ? agentSafariNavigation : webViewNavigator.agentNavigation
    }

    private var agentMode: String { useSafariWebView ? "safarivc" : "wkwebview" }

    func startAgentConnection() {
        agentSession.start(handler: { name, arguments in
            try await agentCall(name, arguments)
        }, onDisconnect: resetAgentSession)
    }

    private func resetAgentSession() {
        agentCaptureRecorder?.stopRecording()
        agentCaptureRecorder?.discardAgentRecording()
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
        if !agentSession.isRunning && rebuild != settings.browserRevision(safari: useSafariWebView) { recreateAgentBrowser() }
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
        let tools = Self.browserTools + AgentCapture.tools + AgentDevTools.tools + AgentSettings.tools
        guard let tool = tools.first(where: { $0["name"] as? String == name }) else {
            throw AgentError("Unknown Walnut tool.")
        }
        try AgentTool.validate(arguments, using: tool)
        let pageAction = name == "page_interact" && ["click", "fill"].contains(arguments["action"] as? String ?? "")
        let fixedTarget = pageAction || ["walnut_screenshot", "storage_write", "storage_clear"].contains(name) ? agentPageEvidence() : nil
        let result = try await performAgentCall(name, arguments, tools: tools)
        var envelope = fixedTarget ?? agentPageEvidence()
        envelope["data"] = result
        return envelope
    }

    private func agentPageEvidence() -> [String: Any] {
        let navigation = agentNavigation
        let evidence: [String: Any] = showWebView ? navigation.evidence : ["phase": "idle"]
        var envelope: [String: Any] = ["runId": navigation.runID.uuidString, "mode": agentMode]
        envelope["navigation"] = evidence
        if let document = navigation.documentID, showWebView {
            envelope["documentId"] = document.uuidString
        }
        if let userAgent = webViewNavigator.agentEffectiveUserAgent, !useSafariWebView, showWebView {
            envelope["userAgentOverride"] = userAgent
        }
        return envelope
    }

    private func performAgentCall(_ name: String, _ arguments: [String: Any], tools: [[String: Any]]) async throws -> Any {
        switch name {
        case "walnut_capabilities":
            let names = Set(AgentDevTools.tools.compactMap { $0["name"] as? String })
            return [
                "tools": tools,
                "mode": agentMode,
                "unavailable": useSafariWebView ? names.sorted() : []
            ]
        case "walnut_browser":
            return try await agentBrowser(arguments)
        case "walnut_panel":
            return try agentPanel(arguments)
        case "walnut_screenshot", "walnut_recording":
            return try await agentMedia(name, arguments)
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
        let previous = agentNavigation.runID
        let settings = AgentBrowserSettings.shared
        let rebuildID = settings.browserRevision(safari: useSafariWebView)
        let wasPrivate = effectivePrivateBrowsing
        let result = try await AgentSettings.call(
            name, arguments: arguments, navigator: showWebView && !useSafariWebView ? webViewNavigator : nil,
            authorize: agentSession.authorize
        )
        if showWebView && !useSafariWebView && wasPrivate && !effectivePrivateBrowsing {
            returnHome()
        }
        if showWebView, settings.browserRevision(safari: useSafariWebView) != rebuildID {
            try await waitForAgentNavigation(previous: previous, timeout: 15)
        } else if showWebView && !useSafariWebView {
            webViewNavigator.applyAgentUserAgent()
        }
        return result
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
        let callbackPage = callback || (newSafari && settings.value("useCallbackTestPage", fallback: useCallbackTestPage))
        let candidate = callbackPage ? CallbackTestManager.testPageURL.absoluteString : arguments["url"] as? String ?? ""
        guard URLValidator.isValidURL(candidate),
              let url = URL(string: URLValidator.normalizeURL(candidate)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
            throw AgentError("Provide a valid HTTP or HTTPS URL.")
        }
        let recordsHistory = !callbackPage && arguments["recordHistory"] as? Bool == true
        let previous = newSafari ? agentSafariNavigation.runID : webViewNavigator.agentNavigation.runID
        var expected: WKNavigation?
        if arguments["cleanStart"] as? Bool == true {
            guard !newSafari, !isPreparingCleanStart else { throw AgentError("Clean Start requires an available WKWebView.") }
            guard await agentSession.authorize("Clear WKWebView website data and development logs before opening the URL?") else {
                throw AgentError("Clean Start was denied.")
            }
            try Task.checkCancellation()
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

    private func agentScreenshot(saveToPhotos: Bool) async throws -> [String: Any] {
        guard showWebView else { throw AgentError("Open a test page first.") }
        let safari = useSafariWebView
        let viewID = webViewID
        let runID = agentNavigation.runID
        let navigator = safari ? nil : webViewNavigator
        let documentID = navigator?.documentID
        let url = navigator?.attachedPageURL ?? agentNavigation.url
        let safariView = safari ? agentSafariNavigation.captureView : nil
        let safariWindow = safariView?.window
        if safari {
            guard safariWindow != nil, agentNavigation.isTerminal else {
                throw AgentError("Wait for SafariVC to finish opening the test page.")
            }
        } else {
            try requireWKWebView()
            guard agentNavigation.documentID != nil, navigator?.agentIsLoading == false else {
                throw AgentError("Wait for the WKWebView test page to load.")
            }
        }

        let photosNote = saveToPhotos ? " Walnut will also save the approved screenshot to Photos." : ""
        let prompt = safari ? "Capture the Walnut app window with SafariVC for you to review before sharing?"
            : "Share a screenshot of the WKWebView test page with the connected Mac and its agent?" + photosNote
        guard await agentSession.authorize(prompt) else {
            throw AgentError("Screenshot sharing was denied.")
        }
        return try await AgentCapture.screenshot(
            navigator: navigator, safariWindow: safariWindow, saveToPhotos: saveToPhotos
        ) { image in
            await agentSession.authorize("Share this screenshot with the connected Mac and its agent?" + photosNote, preview: image)
        } validateTarget: {
            try Task.checkCancellation()
            let sameView = safari ? agentSafariNavigation.captureView === safariView && safariView?.window === safariWindow
                : webViewNavigator === navigator && navigator?.documentID == documentID && navigator?.agentIsLoading == false
            guard showWebView, useSafariWebView == safari, webViewID == viewID, agentNavigation.runID == runID, sameView,
                  (navigator?.attachedPageURL ?? agentNavigation.url) == url else {
                throw AgentError("The test page changed while approving or capturing the screenshot. Try again.")
            }
        }
    }

    private func agentMedia(_ name: String, _ arguments: [String: Any]) async throws -> Any {
        let save = arguments["saveToPhotos"] as? Bool ?? false
        if name == "walnut_screenshot" { return try await agentScreenshot(saveToPhotos: save) }

        let recorder = agentCaptureRecorder ?? (useSafariWebView ? screenRecorder : webViewNavigator.recorder)
        switch arguments["action"] as? String {
        case "start":
            guard showWebView else { throw AgentError("Open a test page first.") }
            let photosNote = save ? " Walnut will also save the video to Photos." : ""
            guard await agentSession.authorize("Record the app screen and share the video with the connected Mac and its agent?" + photosNote) else {
                throw AgentError("Recording was denied.")
            }
            if save { try await AgentCapture.requirePhotos() }
            try Task.checkCancellation()
            guard showWebView else { throw AgentError("Open a test page first.") }
            let activeRecorder = useSafariWebView ? screenRecorder : webViewNavigator.recorder
            guard activeRecorder.state == .idle, (agentCaptureRecorder?.state ?? .idle) == .idle else {
                throw AgentError("A screen recording is already active.")
            }
            if agentCaptureRecorder !== activeRecorder { agentCaptureRecorder?.discardAgentRecording() }
            agentCaptureRecorder = activeRecorder
            guard await activeRecorder.startRecording(retainForAgent: true, saveToPhotos: save) else {
                if agentCaptureRecorder === activeRecorder { agentCaptureRecorder = nil }
                throw AgentError("Recording could not start.")
            }
            return AgentCapture.recordingStatus(activeRecorder)
        case "stop":
            guard agentCaptureRecorder != nil else { throw AgentError("No agent recording to stop.") }
            recorder.stopRecording()
        case "read":
            guard agentCaptureRecorder != nil else { throw AgentError("No agent recording to read.") }
            return try AgentCapture.readRecording(recorder, offset: arguments["offset"] as? Int ?? 0)
        default:
            break
        }
        return AgentCapture.recordingStatus(recorder)
    }
}
