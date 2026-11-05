//
//  WKWebViewCoordinator.swift
//  wina
//
//  Coordinator for WKWebViewRepresentable handling navigation and script messages.
//

import OSLog
import SwiftUI
import WebKit

// MARK: - WKWebView Coordinator

class WKWebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    @Binding var isLoading: Bool
    let navigator: WebViewNavigator?
    let preloadProfile: WebViewPreloadProfile

    private var loadingObservation: NSKeyValueObservation?
    private weak var webView: WKWebView?
    // 마지막으로 커밋된 메인 프레임 URL을 기준점으로 사용합니다.
    private var lastCommittedMainFrameURL: URL?
    // Apply the reload exception only to the navigation started by that policy decision.
    private var nextNavigationIsReload = false
    private var reloadNavigation: WKNavigation?
    // reload 직후 Eruda init을 다시 실행해야 하는지를 추적합니다.
    private var shouldForceErudaInitOnNextFinish: Bool = false
    // didFinish 연속 호출 시 이전 Eruda 동기화 작업을 취소하고 최신 작업만 유지합니다.
    private var erudaSyncTask: Task<Void, Never>?
    private var bridgeResponseGeneration = 0
    private var pendingBridgeResponseWorkItems: [UUID: DispatchWorkItem] = [:]
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "wina", category: "ConsoleBridge")

    var pendingBridgeResponseWorkItemCount: Int {
        pendingBridgeResponseWorkItems.count
    }

    init(
        isLoading: Binding<Bool>,
        navigator: WebViewNavigator?,
        preloadProfile: WebViewPreloadProfile = .empty
    ) {
        _isLoading = isLoading
        self.navigator = navigator
        self.preloadProfile = preloadProfile
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "consoleLog" {
            handleConsoleMessage(message)
        } else if message.name == "networkRequest" {
            handleNetworkMessage(message)
        } else if message.name == "resourceTiming" {
            handleResourceTimingMessage(message)
        } else if preloadProfile.enabledBridgeChannelNames.contains(message.name) {
            handlePreloadBridgeMessage(message)
        }
    }

    private func handlePreloadBridgeMessage(_ message: WKScriptMessage) {
        let bodyText = PreloadBridgeLogFormatter.truncated(
            toMessageString(message.body) ?? String(describing: message.body)
        )
        navigator?.preloadBridgeLogManager.add(
            channel: message.name,
            direction: .received,
            body: bodyText
        )

        // Captured window.postMessage: surface it in the normal Console tab with a distinct
        // badge. This is the only user-visible output of the capture toggle.
        if message.name == PreloadBridgeConstants.postMessageCaptureChannel {
            let dict = message.body as? [String: Any]
            let origin = dict?["origin"] as? String ?? "?"
            let dataText = PreloadBridgeLogFormatter.truncated(toMessageString(dict?["data"]) ?? bodyText)
            emitPreloadConsoleBadge(label: "📨 postMessage", background: "#5856D6", trailing: dataText, source: origin)
            return
        }

        // Show inbound bridge traffic in the Console as well.
        emitPreloadConsoleBadge(label: "📥 bridge", background: "#0D9488", trailing: bodyText, source: message.name)

        // Evaluate rules across ALL enabled channels with this name — duplicates are not silently
        // shadowed (the editor defaults every new channel to "request").
        let matchingChannels = preloadProfile.bridgeChannels.filter { $0.isEnabled && $0.name == message.name }
        guard !matchingChannels.isEmpty else { return }

        for channel in matchingChannels {
            for rule in channel.responseRules where rule.isEnabled && BridgeRuleMatcher.matches(rule.matcher, message: message.body) {
                let script = PreloadScriptBuilder.responseScript(
                    for: rule.response,
                    message: message.body,
                    channel: message.name
                )
                schedulePreloadBridgeResponse(script, channel: message.name, delayMilliseconds: rule.delayMilliseconds)
            }
        }
    }

    // Emits a Chrome-DevTools-style colored pill into the in-app Console by reusing the existing
    // %c styledSegments renderer. Native -> ConsoleManager only (no JS console.log), so it cannot
    // re-enter the page console hook. Respects ConsoleManager.isCapturing.
    private func emitPreloadConsoleBadge(label: String, background: String, trailing: String, source: String?) {
        let segments: [[String: Any]] = [
            ["text": " \(label) ", "color": "white", "backgroundColor": background, "isBold": true, "fontSize": 11],
            ["text": " \(trailing)", "color": "gray", "isBold": false, "fontSize": 12],
        ]
        navigator?.consoleManager.addLog(
            type: "log",
            message: "[\(label)] \(trailing)",
            source: source,
            styledSegments: segments
        )
    }

    func schedulePreloadBridgeResponse(
        _ script: String,
        channel: String,
        delayMilliseconds: Int
    ) {
        guard !script.isEmpty else { return }
        let generation = bridgeResponseGeneration
        let workItemID = UUID()

        let execute = { [weak self] in
            guard let self else { return }
            defer { self.pendingBridgeResponseWorkItems[workItemID] = nil }
            guard self.bridgeResponseGeneration == generation else { return }
            self.webView?.evaluateJavaScript(script)
            self.navigator?.preloadBridgeLogManager.add(
                channel: channel,
                direction: .responded,
                body: script
            )
            self.emitPreloadConsoleBadge(label: "📤 bridge", background: "#16A34A", trailing: "responded on \(channel)", source: channel)
        }

        if delayMilliseconds > 0 {
            let workItem = DispatchWorkItem(block: execute)
            pendingBridgeResponseWorkItems[workItemID] = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMilliseconds), execute: workItem)
        } else {
            execute()
        }
    }

    private func cancelPendingBridgeResponses() {
        bridgeResponseGeneration += 1
        pendingBridgeResponseWorkItems.values.forEach { $0.cancel() }
        pendingBridgeResponseWorkItems.removeAll()
    }

    func handleMainFrameNavigationStarted(from currentURL: URL?, to targetURL: URL?) {
        guard !Self.isSameDocumentNavigation(from: currentURL, to: targetURL) else { return }
        cancelPendingBridgeResponses()
    }

    private static func isSameDocumentNavigation(from currentURL: URL?, to targetURL: URL?) -> Bool {
        guard let currentURL, let targetURL else { return false }
        var currentComponents = URLComponents(url: currentURL, resolvingAgainstBaseURL: false)
        var targetComponents = URLComponents(url: targetURL, resolvingAgainstBaseURL: false)
        currentComponents?.fragment = nil
        targetComponents?.fragment = nil
        return currentComponents?.url == targetComponents?.url
    }

    private func handleNetworkMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              let requestId = body["id"] as? String else {
            return
        }

        switch action {
        case "start":
            let method = body["method"] as? String ?? "GET"
            let url = body["url"] as? String ?? ""
            let requestType = body["type"] as? String ?? "other"
            let headers = toStringDictionary(body["headers"])
            let requestBody = toMessageString(body["body"])
            navigator?.networkManager.addRequest(
                id: requestId,
                method: method,
                url: url,
                requestType: requestType,
                headers: headers,
                body: requestBody
            )

        case "complete":
            let status = body["status"] as? Int
            let statusText = toMessageString(body["statusText"])
            let headers = toStringDictionary(body["headers"])
            let responseBody = toMessageString(body["body"])
            let requestBody = toMessageString(body["requestBody"])
            navigator?.networkManager.updateRequest(
                id: requestId,
                status: status,
                statusText: statusText,
                responseHeaders: headers,
                responseBody: responseBody,
                error: nil,
                requestBody: requestBody
            )

        case "error":
            let error = toMessageString(body["error"])
            let requestBody = toMessageString(body["requestBody"])
            navigator?.networkManager.updateRequest(
                id: requestId,
                status: nil,
                statusText: nil,
                responseHeaders: nil,
                responseBody: nil,
                error: error,
                requestBody: requestBody
            )

        case "requestBody":
            let requestBody = toMessageString(body["body"])
            navigator?.networkManager.updateRequestBody(
                id: requestId,
                requestBody: requestBody
            )

        default:
            break
        }
    }

    // JavaScript bridge payload를 안정적으로 문자열로 정규화합니다.
    private func toMessageString(_ raw: Any?) -> String? {
        guard let raw else { return nil }
        if raw is NSNull { return nil }
        if let text = raw as? String { return text }
        if JSONSerialization.isValidJSONObject(raw),
           let jsonData = try? JSONSerialization.data(withJSONObject: raw),
           let jsonText = String(data: jsonData, encoding: .utf8) {
            return jsonText
        }
        if let number = raw as? NSNumber {
            return number.stringValue
        }
        return String(describing: raw)
    }

    // JavaScript object 형태 헤더를 [String: String]으로 변환합니다.
    private func toStringDictionary(_ raw: Any?) -> [String: String]? {
        guard let raw = raw as? [String: Any] else { return nil }
        var converted: [String: String] = [:]
        for (key, value) in raw where !(value is NSNull) {
            if let text = value as? String {
                converted[key] = text
            } else if let number = value as? NSNumber {
                converted[key] = number.stringValue
            } else {
                converted[key] = String(describing: value)
            }
        }
        return converted.isEmpty ? nil : converted
    }

    private func handleResourceTimingMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }

        if action == "entries", let entries = body["entries"] as? [[String: Any]] {
            navigator?.resourceManager.addResources(from: entries)
        }
    }

    func observeWebView(_ webView: WKWebView) {
        self.webView = webView
        // 최초 기준 URL을 저장해 Same Origin 비교에 사용합니다.
        lastCommittedMainFrameURL = webView.url

        loadingObservation = webView.observe(\.isLoading, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.isLoading = webView.isLoading
            }
        }
    }

    func invalidateObservation() {
        loadingObservation?.invalidate()
        loadingObservation = nil
        webView = nil
        cancelPendingBridgeResponses()
        erudaSyncTask?.cancel()
        erudaSyncTask = nil
        shouldForceErudaInitOnNextFinish = false
        nextNavigationIsReload = false
        reloadNavigation = nil
    }

    // MARK: - Clear Strategy

    private func applyClearStrategies(currentURL: URL?, newURL: URL?) {
        let resolver = LogClearStrategyResolver()
        let strategies = resolver.resolveStrategies()

        if LogClearStrategyResolver.shouldClear(strategy: strategies.console, currentURL: currentURL, newURL: newURL) {
            navigator?.consoleManager.clear()
        }

        if LogClearStrategyResolver.shouldClear(strategy: strategies.network, currentURL: currentURL, newURL: newURL) {
            navigator?.networkManager.clearForNavigation(preserving: pendingDocumentRequestId)
            navigator?.resourceManager.clear()
        }
    }

    private func resetActiveSnippets() {
        navigator?.snippetsManager.resetActiveSnippets()
    }

    // refresh 전략(보존/clear + Eruda force-init + snippet reset)을 공통으로 적용합니다.
    func prepareForManualReloadRequest() {
        navigator?.consoleManager.clearIfNotPreserved()
        navigator?.networkManager.clearIfNotPreserved()
        navigator?.resourceManager.clearIfNotPreserved()
        resetActiveSnippets()
        scheduleForceErudaInitOnNextFinish()
    }

    // reload 이후 다음 didFinish에서 Eruda 강제 재초기화를 예약합니다.
    func scheduleForceErudaInitOnNextFinish() {
        shouldForceErudaInitOnNextFinish = true
    }

    // Track pending document request (only one at a time for main frame)
    private var pendingDocumentRequestId: String?

    // Handle navigation actions (link clicks, reload, etc.)
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let isMainFrameNavigation = navigationAction.targetFrame?.isMainFrame ?? true
        if isMainFrameNavigation {
            handleMainFrameNavigationStarted(from: webView.url, to: navigationAction.request.url)
        }

        // Handle reload: use preserveLog setting
        if navigationAction.targetFrame?.isMainFrame == true {
            nextNavigationIsReload = navigationAction.navigationType == .reload
            if nextNavigationIsReload { prepareForManualReloadRequest() }
        }

        // Track document navigation for main frame only
        if navigationAction.targetFrame?.isMainFrame == true,
           let url = navigationAction.request.url?.absoluteString {

            // If there's already a pending request, it must be a redirect
            // Mark it as 302 before creating the new request
            if let previousId = pendingDocumentRequestId {
                navigator?.networkManager.updateRequest(
                    id: previousId,
                    status: 302,
                    statusText: "Redirect",
                    responseHeaders: nil,
                    responseBody: nil,
                    error: nil
                )
            }

            // Create new request
            let requestId = UUID().uuidString
            pendingDocumentRequestId = requestId

            navigator?.networkManager.addRequest(
                id: requestId,
                method: navigationAction.request.httpMethod ?? "GET",
                url: url,
                requestType: "document",
                headers: nil,
                body: nil
            )
        }

        // Allow default WKWebView behavior (including universal links opening external apps)
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if nextNavigationIsReload { reloadNavigation = navigation }
        nextNavigationIsReload = false
    }

    // Get response status and headers for document navigation
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        // Update document request with response info
        if navigationResponse.isForMainFrame,
           let requestId = pendingDocumentRequestId,
           let httpResponse = navigationResponse.response as? HTTPURLResponse {
            var headers: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                headers[String(describing: key)] = String(describing: value)
            }

            navigator?.networkManager.updateRequest(
                id: requestId,
                status: httpResponse.statusCode,
                statusText: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                responseHeaders: headers.isEmpty ? nil : headers,
                responseBody: nil,
                error: nil
            )
        }
        decisionHandler(.allow)
    }

    // Mark document navigation as complete
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pendingDocumentRequestId = nil

        // 새로고침 force-init 플래그를 취소된 Task가 소거하지 않도록 완료 시점에만 해제합니다.
        let forceInit = shouldForceErudaInitOnNextFinish
        erudaSyncTask?.cancel()
        erudaSyncTask = Task { [weak self, weak navigator] in
            await navigator?.syncErudaWithSettings(forceInit: forceInit)
            guard forceInit, !Task.isCancelled else { return }
            await MainActor.run {
                self?.shouldForceErudaInitOnNextFinish = false
            }
        }
    }

    // 메인 문서가 실제로 커밋된 시점의 URL로 clear 전략을 적용합니다.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        cancelPendingBridgeResponses()
        let committedURL = webView.url

        if let navigation, navigation === reloadNavigation {
            reloadNavigation = nil
            lastCommittedMainFrameURL = committedURL
            return
        }

        applyClearStrategies(
            currentURL: lastCommittedMainFrameURL,
            newURL: committedURL
        )
        resetActiveSnippets()
        lastCommittedMainFrameURL = committedURL
    }

    // Handle document navigation failure
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if let requestId = pendingDocumentRequestId {
            navigator?.networkManager.updateRequest(
                id: requestId,
                status: nil,
                statusText: nil,
                responseHeaders: nil,
                responseBody: nil,
                error: error.localizedDescription
            )
        }
        pendingDocumentRequestId = nil
        // reload 실패 시 다음 정상 탐색에 force-init이 남지 않도록 정리합니다.
        if let navigation, navigation === reloadNavigation { reloadNavigation = nil }
        shouldForceErudaInitOnNextFinish = false
    }

    // Handle provisional navigation failure
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if let requestId = pendingDocumentRequestId {
            navigator?.networkManager.updateRequest(
                id: requestId,
                status: nil,
                statusText: nil,
                responseHeaders: nil,
                responseBody: nil,
                error: error.localizedDescription
            )
        }
        pendingDocumentRequestId = nil
        // provisional 실패도 동일하게 force-init 플래그를 정리합니다.
        if let navigation, navigation === reloadNavigation { reloadNavigation = nil }
        shouldForceErudaInitOnNextFinish = false
    }

    // Handle new window requests (target="_blank")
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Load in same webView instead of opening new window
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // Handle JavaScript alerts
    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            completionHandler()
        }))
        if !presentAlertController(alertController, from: webView) {
            completionHandler()
        }
    }

    // Handle JavaScript confirms
    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            completionHandler(true)
        }))
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            completionHandler(false)
        }))
        if !presentAlertController(alertController, from: webView) {
            completionHandler(false)
        }
    }

    // Handle JavaScript prompts
    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alertController = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.text = defaultText
        }
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak alertController] _ in
            completionHandler(alertController?.textFields?.first?.text)
        }))
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            completionHandler(nil)
        }))
        if !presentAlertController(alertController, from: webView) {
            completionHandler(nil)
        }
    }

    private func presentAlertController(_ alertController: UIAlertController, from webView: WKWebView) -> Bool {
        guard let window = webView.window,
              window.windowScene?.activationState == .foregroundActive,
              let rootViewController = window.rootViewController else { return false }
        // Find topmost presented view controller
        var topVC = rootViewController
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        guard topVC.viewIfLoaded?.window === window,
              !topVC.isBeingDismissed, !topVC.isBeingPresented else { return false }
        topVC.present(alertController, animated: true)
        return true
    }

    deinit {
        invalidateObservation()
    }
}
