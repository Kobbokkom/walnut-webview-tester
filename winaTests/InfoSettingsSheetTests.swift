import SwiftUI
import WebKit
import XCTest

@testable import wina

final class InfoSettingsSheetTests: XCTestCase {
    func testSafariVCInfoViewUsesBindingForWebViewID() {
        var id = UUID()
        let binding = Binding(get: { id }, set: { id = $0 })
        var view = SafariVCInfoView(webViewID: binding)

        XCTAssertEqual(view.webViewID, id)

        let newID = UUID()
        view.webViewID = newID
        XCTAssertEqual(id, newID)
    }

    func testInfoViewStoresBindingsWhenProvided() {
        var id = UUID()
        var url = "https://example.com"
        let idBinding = Binding(get: { id }, set: { id = $0 })
        let urlBinding = Binding(get: { url }, set: { url = $0 })
        let view = InfoView(navigator: nil, webViewID: idBinding, loadedURL: urlBinding)

        XCTAssertEqual(view.webViewID?.wrappedValue, id)
        XCTAssertEqual(view.loadedURL?.wrappedValue, url)

        let newID = UUID()
        let newURL = "https://apple.com"
        view.webViewID?.wrappedValue = newID
        view.loadedURL?.wrappedValue = newURL

        XCTAssertEqual(id, newID)
        XCTAssertEqual(url, newURL)
    }

    func testLiveSettingsDescriptionCopy() {
        XCTAssertEqual(SettingsCopy.liveSettingsDescription.key, "Apply to save changes")
    }
}

@MainActor
final class EmulationRegressionTests: XCTestCase {
    func testEmulationUsesNativeBooleanMediaQueryEvaluation() async throws {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        await webView.loadHTMLStringAsync("<html><body>test</body></html>", baseURL: nil)
        _ = try await webView.evaluateJavaScript(WebViewScripts.emulationConfigScript(
            colorScheme: "dark", reducedMotion: true, highContrast: true, reducedTransparency: true))
        _ = try await webView.evaluateJavaScript(WebViewScripts.emulationBootstrap)
        let cases: [(String, Bool)] = [
            ("(prefers-color-scheme: dark)", true),
            ("not (prefers-color-scheme: dark)", false),
            ("(prefers-color-scheme: dark) and (min-width: 999999px)", false),
            ("(prefers-color-scheme: light), (min-width: 999999px)", false),
            ("(prefers-color-scheme: light) or (prefers-reduced-motion: reduce)", true),
            ("(  prefers-color-scheme : DARK  )", true),
            ("(prefers-color-scheme: dark) and (unknown-feature: yes)", false),
            ("(prefers-color-scheme: sepia)", false),
            ("screen and (prefers-contrast: more)", true),
            ("not (prefers-reduced-transparency: reduce)", false),
            ("(prefers-reduced-motion)", true),
            ("not (prefers-reduced-motion)", false),
            ("( prefers-contrast )", true),
            ("not (prefers-contrast)", false),
            ("(prefers-reduced-transparency)", true),
            ("not (prefers-reduced-transparency)", false)
        ]
        for (query, expected) in cases {
            let data = try JSONSerialization.data(withJSONObject: query, options: .fragmentsAllowed)
            let literal = try XCTUnwrap(String(data: data, encoding: .utf8))
            let result = try await webView.evaluateJavaScript("window.matchMedia(\(literal)).matches") as? Bool
            XCTAssertEqual(result, expected, query)
        }
        let isNative = try await webView.evaluateJavaScript("window.matchMedia('(prefers-color-scheme: dark)') instanceof MediaQueryList") as? Bool
        XCTAssertEqual(isNative, true)
        let media = try await webView.evaluateJavaScript("window.matchMedia('(prefers-color-scheme: dark)').media") as? String
        XCTAssertEqual(media, "(prefers-color-scheme: dark)")
    }
}

@MainActor
final class SharedInfoCacheRegressionTests: XCTestCase {
    private final class InfoNavigator: WebViewNavigator {
        var invalidatesDuringEvaluation = false
        var userAgent = "first session"

        override func evaluateJavaScript(_ script: String) async -> Any? {
            if invalidatesDuringEvaluation {
                await SharedInfoWebView.shared.setNavigator(self)
            }
            return ["browser": ["userAgent": userAgent]]
        }
    }

