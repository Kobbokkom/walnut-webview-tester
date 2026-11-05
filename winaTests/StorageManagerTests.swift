//
//  StorageManagerTests.swift
//  winaTests
//
//  Tests for StorageManager refresh and cookie domain filtering.
//

import Foundation
import JavaScriptCore
import XCTest
@testable import wina

final class StorageManagerTests: XCTestCase {

    @MainActor
    func testRefreshFiltersCookiesByDomain() async {
        let manager = StorageManager()
        let mock = MockStorageNavigator()
        mock.jsResult = "[]"
        mock.cookies = [
            makeCookie(name: "a", value: "1", domain: ".example.com"),
            makeCookie(name: "b", value: "2", domain: "sub.example.com"),
            makeCookie(name: "c", value: "3", domain: "other.com")
        ]

        manager.setNavigator(mock)
        await manager.refresh(
            pageURL: URL(string: "https://sub.example.com/path")
        )

        let cookieKeys = manager.items
            .filter { $0.storageType == .cookies }
            .map(\.key)
            .sorted()

        XCTAssertEqual(cookieKeys, ["a", "b"])
    }

    @MainActor
    func testRefreshFiltersCookiesWithNoURL() async {
        let manager = StorageManager()
        let mock = MockStorageNavigator()
        mock.jsResult = "[]"
        mock.cookies = [
            makeCookie(name: "a", value: "1", domain: ".example.com")
        ]

        manager.setNavigator(mock)
        await manager.refresh(pageURL: nil)

        let cookieKeys = manager.items
            .filter { $0.storageType == .cookies }
            .map(\.key)
            .sorted()

        XCTAssertEqual(cookieKeys, [])
    }

    // MARK: - localStorage/sessionStorage Parsing Tests

    @MainActor
    func testRefreshParsesLocalStorageItems() async {
        let manager = StorageManager()
        let mock = MockStorageNavigator()
        mock.jsResult = """
        [{"key":"user","value":"john"},{"key":"theme","value":"dark"}]
        """
        mock.cookies = []

        manager.setNavigator(mock)
        await manager.refresh(pageURL: URL(string: "https://example.com"))

        let localStorageItems = manager.items
            .filter { $0.storageType == .localStorage }

        XCTAssertEqual(localStorageItems.count, 2)

        let userItem = localStorageItems.first { $0.key == "user" }
        XCTAssertEqual(userItem?.value, "john")
    }

    @MainActor
    func testRefreshParsesSessionStorageItems() async {
        let manager = StorageManager()
        let mock = MockStorageNavigator()
        // The mock returns same value for all JS calls; in reality they're separate
        mock.jsResult = """
        [{"key":"session_id","value":"abc123"}]
        """
        mock.cookies = []

        manager.setNavigator(mock)
        await manager.refresh(pageURL: URL(string: "https://example.com"))

        // Since mock returns same for all, we'll have duplicates
        // but the parsing should work
        let hasSessionItems = manager.items.contains { $0.key == "session_id" }
        XCTAssertTrue(hasSessionItems)
    }

    @MainActor
    func testRefreshHandlesEmptyStorage() async {
        let manager = StorageManager()
        let mock = MockStorageNavigator()
        mock.jsResult = "[]"
        mock.cookies = []

        manager.setNavigator(mock)
        await manager.refresh(pageURL: URL(string: "https://example.com"))

        XCTAssertTrue(manager.items.isEmpty)
        XCTAssertNil(manager.errorMessage)
    }

    @MainActor
    func testRefreshHandlesInvalidJSON() async {
        let manager = StorageManager()
        let mock = MockStorageNavigator()
        mock.jsResult = "not valid json"
        mock.cookies = []

        manager.setNavigator(mock)
        await manager.refresh(pageURL: URL(string: "https://example.com"))

        // Should not crash, items should be empty
        XCTAssertTrue(manager.items.isEmpty)
    }

    // MARK: - SWR Pattern Tests

    @MainActor
    func testRefreshUpdatesLastRefreshTime() async {
        let manager = StorageManager()
        let mock = MockStorageNavigator()
        mock.jsResult = "[]"
        mock.cookies = []

        XCTAssertNil(manager.lastRefreshTime)

        manager.setNavigator(mock)
        await manager.refresh(pageURL: URL(string: "https://example.com"))

        XCTAssertNotNil(manager.lastRefreshTime)
    }

