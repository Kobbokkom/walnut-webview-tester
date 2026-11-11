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

}