    func testLiveInfoPreservesPageStorage() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        await webView.loadHTMLStringAsync("<html><body>storage fixture</body></html>", baseURL: URL(string: "https://example.com"))
        _ = try await webView.evaluateJavaScript("""
        localStorage.setItem('__test__', 'local value');
        sessionStorage.setItem('__test__', 'session value');
        """)
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let shared = SharedInfoWebView.shared
        shared.setNavigator(navigator)
        defer { shared.setNavigator(nil); navigator.detach() }

        let info = await WebViewInfo.load { _ in }
        XCTAssertTrue(info.supportsLocalStorage)
        XCTAssertTrue(info.supportsSessionStorage)
        let values = try await webView.evaluateJavaScript("""
        [localStorage.getItem('__test__'), sessionStorage.getItem('__test__'), localStorage.length, sessionStorage.length]
        """) as? [NSObject]
        XCTAssertEqual(values, ["local value" as NSString, "session value" as NSString, NSNumber(value: 1), NSNumber(value: 1)])
    }

    func testLiveDisplayInfoHandlesUnrepresentableScreenDimensions() async throws {
        let webView = WKWebView(frame: .zero)
        await webView.loadHTMLStringAsync("<html><body>display fixture</body></html>", baseURL: nil)
        _ = try await webView.evaluateJavaScript("""
        Object.defineProperty(screen, 'width', { value: 1e30 });
        Object.defineProperty(screen, 'height', { value: 600 });
        Object.defineProperty(screen, 'availWidth', { value: -1e30 });
        true;
        """)
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let shared = SharedInfoWebView.shared
        shared.setNavigator(navigator)
        defer { shared.setNavigator(nil); navigator.detach() }

        let info = await DisplayInfo.load { _ in }
        XCTAssertEqual(info.screenWidth, "N/A")
        XCTAssertEqual(info.screenHeight, "600 px")
        XCTAssertEqual(info.availWidth, "N/A")
        XCTAssertEqual(info.aspectRatio, "N/A")
    }

    func testReopeningInfoClearsSameNavigatorCaches() async {
        let navigator = InfoNavigator()
        let webView = WKWebView(frame: .zero)
        navigator.attach(to: webView)
        let shared = SharedInfoWebView.shared
        shared.setNavigator(navigator)
        defer { shared.setNavigator(nil); navigator.detach() }
        let first = await WebViewInfo.load { _ in }
        XCTAssertEqual(first.userAgent, "first session")
        navigator.userAgent = "second session"
        shared.setNavigator(navigator)
        XCTAssertNil(shared.cachedWebViewInfo)
        let second = await WebViewInfo.load { _ in }
        XCTAssertEqual(second.userAgent, "second session")
    }

    func testInvalidatedLoadsCannotRepopulateNewSessionCaches() async {
        let navigator = InfoNavigator()
        let webView = WKWebView(frame: .zero)
        navigator.attach(to: webView)
        let shared = SharedInfoWebView.shared
        shared.setNavigator(navigator)
        defer { shared.setNavigator(nil); navigator.detach() }
        navigator.invalidatesDuringEvaluation = true
        _ = await WebViewInfo.load { _ in }
        XCTAssertNil(shared.cachedWebViewInfo)
        _ = await MediaCodecInfo.load { _ in }
        XCTAssertNil(shared.cachedCodecInfo)
        _ = await DisplayInfo.load { _ in }
        XCTAssertNil(shared.cachedDisplayInfo)
        _ = await AccessibilityInfo.load { _ in }
        XCTAssertNil(shared.cachedAccessibilityInfo)
        navigator.invalidatesDuringEvaluation = false
        _ = await WebViewInfo.load { _ in }
        _ = await MediaCodecInfo.load { _ in }
        _ = await DisplayInfo.load { _ in }
        _ = await AccessibilityInfo.load { _ in }
        XCTAssertNotNil(shared.cachedWebViewInfo)
        XCTAssertNotNil(shared.cachedCodecInfo)
        XCTAssertNotNil(shared.cachedDisplayInfo)
        XCTAssertNotNil(shared.cachedAccessibilityInfo)
    }
}