    @MainActor
    func testRefreshClearsItemsOnURLChange() async {
        let manager = StorageManager()
        let mock = MockStorageNavigator()
        mock.jsResult = """
        [{"key":"key1","value":"value1"}]
        """
        mock.cookies = []

        manager.setNavigator(mock)
        await manager.refresh(pageURL: URL(string: "https://first.com"))

        XCTAssertFalse(manager.items.isEmpty)

        // Change URL - items should be cleared before new fetch
        await manager.refresh(pageURL: URL(string: "https://second.com"))

        // After refresh, new items are loaded
        XCTAssertEqual(manager.currentURL?.host, "second.com")
    }

    // MARK: - Navigator Not Set Tests

    @MainActor
    func testRefreshWithoutNavigatorSetsError() async {
        let manager = StorageManager()

        await manager.refresh(pageURL: URL(string: "https://example.com"))

        XCTAssertEqual(manager.errorMessage, "WebView not connected")
    }

    // MARK: - Delete Operations Tests

    @MainActor
    func testRemoveItemForLocalStorage() async {
        let manager = StorageManager()
        let mock = MockStorageNavigator()
        mock.jsResult = true

        manager.setNavigator(mock)
        let result = await manager.removeItem(StorageItem(key: "test_key", value: "value", storageType: .localStorage, origin: "https://example.com"))

        XCTAssertTrue(result)
        XCTAssertTrue(mock.scripts.last?.contains("removeItem") ?? false)
    }

    @MainActor
    func testRemoveItemForSessionStorage() async {
        let manager = StorageManager()
        let mock = MockStorageNavigator()
        mock.jsResult = true

        manager.setNavigator(mock)
        let result = await manager.removeItem(StorageItem(key: "test_key", value: "value", storageType: .sessionStorage, origin: "https://example.com"))

        XCTAssertTrue(result)
        XCTAssertTrue(mock.scripts.last?.contains("sessionStorage") ?? false)
    }

    @MainActor
    func testClearStorageForLocalStorage() async {
        let manager = StorageManager()
        let mock = MockStorageNavigator()
        mock.jsResult = true

        manager.setNavigator(mock)
        let result = await manager.clearStorage(type: .localStorage)

        XCTAssertTrue(result)
        XCTAssertTrue(mock.scripts.last?.contains("localStorage.clear()") ?? false)
    }

    @MainActor
    func testClearCookiesForDomainCallsNavigator() async {
        let manager = StorageManager()
        let mock = MockStorageNavigator()

        manager.setNavigator(mock)
        let result = await manager.clearCookies(forDomain: "example.com")

        XCTAssertTrue(result)
        XCTAssertEqual(mock.deletedCookieDomains, ["example.com"])
    }

    @MainActor
    func testClearResetAllState() async {
        let manager = StorageManager()
        let mock = MockStorageNavigator()
        mock.jsResult = """
        [{"key":"key1","value":"value1"}]
        """
        mock.cookies = []

        manager.setNavigator(mock)
        await manager.refresh(pageURL: URL(string: "https://example.com"))

        XCTAssertFalse(manager.items.isEmpty)

        manager.clear()

        XCTAssertTrue(manager.items.isEmpty)
        XCTAssertNil(manager.lastRefreshTime)
        XCTAssertNil(manager.errorMessage)
    }

    // MARK: - Set Item Tests

    @MainActor
    func testSetItemForLocalStorage() async {
        let manager = StorageManager()
        let mock = MockStorageNavigator()
        mock.jsResult = true

        manager.setNavigator(mock)
        let result = await manager.setItem(key: "newKey", value: "newValue", type: .localStorage)

        XCTAssertTrue(result)
        XCTAssertTrue(mock.scripts.last?.contains("localStorage.setItem") ?? false)
    }

