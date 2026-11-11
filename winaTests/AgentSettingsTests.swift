import WebKit
import XCTest
@testable import wina

@MainActor
final class AgentSettingsTests: XCTestCase {
    func testSafariSettingsDoNotRecreateWKWebView() throws {
        let settings = AgentBrowserSettings()
        let wk = settings.rebuildID
        let safari = settings.safariRebuildID
        let patch = try AgentSetting.validatePatch(["safariEntersReaderIfAvailable": true], persist: false)
        settings.apply(patch, persist: false)
        XCTAssertEqual(settings.rebuildID, wk)
        XCTAssertNotEqual(settings.safariRebuildID, safari)
    }

    func testSafariTintReportsActiveSettingsAndCompatibilityDefaultsSeparately() async throws {
        let settings = AgentBrowserSettings.shared
        let defaults = UserDefaults.standard
        let colors = ["safariControlTintColorHex": "#123456", "safariBarTintColorHex": "#ABCDEF"]
        let keys = colors.keys.sorted()
        let original = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            settings.reset(keys: keys + ["pageZoom"])
            for (key, value) in original { defaults.set(value, forKey: key) }
        }
        let supported: Bool
        if #available(iOS 26.0, *) { supported = false } else { supported = true }
        let before = settings.safariRebuildID