@MainActor
final class EmulationInstallationTests: XCTestCase {
    private final class LoadDelegate: WKWebViewCoordinator {
        var completion: (() -> Void)?
        var lastNavigation: WKNavigation?
        override func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            super.webView(webView, didFinish: navigation)
            lastNavigation = navigation
            let action = completion
            completion = nil
            action?()
        }
    }

    func testApplyReplacesInstalledConfigurationAndPreservesOtherHooks() async throws {
        let configuration = WKWebViewConfiguration()
        let controller = configuration.userContentController
        let before = WKUserScript(source: "window.__before = true;", injectionTime: .atDocumentStart, forMainFrameOnly: false)
        let original = WKUserScript(source: WebViewScripts.emulationConfigScript(colorScheme: "system", reducedMotion: false, highContrast: false, reducedTransparency: false), injectionTime: .atDocumentStart, forMainFrameOnly: false)
        let bootstrap = WKUserScript(source: WebViewScripts.emulationBootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        let after = WKUserScript(source: "window.__after = true;", injectionTime: .atDocumentStart, forMainFrameOnly: false)
        [before, original, bootstrap, after].forEach(controller.addUserScript)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 640), configuration: configuration)
        await webView.loadHTMLStringAsync("<html><body>test</body></html>", baseURL: nil)
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        defer { navigator.detach() }
        let delegate = LoadDelegate(isLoading: .constant(false), navigator: navigator)
        webView.navigationDelegate = delegate
        let loaded = expectation(description: "Emulation reload completed")
        delegate.completion = { loaded.fulfill() }
        let script = WebViewScripts.emulationConfigScript(colorScheme: "dark", reducedMotion: true, highContrast: true, reducedTransparency: true)
        let historyCount = webView.backForwardList.backList.count
        navigator.applyEmulation(configScript: script)
        XCTAssertEqual(controller.userScripts.count, 4)
        XCTAssertEqual(controller.userScripts.map(\.source), [before.source, script, bootstrap.source, after.source])
        await fulfillment(of: [loaded], timeout: 10)
        XCTAssertEqual(webView.backForwardList.backList.count, historyCount)
        let config = try await webView.evaluateJavaScript("window.__winaEmulationConfig.colorScheme") as? String
        XCTAssertEqual(config, "dark")
        let effects = try await webView.evaluateJavaScript("window.__before && window.__after && window.matchMedia('(prefers-reduced-motion: reduce)').matches && !!document.getElementById('wina-emulation-style')") as? Bool
        XCTAssertEqual(effects, true)
    }

    func testSessionEmulationReloadsExistingHistoryAndRestoresSavedSettings() async throws {
        let suite = "EmulationInstallationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("light", forKey: "emulationColorScheme")

        let settings = AgentBrowserSettings()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let controller = configuration.userContentController
        let savedScript = WebViewScripts.emulationConfigScript(agentSettings: nil, defaults: defaults)
        for script in [savedScript, WebViewScripts.emulationBootstrap] {
            controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let initial = folder.appendingPathComponent("initial.html")
        let current = folder.appendingPathComponent("current.html")
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        defer { webView.navigationDelegate = nil; navigator.detach() }
        let delegate = LoadDelegate(isLoading: .constant(false), navigator: navigator)
        webView.navigationDelegate = delegate
        for url in [initial, current] {
            try "<p>\(url.lastPathComponent)</p>".write(to: url, atomically: true, encoding: .utf8)
            let loaded = expectation(description: "Load \(url.lastPathComponent)")
            delegate.completion = { loaded.fulfill() }
            webView.loadFileURL(url, allowingReadAccessTo: folder)
            await fulfillment(of: [loaded], timeout: 10)
        }
        let history = webView.backForwardList.backList.map(\.url.lastPathComponent)
        XCTAssertEqual(history, [initial.lastPathComponent])

        let revision = settings.rebuildID
        let patch = try AgentSetting.validatePatch([
            "emulationColorScheme": "dark", "emulationReducedMotion": true,
            "emulationHighContrast": true, "emulationReducedTransparency": true,
        ], persist: false)
        settings.apply(patch, persist: false, defaults: defaults)
        let sessionScript = WebViewScripts.emulationConfigScript(agentSettings: settings, defaults: defaults)
        let applied = expectation(description: "Session emulation reload")
        delegate.completion = { applied.fulfill() }
        let applyNavigation = try XCTUnwrap(navigator.applyEmulation(configScript: sessionScript, onlyReloadSafeRequest: true))
        await fulfillment(of: [applied], timeout: 10)
        XCTAssertTrue(delegate.lastNavigation === applyNavigation)
        let oldRevision = navigator.emulationRevision
        XCTAssertFalse(navigator.emulationNeedsNavigation)
        XCTAssertNil(navigator.applyEmulation(configScript: sessionScript))
        let session = try await webView.evaluateJavaScript("Object.values(window.__winaEmulationConfig)") as? [AnyHashable]
        XCTAssertEqual(session, ["dark", true, true, true])

        navigator.documentDidChange(in: webView, requestMethod: "POST", emulationRevision: oldRevision)
        settings.reset()
        let restoredScript = WebViewScripts.emulationConfigScript(agentSettings: settings, defaults: defaults)
        XCTAssertEqual(restoredScript, savedScript)
        XCTAssertNil(navigator.applyEmulation(configScript: restoredScript, onlyReloadSafeRequest: true))
        XCTAssertTrue(navigator.emulationNeedsNavigation)
        let unchanged = try await webView.evaluateJavaScript("window.__winaEmulationConfig.colorScheme") as? String
        XCTAssertEqual(unchanged, "dark")
        navigator.documentDidChange(in: webView, requestMethod: "GET", emulationRevision: oldRevision)
        XCTAssertTrue(navigator.emulationNeedsNavigation)
        let restored = expectation(description: "Saved emulation reload")
        delegate.completion = { restored.fulfill() }
        let resetNavigation = try XCTUnwrap(navigator.applyEmulation(configScript: restoredScript, onlyReloadSafeRequest: true))
        await fulfillment(of: [restored], timeout: 10)
        XCTAssertTrue(delegate.lastNavigation === resetNavigation)
        XCTAssertFalse(navigator.emulationNeedsNavigation)
        let saved = try await webView.evaluateJavaScript("Object.values(window.__winaEmulationConfig)") as? [AnyHashable]
        XCTAssertEqual(saved, ["light", false, false, false])
        XCTAssertEqual(webView.url?.lastPathComponent, current.lastPathComponent)
        XCTAssertEqual(webView.backForwardList.backList.map(\.url.lastPathComponent), history)

        let back = expectation(description: "Back through preserved history")
        delegate.completion = { back.fulfill() }
        XCTAssertNotNil(navigator.goBack())
        await fulfillment(of: [back], timeout: 10)
        XCTAssertEqual(webView.url?.lastPathComponent, initial.lastPathComponent)
        XCTAssertTrue(navigator.emulationNeedsNavigation)

        let forward = expectation(description: "Forward through preserved history")
        delegate.completion = { forward.fulfill() }
        XCTAssertNotNil(navigator.goForward())
        await fulfillment(of: [forward], timeout: 10)
        XCTAssertEqual(webView.url?.lastPathComponent, current.lastPathComponent)
        XCTAssertTrue(navigator.emulationNeedsNavigation)
        XCTAssertEqual(settings.rebuildID, revision)

        let beforeStaging = try await webView.evaluateJavaScript("window.__winaEmulationConfig.colorScheme") as? String
        let beforeStagingNavigation = delegate.lastNavigation
        navigator.installEmulation(configScript: sessionScript)
        XCTAssertFalse(webView.isLoading)
        let afterStaging = try await webView.evaluateJavaScript("window.__winaEmulationConfig.colorScheme") as? String
        XCTAssertEqual(afterStaging, beforeStaging)
        XCTAssertTrue(delegate.lastNavigation === beforeStagingNavigation)

        let fresh = expectation(description: "Staged emulation runs on a new document")
        delegate.completion = { fresh.fulfill() }
        webView.loadFileURL(initial, allowingReadAccessTo: folder)
        await fulfillment(of: [fresh], timeout: 10)
        let staged = try await webView.evaluateJavaScript("window.__winaEmulationConfig.colorScheme") as? String
        XCTAssertEqual(staged, "dark")
        XCTAssertFalse(navigator.emulationNeedsNavigation)
    }

    func testOnlyEmulationChangesCanRetryPendingReload() {
        XCTAssertFalse(AgentSettings.changesEmulation("settings_apply", arguments: ["settings": ["pageZoom": 1.5]]))
        XCTAssertTrue(AgentSettings.changesEmulation("settings_apply", arguments: ["settings": ["emulationColorScheme": "dark"]]))
        XCTAssertFalse(AgentSettings.changesEmulation("settings_reset", arguments: ["keys": ["pageZoom"]]))
        XCTAssertTrue(AgentSettings.changesEmulation("settings_reset", arguments: ["keys": ["emulationReducedMotion"]]))
        XCTAssertTrue(AgentSettings.changesEmulation("settings_reset", arguments: [:]))
    }
}