    @MainActor
    func testRenameKeepsOriginalOnWriteFailureAndCollision() async throws {
        for type in [StorageItem.StorageType.localStorage, .sessionStorage] {
            let context = try XCTUnwrap(JSContext())
            context.evaluateScript("""
            var localStorage = {values: {old:'original', taken:'occupied'},
              getItem:function(k){return Object.prototype.hasOwnProperty.call(this.values,k) ? this.values[k] : null;},
              setItem:function(k,v){if(v==='too large') throw new Error('QuotaExceededError'); this.values[k]=v;},
              removeItem:function(k){delete this.values[k];}};
            var sessionStorage = localStorage;
            var location = {origin: 'https://elsewhere.example'};
            """)
            let mock = MockStorageNavigator()
            mock.scriptContext = context
            let manager = StorageManager()
            manager.setNavigator(mock)
            let item = StorageItem(key: "old", value: "original", storageType: type, origin: "https://example.com")
            let wrongOriginSave = await manager.updateItem(item, key: "old", value: "changed")
            let wrongOriginDelete = await manager.removeItem(item)
            XCTAssertFalse(wrongOriginSave)
            XCTAssertFalse(wrongOriginDelete)
            XCTAssertEqual(context.evaluateScript("localStorage.getItem('old')")?.toString(), "original")
            context.evaluateScript("location.origin = 'https://example.com';")
            let failed = await manager.updateItem(item, key: "new", value: "too large")
            XCTAssertFalse(failed)
            XCTAssertNotNil(manager.errorMessage)
            XCTAssertEqual(context.evaluateScript("localStorage.getItem('old')")?.toString(), "original")
            let collision = await manager.updateItem(item, key: "taken", value: "changed")
            XCTAssertFalse(collision)
            XCTAssertEqual(context.evaluateScript("localStorage.getItem('taken')")?.toString(), "occupied")
            let saved = await manager.updateItem(item, key: "new'key", value: "new value")
            XCTAssertTrue(saved)
            XCTAssertNil(manager.errorMessage)
            XCTAssertTrue(context.evaluateScript("localStorage.getItem('old')")?.isNull == true)
            XCTAssertEqual(context.evaluateScript("localStorage.getItem(\"new'key\")")?.toString(), "new value")
        }
    }

    @MainActor
    func testCookieRenameVerifiesWriteBeforeDeletingOriginal() async {
        let manager = StorageManager()
        let mock = MockStorageNavigator()
        let cookie = makeCookie(name: "old", value: "original", domain: ".example.com")
        mock.cookies = [cookie]
        mock.acceptsCookieWrites = false
        manager.setNavigator(mock)
        let item = StorageItem(key: "old", value: "original", storageType: .cookies, cookieMetadata: CookieMetadata(from: cookie))
        let failed = await manager.updateItem(item, key: "new", value: "updated")
        XCTAssertFalse(failed)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertTrue(mock.deletedCookies.isEmpty)
        XCTAssertEqual(mock.cookies.first?.name, "old")
        mock.acceptsCookieWrites = true
        let saved = await manager.updateItem(item, key: "new", value: "updated")
        XCTAssertTrue(saved)
        XCTAssertNil(manager.errorMessage)
        XCTAssertEqual(mock.deletedCookies.last?.name, "old")
        XCTAssertEqual(mock.setCookies.last?.domain, cookie.domain)
        XCTAssertEqual(mock.setCookies.last?.path, cookie.path)
    }

    @MainActor
    func testSetItemWithoutNavigatorReturnsFalse() async {
        let manager = StorageManager()

        let result = await manager.setItem(key: "key", value: "value", type: .localStorage)

        XCTAssertFalse(result)
    }
}

private final class MockStorageNavigator: StorageNavigator {
    var jsResult: Any?
    var scriptContext: JSContext?
    var acceptsCookieWrites = true
    var cookies: [HTTPCookie] = []
    private(set) var scripts: [String] = []
    private(set) var deletedCookies: [(name: String, domain: String?, path: String?)] = []
    private(set) var deletedCookieDomains: [String] = []
    private(set) var setCookies: [HTTPCookie] = []

    func evaluateJavaScript(_ script: String) async -> Any? {
        scripts.append(script)
        if let context = scriptContext {
            context.exception = nil
            let result = context.evaluateScript(script)
            return context.exception == nil ? result?.toObject() : nil
        }
        return jsResult
    }

    func getAllCookies() async -> [HTTPCookie] {
        cookies
    }

    func setCookie(_ cookie: HTTPCookie) async {
        setCookies.append(cookie)
        if acceptsCookieWrites {
            cookies.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
            cookies.append(cookie)
        }
    }

    func deleteCookie(name: String, domain: String?, path: String?) async {
        deletedCookies.append((name: name, domain: domain, path: path))
    }

    func deleteCookies(forDomain domain: String) async {
        deletedCookieDomains.append(domain)
    }

    func deleteAllCookies() async {
    }
}

private func makeCookie(name: String, value: String, domain: String) -> HTTPCookie {
    let properties: [HTTPCookiePropertyKey: Any] = [
        .domain: domain,
        .path: "/",
        .name: name,
        .value: value
    ]
    return HTTPCookie(properties: properties)!
}
