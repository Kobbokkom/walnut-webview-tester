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

    func testTemporaryPreloadCookiesIsolateWebsiteData() {
        let settings = AgentBrowserSettings()
        let profile = WebViewPreloadProfile(isEnabled: true, cookies: [PreloadCookie(name: "fixture", value: "1")])
        XCTAssertFalse(settings.isolatesPreloadCookies)
        settings.setPreloadProfile(profile, persist: false)
        XCTAssertTrue(settings.isolatesPreloadCookies)
        settings.reset()
        XCTAssertFalse(settings.isolatesPreloadCookies)
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
        let keys = ["allowsContentJavaScript", "safariWidthRatio"]
        defer { settings.reset(keys: keys) }
        settings.apply(["allowsContentJavaScript": false, "safariWidthRatio": 0.5], persist: false)

        let wk = AgentSettings.configuredBrowserSettings(safari: false)
        XCTAssertEqual(wk["allowsContentJavaScript"] as? Bool, false)
        XCTAssertNil(wk["safariWidthRatio"])
        XCTAssertNil(wk["cleanStart"])

        let safari = AgentSettings.configuredBrowserSettings(safari: true)
        XCTAssertEqual(safari["safariWidthRatio"] as? Double, 0.5)
        XCTAssertNil(safari["allowsContentJavaScript"])
        XCTAssertNil(safari["useCallbackTestPage"])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(safari))
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
