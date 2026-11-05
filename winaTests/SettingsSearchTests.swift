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

    func testSelectedResultShowsOnlyThatSettingUntilQueryChanges() throws {
        let items = SettingsSearchCatalog.items(for: .configuration)
        let item = try XCTUnwrap(items.first { $0.id == "enableJavaScript" })
        var search = SettingsSearch(item: item, locale: english)

        XCTAssertEqual(items.filter { search.matches($0, screen: .configuration, locale: english) }.map(\.id), [item.id])

        search.query = "Content JavaScript"
        XCTAssertNil(search.selectedID)
        XCTAssertTrue(items.filter { search.matches($0, screen: .configuration, locale: english) }
            .contains { $0.id == "allowsContentJavaScript" })

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