        if !supported {
            settings.apply(["pageZoom": 1.25], persist: false)
            let patch: [String: Any] = [keys[0]: "#FFFFFF", "pageZoom": 2.0]
            do {
                _ = try await AgentSettings.call(
                    "settings_apply", arguments: ["settings": patch],
                    navigator: nil, authorize: { _ in XCTFail("Invalid patch reached approval"); return false }
                )
                XCTFail("The patch applied an unavailable tint")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("unavailable on this iOS version"))
            }
            XCTAssertEqual(settings.value("pageZoom", fallback: 1.0), 1.25)
            XCTAssertEqual(settings.safariRebuildID, before)
        }

        let response = try await AgentSettings.call(
            "settings_apply", arguments: ["settings": colors, "persist": true], navigator: nil
        ) { prompt in
            XCTAssertEqual(prompt.contains("saved for older iOS versions"), !supported)
            return true
        }
        let applied = try XCTUnwrap(response as? [String: Any])
        XCTAssertEqual(applied["applied"] as? [String: String], supported ? colors : [:])
        XCTAssertEqual(applied["savedOnly"] as? [String: String], supported ? nil : colors)
        XCTAssertEqual(applied["browserRecreationRequested"] as? Bool, supported)
        XCTAssertEqual(settings.safariRebuildID != before, supported)

        let snapshot = try await AgentSettings.call("settings_get", arguments: [:], navigator: nil) { _ in false }
        let rows = try XCTUnwrap(snapshot as? [[String: Any]])
        let configured = AgentSettings.configuredBrowserSettings(safari: true)
        for (key, color) in colors {
            let row = try XCTUnwrap(rows.first { $0["key"] as? String == key })
            XCTAssertEqual(row["available"] as? Bool, supported)
            XCTAssertEqual(row["saved"] as? String, color)
            XCTAssertEqual(row["recreatesBrowser"] as? Bool, supported)
            if supported {
                XCTAssertEqual(row["value"] as? String, color)
                XCTAssertEqual(configured[key] as? String, color)
            } else {
                XCTAssertTrue(row["value"] is NSNull)
                XCTAssertNil(configured[key])
            }
        }

        let reset = try await AgentSettings.call(
            "settings_reset", arguments: ["keys": keys], navigator: nil
        ) { _ in false }
        XCTAssertEqual((reset as? [String: Any])?["browserRecreationRequested"] as? Bool, false)
        for (key, color) in colors { XCTAssertEqual(defaults.string(forKey: key), color) }
    }

    func testApplyRevalidatesBrowserAfterApprovalBeforeMutating() async throws {
        let settings = AgentBrowserSettings.shared
        let keys = ["cleanStart", "safariEntersReaderIfAvailable"]
        defer { settings.reset(keys: keys) }
        settings.apply(["safariEntersReaderIfAvailable": false], persist: false)
        let revision = settings.safariRebuildID
        var approved = false

        do {
            _ = try await AgentSettings.call(
                "settings_apply", arguments: ["settings": ["cleanStart": true, "safariEntersReaderIfAvailable": true]],
                navigator: nil,
                validateApplyTarget: {
                    XCTAssertTrue(approved)
                    throw AgentError("The callback sheet is open.")
                },
                authorize: { _ in
                    approved = true
                    return true
                }
            )
            XCTFail("Settings were applied after the Safari presentation became unavailable")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The callback sheet is open.")
        }
        XCTAssertEqual(settings.safariRebuildID, revision)
        XCTAssertFalse(settings.value("safariEntersReaderIfAvailable", fallback: false))
    }

    func testTemporaryPreloadCookiesIsolateWebsiteData() {
        let settings = AgentBrowserSettings()
        let profile = WebViewPreloadProfile(isEnabled: true, cookies: [PreloadCookie(name: "fixture", value: "1")])
        XCTAssertFalse(settings.isolatesPreloadCookies)
        settings.setPreloadProfile(profile, persist: false)
        XCTAssertTrue(settings.isolatesPreloadCookies)
        settings.reset()
        XCTAssertFalse(settings.isolatesPreloadCookies)
    }

    func testHomePreloadToggleChangesTemporaryProfileWithoutSavingIt() throws {
        let suite = "AgentSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = WebViewPreloadProfile(name: "On-device setup", isEnabled: false)
        let temporary = WebViewPreloadProfile(name: "Temporary setup", isEnabled: true, cookies: [PreloadCookie(name: "fixture", value: "1")])
        PreloadProfileStore.saveActiveProfile(saved, defaults: defaults)
        let settings = AgentBrowserSettings()
        settings.setPreloadProfile(temporary, persist: false, defaults: defaults)

        settings.setPreloadEnabledFromHome(false, defaults: defaults)
        var disabled = temporary
        disabled.isEnabled = false
        XCTAssertEqual(settings.preloadProfile(fallback: saved), disabled)
        XCTAssertFalse(settings.isolatesPreloadCookies)
        XCTAssertEqual(PreloadProfileStore.activeProfile(defaults: defaults), saved)

        settings.setPreloadEnabledFromHome(true, defaults: defaults)
        XCTAssertEqual(settings.preloadProfile(fallback: saved), temporary)
        XCTAssertTrue(settings.isolatesPreloadCookies)
        XCTAssertEqual(PreloadProfileStore.activeProfile(defaults: defaults), saved)
    }

    func testApplyingOnDevicePreloadDraftRequiresClosingThePrivateWKPage() throws {
        let suite = "AgentSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = WebViewPreloadProfile(name: "On-device setup", isEnabled: false)
        PreloadProfileStore.saveActiveProfile(saved, defaults: defaults)
        let settings = AgentBrowserSettings.shared
        defer { settings.reset() }
        settings.apply(["privateBrowsing": false], persist: false, defaults: defaults)
        settings.setPreloadProfile(.nativeBridgeDemoPreset, persist: false, defaults: defaults)
        let owner = ContentView()
        let session = owner.agentSession
        session.start(handler: { _, _ in true }, onDisconnect: {})
        defer { session.stop() }
        let browser = ContentView.BrowserState()
        browser.isOpen = true
        let wasPrivate = owner.effectivePrivateBrowsing
        XCTAssertTrue(wasPrivate)
        var state = PreloadProfileSettingsState()
        state.loadIfNeeded(activeProfile: { PreloadProfileStore.activeProfile(defaults: defaults) }, savedProfiles: { [] })

        state.applyCurrentProfile(defaults: defaults) { owner.applyPreloadProfileFromEditor($0, defaults: defaults) }
        XCTAssertTrue(browser.shouldCloseWKPageAfterPrivacyChange(wasPrivate: wasPrivate, isPrivate: owner.effectivePrivateBrowsing))
        XCTAssertEqual(settings.preloadProfile(fallback: saved), saved)
        XCTAssertEqual(PreloadProfileStore.activeProfile(defaults: defaults), saved)
        XCTAssertFalse(settings.isolatesPreloadCookies)

        settings.setPreloadEnabledFromHome(true, defaults: defaults)
        let active = PreloadProfileStore.activeProfile(defaults: defaults)
        XCTAssertTrue(active.isEnabled)
        XCTAssertEqual(active.id, saved.id)
    }

    func testUnpairedPreloadEditorKeepsAnotherWindowsTemporaryProfile() throws {
        let suite = "AgentSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AgentBrowserSettings.shared
        defer { settings.reset() }
        let temporary = WebViewPreloadProfile.nativeBridgeDemoPreset
        settings.setPreloadProfile(temporary, persist: false, defaults: defaults)
        let saved = WebViewPreloadProfile(name: "Other window draft", isEnabled: false)

        ContentView().applyPreloadProfileFromEditor(saved, defaults: defaults)

        XCTAssertEqual(PreloadProfileStore.activeProfile(defaults: defaults), saved)
        XCTAssertEqual(settings.preloadProfile(fallback: saved), temporary)
        XCTAssertTrue(settings.isolatesPreloadCookies)
    }

    func testSessionSettingsDoNotPersistAndResetRevealsSavedValue() throws {
        let suite = "AgentSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AgentBrowserSettings()
        let setting = try XCTUnwrap(AgentSetting.catalog["privateBrowsing"])
        defaults.set(false, forKey: setting.key)
        let patch = try AgentSetting.validatePatch([setting.key: true], persist: false)
        let originalID = settings.rebuildID

        settings.apply(patch, persist: false, defaults: defaults)

        XCTAssertTrue(settings.value(setting.key, fallback: false))
        XCTAssertFalse(defaults.bool(forKey: setting.key))
        XCTAssertNotEqual(settings.rebuildID, originalID)
        settings.reset()
        XCTAssertEqual(settings.effectiveValue(for: setting, defaults: defaults) as? Bool, false)
        XCTAssertFalse(settings.value(setting.key, fallback: false))
    }

    func testToolCatalogAndSettingsSnapshotEncodeAsJSON() async throws {
        XCTAssertTrue(JSONSerialization.isValidJSONObject(AgentSettings.tools))
        let result = try await AgentSettings.call("settings_get", arguments: [:], navigator: nil) { _ in false }
        XCTAssertTrue(JSONSerialization.isValidJSONObject(result))
        let keys = Set(try XCTUnwrap((result as? [[String: Any]])?.compactMap { $0["key"] as? String }))
        XCTAssertTrue(keys.isSuperset(of: ["elementFullscreenEnabled", "safariDismissButtonStyle", "emulationHighContrast"]))
    }

    func testBrowserEvidenceSettingsUseCurrentModeAndOverrides() {
        let settings = AgentBrowserSettings.shared
        let keys = ["allowsContentJavaScript", "safariDismissButtonStyle"]
        defer { settings.reset(keys: keys) }
        settings.apply(["allowsContentJavaScript": false, "safariDismissButtonStyle": 1], persist: false)

        let wk = AgentSettings.configuredBrowserSettings(safari: false)
        XCTAssertEqual(wk["allowsContentJavaScript"] as? Bool, false)
        XCTAssertNil(wk["safariDismissButtonStyle"])
        XCTAssertNil(wk["presentation"])
        XCTAssertNil(wk["cleanStart"])

        let safari = AgentSettings.configuredBrowserSettings(safari: true)
        XCTAssertEqual(safari["safariDismissButtonStyle"] as? Int, 1)
        XCTAssertEqual(safari["presentation"] as? String, "full_screen")
        XCTAssertNil(safari["allowsContentJavaScript"])
        XCTAssertNil(safari["useCallbackTestPage"])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(safari))
    }

    func testSafariOnlyAdvertisesSettingsAvailableInItsFullScreenPresentation() async throws {
        let removedDimensions = ["safariWidthRatio", "safariHeightRatio"]
        let report = try await AgentSettings.call("diagnostics", arguments: ["section": "safari"], navigator: nil) { _ in false }
        let diagnostics = try XCTUnwrap(report as? [String: Any])
        let safariSettings = try XCTUnwrap(diagnostics["settings"] as? [String: Any])
        XCTAssertEqual(diagnostics["presentation"] as? String, "full_screen")
        for key in removedDimensions {
            XCTAssertNil(safariSettings[key])
            XCTAssertThrowsError(try AgentSetting.validatePatch([key: 0.5], persist: false))
        }

        let menus = try XCTUnwrap(AgentSettings.tools.first { $0["name"] as? String == "menus" })
        for key in ["wk_toolbar", "wk_app_bar"] {
            XCTAssertNoThrow(try AgentTool.validate(["action": "get", "menu": key], using: menus))
        }
        for key in ["safari_toolbar", "safari_app_bar"] {
            XCTAssertThrowsError(try AgentTool.validate(["action": "get", "menu": key], using: menus))
        }
    }

    func testWebViewStateReportsAppliedZoomAndStore() throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.pageZoom = 1.5
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)

        let state = try XCTUnwrap(navigator.agentWebViewState)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(state))
        XCTAssertEqual(state["pageZoom"] as? CGFloat, 1.5)
        XCTAssertEqual(state["privateBrowsing"] as? Bool, true)
    }

    func testDisablingSiteProtectionsRequiresApproval() async throws {
        let settings = AgentBrowserSettings.shared
        let keys = ["fraudulentWebsiteWarning", "upgradeToHTTPS"]
        defer { settings.reset(keys: keys) }
        settings.apply(Dictionary(uniqueKeysWithValues: keys.map { ($0, true) }), persist: false)
        let patch = Dictionary(uniqueKeysWithValues: keys.map { ($0, false) })
        var prompt: String?
        do {
            _ = try await AgentSettings.call("settings_apply", arguments: ["settings": patch], navigator: nil) {
                prompt = $0
                return false
            }
            XCTFail("Unapproved settings must not disable site protections")
        } catch {
            let request = try XCTUnwrap(prompt)
            XCTAssertTrue(request.contains("fraudulent websites"))
            XCTAssertTrue(request.contains("upgrading known hosts to HTTPS"))
        }
        for key in keys {
            XCTAssertTrue(settings.value(key, fallback: false))
        }
    }

    func testTemporaryCleanStartRequiresApprovalAndExplainsDeletion() async throws {
        let settings = AgentBrowserSettings.shared
        let key = "cleanStart"
        defer { settings.reset(keys: [key]) }
        settings.apply([key: false], persist: false)
        var prompt: String?
        do {
            _ = try await AgentSettings.call("settings_apply", arguments: ["settings": [key: true]], navigator: nil) {
                prompt = $0
                return false
            }
            XCTFail("Unapproved settings must not enable Clean Start")
        } catch {
            XCTAssertTrue(try XCTUnwrap(prompt).contains("clears all WKWebView website data"))
        }
        XCTAssertFalse(settings.value(key, fallback: true))
    }

    func testTypedPatchRejectsUnknownOrInvalidValues() {
        XCTAssertThrowsError(try AgentSetting.validatePatch(["unknown": true], persist: false))
        XCTAssertThrowsError(try AgentSetting.validatePatch(["pageZoom": true], persist: false))
        XCTAssertThrowsError(try AgentSetting.validatePatch(["pageZoom": 9], persist: false))
        XCTAssertThrowsError(try AgentSetting.validatePatch(["allowsAirPlay": 1], persist: false))
        XCTAssertThrowsError(try AgentSetting.validatePatch(["useCallbackTestPage": true], persist: true))
        XCTAssertNoThrow(try AgentSetting.validatePatch(["webViewHeightRatio": BarConstants.appHeightPreset], persist: false))
    }

    func testPersistClearsPreviousSessionOverride() throws {
        let suite = "AgentSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AgentBrowserSettings()
        let key = "pageZoom"
        let setting = try XCTUnwrap(AgentSetting.catalog[key])
        let session = try AgentSetting.validatePatch([key: 2.0], persist: false)
        let saved = try AgentSetting.validatePatch([key: 1.5], persist: true)
        settings.apply(session, persist: false, defaults: defaults)

        settings.apply(saved, persist: true, defaults: defaults)

        XCTAssertEqual(settings.value(key, fallback: 1.5), 1.5)
        XCTAssertEqual(settings.effectiveValue(for: setting, defaults: defaults) as? Double, 1.5)
        XCTAssertEqual(defaults.double(forKey: key), 1.5)
    }

    func testMenuOverrideUsesTheSameStoredRowsAsToolbar() async throws {
        let key = "toolbarItemsOrder"
        defer { AgentBrowserSettings.shared.reset(keys: [key]) }
        let args: [String: Any] = [
            "menu": "wk_toolbar",
            "action": "apply",
            "visibleOrder": ["screenshot", "console"],
        ]
        let result = try await AgentSettings.call("menus", arguments: args, navigator: nil) { _ in false }
        XCTAssertEqual((result as? [String: Any])?["visibleOrder"] as? [String], ["screenshot", "console"])

        let data = AgentBrowserSettings.shared.value(key, fallback: Data())
        XCTAssertEqual(ToolbarSettings.visibleItems(from: data), [.screenshot, .console])
    }

    func testMenuRowsKeepHiddenItemsInTheirRequestedPositions() async throws {
        let key = "appBarItemsOrder"
        let settings = AgentBrowserSettings.shared
        defer { settings.reset(keys: [key]) }
        let arguments: [String: Any] = [
            "menu": "wk_app_bar", "action": "apply",
            "items": [
                ["menuItem": "refresh", "isVisible": true],
                ["menuItem": "back", "isVisible": false],
                ["menuItem": "home", "isVisible": true]
            ]
        ]
        let response = try await AgentSettings.call("menus", arguments: arguments, navigator: nil) { _ in false }
        let result = try XCTUnwrap(response as? [String: Any])
        XCTAssertEqual(result["visibleOrder"] as? [String], ["refresh", "home"])
        let rows = try XCTUnwrap(result["items"] as? [[String: Any]])
        XCTAssertEqual(rows.compactMap { $0["menuItem"] as? String }, ["refresh", "back", "home", "initialURL", "forward"])
        XCTAssertEqual(rows.compactMap { $0["isVisible"] as? Bool }, [true, false, true, false, false])
        let nativeRows = try JSONDecoder().decode([AppBarItemState].self, from: settings.value(key, fallback: Data()))
        XCTAssertEqual(nativeRows.map(\.menuItem), [.refresh, .back, .home, .initialURL, .forward])
        XCTAssertEqual(nativeRows.filter(\.isVisible).map(\.menuItem), [.refresh, .home])
    }

    func testMenuRejectsDuplicateIDsNonBooleanVisibilityAndMixedFormats() async throws {
        let base: [String: Any] = ["menu": "wk_toolbar", "action": "apply"]
        let valid = ["menuItem": "network", "isVisible": true] as [String: Any]
        for patch: [String: Any] in [
            ["items": [valid, valid]],
            ["items": [["menuItem": "network", "isVisible": 1]]],
            ["items": [valid], "visibleOrder": ["network"]]
        ] {
            do {
                _ = try await AgentSettings.call("menus", arguments: base.merging(patch) { _, new in new }, navigator: nil) { _ in false }
                XCTFail("Invalid menu layout was accepted")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("unique menu item"))
            }
        }
    }

    func testBookmarkPaginationKeepsDefaultLimitAndRedactsBeforeFiltering() async throws {
        let urls = (0..<65).map { "https://bookmark\($0).example.com/private?secret=\($0)" }
        let tool = try XCTUnwrap(AgentSettings.tools.first { $0["name"] as? String == "bookmarks" })
        let first = try await AgentSettings.savedURLPage(
            AgentSettingsInput(arguments: [:], authorize: { _ in false }), action: "list", collection: { urls }
        )
        XCTAssertEqual((first["urls"] as? [String])?.count, 50)
        XCTAssertEqual(first["total"] as? Int, 65)
        let offset = try XCTUnwrap(first["nextOffset"] as? Int)
        let arguments: [String: Any] = ["action": "list", "offset": offset, "limit": 30]
        try AgentTool.validate(arguments, using: tool)
        let next = try await AgentSettings.savedURLPage(
            AgentSettingsInput(arguments: arguments, authorize: { _ in false }), action: "list", collection: { urls }
        )
        XCTAssertEqual(next["urls"] as? [String], (50..<65).map { "https://bookmark\($0).example.com" })
        XCTAssertNil(next["nextOffset"])
        XCTAssertEqual(next["redacted"] as? Bool, true)

        let filtered = try await AgentSettings.savedURLPage(
            AgentSettingsInput(arguments: ["query": "private"], authorize: { _ in false }), action: "list", collection: { urls }
        )
        XCTAssertEqual(filtered["total"] as? Int, 0)
        XCTAssertThrowsError(try AgentTool.validate(["action": "list", "offset": true], using: tool))
        XCTAssertThrowsError(try AgentTool.validate(["action": "history", "limit": 101], using: tool))
    }

    func testRawHistoryPageRequiresApprovalBeforeReadingSavedURLs() async throws {
        let url = "https://example.com/path?token=fixture"
        let arguments: [String: Any] = ["raw": true, "limit": 1, "offset": 1]
        var approved = false
        let input = AgentSettingsInput(arguments: arguments) { _ in
            approved = true
            return true
        }
        let page = try await AgentSettings.savedURLPage(input, action: "history") {
            XCTAssertTrue(approved)
            return ["https://other.example.com/", url]
        }
        XCTAssertEqual(page["urls"] as? [String], [url])
        XCTAssertEqual(page["redacted"] as? Bool, false)
    }

    func testPreloadLogListCanPageThroughAllRetainedEntries() async throws {
        let webView = WKWebView()
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        defer { withExtendedLifetime(webView) {} }
        for index in 0..<205 {
            navigator.preloadBridgeLogManager.add(channel: "channel_\(index)", direction: .received, body: "private")
        }
        let tool = try XCTUnwrap(AgentSettings.tools.first { $0["name"] as? String == "preload" })
        let arguments: [String: Any] = ["action": "logs", "offset": 50, "limit": 150]
        try AgentTool.validate(arguments, using: tool)
        XCTAssertThrowsError(try AgentTool.validate(["action": "logs", "limit": 201], using: tool))

        let first = try await AgentSettings.call("preload", arguments: ["action": "logs"], navigator: navigator) { _ in
            XCTFail("Listing log metadata does not need approval")
            return false
        }
        let next = try await AgentSettings.call("preload", arguments: arguments, navigator: navigator) { _ in false }
        let rows = try XCTUnwrap(first as? [[String: Any]]) + XCTUnwrap(next as? [[String: Any]])
        XCTAssertEqual((first as? [[String: Any]])?.count, 50)
        XCTAssertEqual(rows.compactMap { $0["channel"] as? String }, (5..<205).reversed().map { "channel_\($0)" })
        XCTAssertTrue(rows.allSatisfy { $0["body"] == nil })
    }

    func testPreloadLogDetailReturnsExactRetainedBodyWithApprovalOnEveryChunk() async throws {
        let webView = WKWebView()
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        defer { withExtendedLifetime(webView) {} }
        let channel = String(repeating: "c", count: 5_000)
        let longCharacter = "a" + String(repeating: "\u{301}", count: 150_000)
        let body = longCharacter + String(repeating: "🚦", count: 20_001)
        navigator.preloadBridgeLogManager.add(channel: channel, direction: .received, body: body)
        let entry = try XCTUnwrap(navigator.preloadBridgeLogManager.entries.first)
        var arguments: [String: Any] = ["action": "logs", "logId": entry.id.uuidString, "raw": true]

        do {
            _ = try await AgentSettings.call("preload", arguments: arguments, navigator: navigator) { _ in false }
            XCTFail("The log body requires iPhone approval")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("did not approve"))
        }

        let preview = try await AgentSettings.call("preload", arguments: ["action": "logs", "raw": true], navigator: navigator) { _ in true }
        let row = try XCTUnwrap((preview as? [[String: Any]])?.first)
        XCTAssertEqual((row["body"] as? String)?.unicodeScalars.count, 8_192)

        var approvalCount = 0
        var content = ""
        for _ in 0..<2 {
            let response = try await AgentSettings.call("preload", arguments: arguments, navigator: navigator) { _ in
                approvalCount += 1
                return true
            }
            let chunk = try XCTUnwrap(response as? [String: Any])
            XCTAssertEqual(chunk["id"] as? String, entry.id.uuidString)
            content += try XCTUnwrap(chunk["content"] as? String)
            guard let nextOffset = chunk["nextByteOffset"] as? Int else { break }
            arguments["byteOffset"] = nextOffset
            arguments["contentId"] = try XCTUnwrap(chunk["contentId"] as? String)
        }
        XCTAssertEqual(approvalCount, 2)
        let record = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
        XCTAssertEqual(record["channel"] as? String, channel)
        XCTAssertEqual(Data(try XCTUnwrap(record["body"] as? String).utf8), Data(entry.body.utf8))
        XCTAssertTrue(entry.body.contains("[truncated "))
    }

}
