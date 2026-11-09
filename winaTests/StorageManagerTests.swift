//
//  StorageManagerTests.swift
//  winaTests
//
//  Tests for StorageManager refresh and cookie domain filtering.
//

import Foundation
import JavaScriptCore
import WebKit
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

    @MainActor
    func testAgentStorageReadsOnlyTheCurrentDocument() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/account"))
        let initialConfiguration = WKWebViewConfiguration()
        initialConfiguration.websiteDataStore = .nonPersistent()
        let initialView = WKWebView(frame: .zero, configuration: initialConfiguration)
        await initialView.loadHTMLStringAsync("<html></html>", baseURL: url)
        _ = try await initialView.evaluateJavaScript("localStorage.setItem('previous', 'sensitive')")

        let navigator = WebViewNavigator()
        let storage = StorageManager()
        navigator.attach(to: initialView)
        defer { navigator.detach() }
        storage.setNavigator(navigator)
        await storage.refresh(pageURL: url)
        XCTAssertTrue(storage.items.contains { $0.key == "previous" })

        let currentConfiguration = WKWebViewConfiguration()
        currentConfiguration.websiteDataStore = .nonPersistent()
        let currentView = WKWebView(frame: .zero, configuration: currentConfiguration)
        await currentView.loadHTMLStringAsync("<html></html>", baseURL: url)
        _ = try await currentView.evaluateJavaScript("""
        Object.defineProperty(window, 'localStorage', { get: () => { throw new Error('page-supplied text'); } });
        true;
        """)
        navigator.attach(to: currentView)

        for (tool, arguments) in [
            ("storage_list", ["type": "localStorage", "raw": true] as [String: Any]),
            ("storage_write", ["type": "localStorage", "action": "remove", "key": "previous"])
        ] {
            do {
                _ = try await AgentDevTools.call(
                    tool, arguments: arguments, navigator: navigator, storage: storage, console: ConsoleSession(),
                    authorize: { _ in true }
                )
                XCTFail("Unavailable storage should not fall back to the previous document")
            } catch {
                XCTAssertEqual(error.localizedDescription, "Could not read localStorage for the active document.")
            }
        }
        let session = try await AgentDevTools.call(
            "storage_list", arguments: ["type": "sessionStorage"], navigator: navigator, storage: storage,
            console: ConsoleSession(), authorize: { _ in false }
        ) as? [String: Any]
        XCTAssertEqual(session?["total"] as? Int, 0)
        XCTAssertTrue(storage.items.contains { $0.key == "previous" })
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
        let result = await manager.clearStorage(type: .localStorage, pageURL: URL(string: "https://example.com"))

        XCTAssertTrue(result)
        XCTAssertTrue(mock.scripts.last?.contains("localStorage.clear()") ?? false)
    }

    @MainActor
    func testClearCookiesForDomainLeavesOtherDomainsIntact() async {
        let manager = StorageManager()
        let mock = MockStorageNavigator()
        mock.cookies = [
            makeCookie(name: "parent", value: "1", domain: ".example.com"),
            makeCookie(name: "current", value: "2", domain: "sub.example.com"),
            makeCookie(name: "other", value: "3", domain: "other.example.com")
        ]

        manager.setNavigator(mock)
        let result = await manager.clearCookies(forDomain: "sub.example.com")

        XCTAssertTrue(result)
        XCTAssertEqual(mock.deletedCookies.map(\.name), ["parent", "current"])
        XCTAssertEqual(mock.cookies.map(\.name), ["other"])
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
    func testSetItemForLocalStorage() async throws {
        let manager = StorageManager()
        let mock = MockStorageNavigator()
        mock.jsResult = true

        manager.setNavigator(mock)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let result = await manager.addItem(key: "newKey", value: "newValue", type: .localStorage, pageURL: url)

        XCTAssertTrue(result)
        XCTAssertTrue(mock.scripts.last?.contains("localStorage.setItem") ?? false)
    }

    @MainActor
    func testAddAndClearRespectDraftOriginAndLiveKeys() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let oldURL = try XCTUnwrap(URL(string: "https://old.example"))
        let pageURL = try XCTUnwrap(URL(string: "https://current.example:443/page"))
        await webView.loadHTMLStringAsync("<html><body>storage fixture</body></html>", baseURL: pageURL)
        _ = try await webView.evaluateJavaScript("localStorage.setItem('late', 'existing'); sessionStorage.setItem('late', 'existing');")
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        defer { navigator.detach() }
        let manager = StorageManager()
        manager.setNavigator(navigator)

        for type in [StorageItem.StorageType.localStorage, .sessionStorage] {
            let wrongOrigin = await manager.addItem(key: "new", value: "wrong", type: type, pageURL: oldURL)
            let duplicate = await manager.addItem(key: "late", value: "overwrite", type: type, pageURL: pageURL)
            let wrongClear = await manager.clearStorage(type: type, pageURL: oldURL)
            XCTAssertFalse(wrongOrigin)
            XCTAssertFalse(duplicate)
            XCTAssertFalse(wrongClear)
            let storage = type.rawValue
            let untouched = try await webView.evaluateJavaScript("[\(storage).getItem('late'), \(storage).getItem('new') === null]") as? [NSObject]
            XCTAssertEqual(untouched, ["existing" as NSString, NSNumber(value: true)])

            let added = await manager.addItem(key: "new", value: "saved", type: type, pageURL: pageURL)
            XCTAssertTrue(added)
            let value = try await webView.evaluateJavaScript("\(storage).getItem('new')") as? String
            XCTAssertEqual(value, "saved")
            let cleared = await manager.clearStorage(type: type, pageURL: pageURL)
            XCTAssertTrue(cleared)
            let count = try await webView.evaluateJavaScript("\(storage).length") as? Int
            XCTAssertEqual(count, 0)
        }

        webView.navigationDelegate = nil
        _ = try await webView.evaluateJavaScript("""
        location.href = URL.createObjectURL(new Blob(['<title>Blob Storage Fixture</title>'], {type: 'text/html'}));
        true;
        """)
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            webView.url?.scheme == "blob" && webView.title == "Blob Storage Fixture"
        }, object: nil)
        await fulfillment(of: [loaded], timeout: 5)
        let blobURL = try XCTUnwrap(webView.url)
        for type in [StorageItem.StorageType.localStorage, .sessionStorage] {
            let added = await manager.addItem(key: "blob", value: "kept", type: type, pageURL: blobURL)
            XCTAssertTrue(added)
            let value = try await webView.evaluateJavaScript("\(type.rawValue).getItem('blob')") as? String
            XCTAssertEqual(value, "kept")
            let cleared = await manager.clearStorage(type: type, pageURL: blobURL)
            XCTAssertTrue(cleared)
        }
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
    func testCookieRenamePinsTheOriginalStoreWhenTheViewChanges() async {
        let manager = StorageManager()
        let navigator = MockStorageNavigator()
        let original = makeCookie(name: "old", value: "original", domain: ".example.com")
        navigator.cookies = [original]
        let replacementStore = MockStorageNavigator()
        replacementStore.cookies = [makeCookie(name: "old", value: "separate", domain: ".example.com")]
        navigator.afterReadingCookies = { navigator.cookieStoreOverride = replacementStore }
        manager.setNavigator(navigator)

        let item = StorageItem(key: original.name, value: original.value, storageType: .cookies, cookieMetadata: CookieMetadata(from: original))
        let saved = await manager.updateItem(item, key: "new", value: "updated")

        XCTAssertTrue(saved)
        XCTAssertEqual(navigator.cookies.map(\.name), ["new"])
        XCTAssertEqual(navigator.cookies.map(\.value), ["updated"])
        XCTAssertEqual(replacementStore.cookies.map(\.name), ["old"])
        XCTAssertEqual(replacementStore.cookies.map(\.value), ["separate"])
        XCTAssertTrue(replacementStore.setCookies.isEmpty)
        XCTAssertTrue(replacementStore.deletedCookies.isEmpty)
    }

    @MainActor
    func testSetItemWithoutNavigatorReturnsFalse() async throws {
        let manager = StorageManager()

        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let result = await manager.addItem(key: "key", value: "value", type: .localStorage, pageURL: url)

        XCTAssertFalse(result)
    }
}

@MainActor
private final class MockStorageNavigator: StorageNavigator, StorageCookieStore {
    var jsResult: Any?
    var scriptContext: JSContext?
    var acceptsCookieWrites = true
    var cookies: [HTTPCookie] = []
    var cookieStoreOverride: (any StorageCookieStore)?
    var afterReadingCookies: (() -> Void)?
    var attachedCookieStore: (any StorageCookieStore)? { cookieStoreOverride ?? self }
    private(set) var scripts: [String] = []
    private(set) var deletedCookies: [HTTPCookie] = []
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

    func allCookies() async -> [HTTPCookie] {
        let afterRead = afterReadingCookies
        afterReadingCookies = nil
        afterRead?()
        return cookies
    }

    func setCookie(_ cookie: HTTPCookie) async {
        setCookies.append(cookie)
        if acceptsCookieWrites {
            cookies.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
            cookies.append(cookie)
        }
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        deletedCookies.append(cookie)
        cookies.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
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
