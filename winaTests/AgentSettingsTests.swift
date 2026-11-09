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

}
