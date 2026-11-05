import WebKit
import XCTest

@testable import wina

final class SettingsSearchTests: XCTestCase {
    private let english = Locale(identifier: "en")
    private let korean = Locale(identifier: "ko")

    func testSearchTrimsWhitespaceAndMatchesDescriptions() {
        var search = SettingsSearch()
        search.query = " \n WINDOW.OPEN() \t"
        let results = search.results(in: .loaded, locale: english)

        XCTAssertEqual(results.map(\.item.id), ["javaScriptCanOpenWindows"])
        XCTAssertEqual(results.first?.screen, .configuration)
    }

    func testSearchMatchesBothDisplayedKoreanAndEnglishSource() {
        XCTAssertEqual(SettingsSearchItem.localized("Page Zoom", locale: english), "Page Zoom")
        XCTAssertEqual(SettingsSearchItem.localized("Page Zoom", locale: korean), "페이지 확대/축소")
        var search = SettingsSearch()
        search.query = "페이지 확대"
        XCTAssertTrue(search.results(in: .loaded, locale: korean).contains { $0.item.id == "pageZoom" })

        search.query = "PAGE ZOOM"
        XCTAssertTrue(search.results(in: .loaded, locale: korean).contains { $0.item.id == "pageZoom" })

        search.query = "너비"
        XCTAssertTrue(search.results(in: .loaded, locale: korean).contains { $0.item.id == "webViewSize" })
    }

    func testViewportScaleLimitSearchOpensConfiguration() throws {
        var search = SettingsSearch()
        search.query = "Ignore Viewport Scale Limits"
        let results = search.results(in: .loaded, locale: english)

        XCTAssertEqual(results.map(\.id), ["configuration.allowZoom"])
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.item.section, "Behavior")
        let selected = SettingsSearch(item: result.item, locale: english)
        let destination = SettingsSearchCatalog.items(for: result.screen)
        XCTAssertEqual(destination.filter { selected.matches($0, screen: result.screen, locale: english) }.map(\.id), ["allowZoom"])
        XCTAssertFalse(SettingsSearchCatalog.items(for: .live).contains { $0.id == "allowZoom" })
        XCTAssertEqual(SettingsSearchCatalog.items(for: .settings).filter { $0.id == "allowZoom" }.count, 1)
    }

    func testMenuDescriptionMatchesInEnglishAndAppLanguage() {
        let description = "Dark mode, Reduced motion, Contrast"
        var search = SettingsSearch()
        search.query = "  DARK MODE  "
        XCTAssertTrue(search.matchesMenuDescription(description, locale: korean))

        search.query = "다크 모드"
        XCTAssertTrue(search.matchesMenuDescription(description, locale: korean))
        XCTAssertFalse(search.matchesMenuDescription(description, locale: english))
    }

    func testSelectedResultShowsOnlyThatSettingUntilQueryChanges() throws {
        let items = SettingsSearchCatalog.items(for: .configuration)
        let item = try XCTUnwrap(items.first { $0.id == "allowsContentJavaScript" })
        var search = SettingsSearch(item: item, locale: english)

        XCTAssertEqual(items.filter { search.matches($0, screen: .configuration, locale: english) }.map(\.id), [item.id])

        search.query = "Minimum Font Size"
        XCTAssertNil(search.selectedID)
        XCTAssertTrue(items.filter { search.matches($0, screen: .configuration, locale: english) }
            .contains { $0.id == "minimumFontSize" })

        search.query = " \n "
        XCTAssertFalse(search.isActive)
        XCTAssertTrue(items.allSatisfy { search.matches($0, screen: .configuration, locale: english) })
    }

    func testSearchOnlyReturnsSettingsAvailableInCurrentMode() {
        var search = SettingsSearch()
        search.query = "JavaScript"
        XCTAssertFalse(search.results(in: .loaded, locale: english).isEmpty)
        XCTAssertTrue(search.results(in: .safari, locale: english).isEmpty)

        search.query = "Reader"
        XCTAssertEqual(search.results(in: .safari, locale: english).map(\.item.id), ["safariEntersReaderIfAvailable"])
        XCTAssertTrue(search.results(in: .loaded, locale: english).isEmpty)
    }

    func testOldJavaScriptSearchFindsOneContentSwitch() {
        var search = SettingsSearch()
        search.query = "JavaScript"
        let matches = search.results(in: .loaded, locale: english).map(\.item.id)
        XCTAssertEqual(matches.filter { $0 == "allowsContentJavaScript" }.count, 1)
        XCTAssertFalse(matches.contains("enableJavaScript"))
    }

    func testCategorySearchAndMenuItemsHaveDistinctStableIDs() {
        var search = SettingsSearch()
        search.query = "Menu"
        let results = search.results(in: .loaded, locale: english)
        XCTAssertTrue(results.contains { $0.item.id == "toolbar.screenshot" })
        XCTAssertTrue(results.contains { $0.item.id == "appBar.home" })
        XCTAssertEqual(Set(results.map(\.id)).count, results.count)

        for screen in SettingsSearchScreen.allCases {
            let items = SettingsSearchCatalog.items(for: screen)
            XCTAssertEqual(Set(items.map(\.id)).count, items.count, screen.rawValue)
        }
    }

    func testEveryResultCanBeSelectedInItsDestination() {
        for root in [SettingsSearchScreen.settings, .loaded, .safari] {
            for screen in root.children {
                let items = SettingsSearchCatalog.items(for: screen)
                for item in items {
                    let search = SettingsSearch(item: item, locale: korean)
                    XCTAssertEqual(items.filter { search.matches($0, screen: screen, locale: korean) }.map(\.id), [item.id])
                }
            }
        }
    }

    func testEmptyAndUnmatchedSearchHaveNoNavigationResults() {
        var search = SettingsSearch()
        XCTAssertTrue(search.results(in: .loaded, locale: english).isEmpty)
        search.query = "no-such-setting-7A28"
        XCTAssertTrue(search.results(in: .loaded, locale: english).isEmpty)
    }
}

@MainActor
final class ContentJavaScriptPreferenceTests: XCTestCase {
    func testMigrationPreservesEffectiveSettingAndLaterChanges() throws {
        let name = "walnut-content-javascript-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let values: [Bool?] = [nil, false, true]
        for legacy in values {
            for content in values {
                defaults.set(legacy, forKey: "enableJavaScript")
                defaults.set(content, forKey: "allowsContentJavaScript")
                winaApp.migrateContentJavaScriptPreference(in: defaults)

                let effective = (legacy ?? true) && (content ?? true)
                let migrated = defaults.object(forKey: "allowsContentJavaScript") as? Bool
                XCTAssertEqual(migrated ?? true, effective)
                XCTAssertNil(defaults.object(forKey: "enableJavaScript"))

                defaults.set(!effective, forKey: "allowsContentJavaScript")
                winaApp.migrateContentJavaScriptPreference(in: defaults)
                XCTAssertEqual(defaults.bool(forKey: "allowsContentJavaScript"), !effective)
            }
        }
    }

    func testPageJavaScriptOffStillAllowsWalnutScripts() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.userContentController.addUserScript(WKUserScript(
            source: "window.walnutScriptRan = true;", injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        await webView.loadHTMLStringAsync("<script>window.pageScriptRan = true;</script>", baseURL: nil)
        let state = try await webView.evaluateJavaScript("[window.pageScriptRan === true, window.walnutScriptRan === true]") as? [Bool]
        XCTAssertEqual(state, [false, true])
    }
}
