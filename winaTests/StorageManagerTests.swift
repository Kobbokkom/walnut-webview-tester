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
        localStorage.setItem('actual', 'current-local');
        sessionStorage.setItem('current', 'visible');
        Object.defineProperty(window, 'localStorage', { value: {
            length: 1, key: () => 'previous', getItem: () => 'forged',
            setItem: () => { throw new Error('page-supplied text'); },
            removeItem: () => { throw new Error('page-supplied text'); },
            clear: () => { throw new Error('page-supplied text'); }
        } });
        true;
        """)
        await currentConfiguration.websiteDataStore.httpCookieStore.setCookie(
            makeCookie(name: "current-cookie", value: "available", domain: "example.com")
        )
        navigator.attach(to: currentView)

        func call(_ tool: String, _ args: [String: Any], approve: Bool = true) async throws -> [String: Any] {
            let result = try await AgentDevTools.call(
                tool, arguments: args, navigator: navigator, storage: storage, console: ConsoleSession(), authorize: { _ in approve }
            )
            return try XCTUnwrap(result as? [String: Any])
        }
        do {
            _ = try await call("storage_write", ["type": "localStorage", "action": "remove", "key": "previous"])
            XCTFail("An agent must not act on a forged or previous-document entry")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Storage entry not found or ambiguous. Supply the exact cookie domain and path if needed.")
        }
        let session = try await call("storage_list", ["type": "sessionStorage"], approve: false)
        XCTAssertEqual(session["total"] as? Int, 1)
        let all = try await call("storage_list", ["raw": true])
        let entries = try XCTUnwrap(all["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.compactMap { $0["key"] as? String }, ["actual", "current", "current-cookie"])
        XCTAssertNil(all["errors"])
        XCTAssertTrue(storage.items.contains { $0.key == "previous" })

        let added = try await call("storage_write", ["type": "localStorage", "action": "add", "key": "new", "value": "added"])
        XCTAssertEqual(added["applied"] as? Bool, true)
        let edited = try await call("storage_write", ["type": "localStorage", "action": "edit", "key": "actual", "value": "edited"])
        XCTAssertEqual(edited["applied"] as? Bool, true)
        let removed = try await call("storage_write", ["type": "localStorage", "action": "remove", "key": "new"])
        XCTAssertEqual(removed["applied"] as? Bool, true)
        let real = try await currentView.evaluateJavaScript("JSON.stringify(Object.entries(localStorage))", in: nil, contentWorld: .defaultClient)
        XCTAssertEqual(real as? String, #"[["actual","edited"]]"#)
        let cleared = try await call("storage_clear", ["type": "localStorage"])
        XCTAssertEqual(cleared["cleared"] as? Bool, true)
        let afterClear = try await call("storage_list", ["type": "localStorage"])
        XCTAssertEqual(afterClear["total"] as? Int, 0)
    }

    @MainActor
    func testAgentCookieScopePreservesWebKitAndHttpOnlyBoundaries() async throws {
        let url = try XCTUnwrap(URL(string: "https://child.example.com/account/settings"))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        await webView.loadHTMLStringAsync("<html></html>", baseURL: url)
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        defer { navigator.detach() }
        let storage = StorageManager()
        let cookieStore = configuration.websiteDataStore.httpCookieStore
        let protected = try XCTUnwrap(HTTPCookie(properties: [
            .name: "protected", .value: "untouched", .domain: ".example.com", .path: "/receipt",
            HTTPCookiePropertyKey("HttpOnly"): "TRUE"
        ]))
        await cookieStore.setCookie(protected)
        await cookieStore.setCookie(makeCookie(name: "foreign", value: "untouched", domain: "unrelated.test"))
        _ = try await webView.evaluateJavaScript("""
            Object.defineProperty(document, 'cookie', { set: () => { throw new Error('page override'); } });
            true;
            """)

        let arguments: [String: Any] = [
            "type": "cookies", "action": "add", "key": "scoped", "value": "approved", "domain": ".example.com", "path": "/receipt"
        ]
        func write(_ changes: [String: Any], authorize: @escaping (String) async -> Bool = { _ in true }) async throws -> Any {
            try await AgentDevTools.call(
                "storage_write", arguments: arguments.merging(changes) { _, new in new },
                navigator: navigator, storage: storage, console: ConsoleSession(), authorize: authorize
            )
        }
        for (changes, approval) in [
            ([:], false),
            (["key": "protected"], true),
            (["domain": "unrelated.test"], true),
            (["cookieScope": "all"], true),
            (["path": "/receipt; Domain=unrelated.test"], true),
            (["action": "remove", "key": "foreign", "domain": "unrelated.test", "path": "/", "cookieScope": "current"], true)
        ] {
            do {
                _ = try await write(changes, authorize: { _ in approval })
                XCTFail("Cookie mutation escaped its approved scope")
            } catch {
                let cookies = await cookieStore.allCookies()
                XCTAssertEqual(Set(cookies.map(\.value)), ["untouched"])
                XCTAssertEqual(cookies.count, 2)
            }
        }
        let added = try await write([:], authorize: { prompt in
            XCTAssertTrue(prompt.contains("example.com and its subdomains"))
            XCTAssertTrue(prompt.contains("at path /receipt"))
            return true
        }) as? [String: Any]
        XCTAssertEqual(added?["applied"] as? Bool, true)
        XCTAssertEqual(added?["domain"] as? String, ".example.com")
        XCTAssertEqual(added?["path"] as? String, "/receipt")
        let cookies = await cookieStore.allCookies()
        let scoped = try XCTUnwrap(cookies.first { $0.name == "scoped" })
        XCTAssertEqual(scoped.domain, ".example.com")
        XCTAssertEqual(scoped.path, "/receipt")
        XCTAssertFalse(scoped.isHTTPOnly)
        let listed = try await AgentDevTools.call(
            "storage_list", arguments: ["domain": ".example.com", "path": "/receipt", "query": "scoped", "raw": true],
            navigator: navigator, storage: storage, console: ConsoleSession(), authorize: { _ in true }
        ) as? [String: Any]
        XCTAssertEqual((listed?["entries"] as? [[String: Any]])?.compactMap { $0["key"] as? String }, ["scoped"])

        let foreign = ["action": "edit", "key": "foreign", "domain": "unrelated.test", "path": "/", "value": "changed"]
        do {
            _ = try await write(foreign, authorize: { prompt in
                XCTAssertTrue(prompt.contains("the exact domain unrelated.test at path /"))
                return false
            })
            XCTFail("A cross-domain edit must require approval")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The iPhone did not approve this action.")
        }
        let edited = try await write(foreign) as? [String: Any]
        XCTAssertEqual(edited?["domain"] as? String, "unrelated.test")
        let editedCookies = await cookieStore.allCookies()
        XCTAssertEqual(editedCookies.first { $0.name == "foreign" }?.value, "changed")
        let removed = try await write(foreign.merging(["action": "remove", "cookieScope": "all"]) { _, new in new }) as? [String: Any]
        XCTAssertEqual(removed?["applied"] as? Bool, true)
        let remaining = await cookieStore.allCookies()
        XCTAssertFalse(remaining.contains { $0.name == "foreign" })
    }

    @MainActor
    func testAgentStorageExportBoundsTextAndContinuesWithTheNextEntry() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        await webView.loadHTMLStringAsync("<html></html>", baseURL: url)
        _ = try await webView.evaluateJavaScript("""
            sessionStorage.setItem('a', 'x'.repeat(150 * 1024));
            sessionStorage.setItem('b', 'y'.repeat(150 * 1024));
            sessionStorage.setItem('c', '💚'.repeat(80 * 1024));
            sessionStorage.setItem('d', 'end');
            true;
            """)
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        defer { navigator.detach() }
        let storage = StorageManager()
        func export(offset: Int, byteOffset: Int = 0, rowId: String? = nil, limit: Int = 30, approve: Bool = true) async throws -> [String: Any] {
            var arguments: [String: Any] = [
                "type": "sessionStorage", "format": "text", "offset": offset, "byteOffset": byteOffset, "limit": limit
            ]
            arguments["rowId"] = rowId
            let result = try await AgentDevTools.call(
                "storage_list", arguments: arguments,
                navigator: navigator, storage: storage, console: ConsoleSession(), authorize: { _ in approve }
            )
            return try XCTUnwrap(result as? [String: Any])
        }
        do {
            _ = try await export(offset: 0, approve: false)
            XCTFail("Text export shares storage values and must require approval")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The iPhone did not approve this action.")
        }
        let first = try await export(offset: 0)
        XCTAssertEqual(first["nextOffset"] as? Int, 1)
        XCTAssertEqual(first["exportTruncated"] as? Bool, false)
        XCTAssertTrue((first["export"] as? String)?.contains("a = " + String(repeating: "x", count: 150 * 1024) + "\n") == true)
        let second = try await export(offset: 1)
        XCTAssertEqual(second["nextOffset"] as? Int, 2)
        XCTAssertTrue((second["export"] as? String)?.contains("b = y") == true)
        let partial = try await export(offset: 2)
        let text = try XCTUnwrap(partial["export"] as? String)
        XCTAssertEqual(partial["nextOffset"] as? Int, 2)
        XCTAssertEqual(partial["exportTruncated"] as? Bool, true)
        XCTAssertLessThanOrEqual(text.utf8.count, 256 * 1024)
        let byteOffset = try XCTUnwrap(partial["nextByteOffset"] as? Int)
        let rowId = try XCTUnwrap(partial["nextRowId"] as? String)
        do {
            _ = try await export(offset: 2, byteOffset: byteOffset)
            XCTFail("A continuation must be bound to the previously exported row")
        } catch {
            XCTAssertEqual(error.localizedDescription, "A text export continuation requires its byte offset and row ID.")
        }
        do {
            _ = try await export(offset: 2, byteOffset: byteOffset + 1, rowId: rowId)
            XCTFail("An offset inside a UTF-8 scalar must fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Invalid storage entry byte offset.")
        }
        _ = try await webView.evaluateJavaScript("sessionStorage.setItem('c', '💙'.repeat(80 * 1024)); true;")
        do {
            _ = try await export(offset: 2, byteOffset: byteOffset, rowId: rowId)
            XCTFail("A different value of the same length must not provide a suffix")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The storage export row changed. Restart this export page.")
        }
        _ = try await webView.evaluateJavaScript("sessionStorage.setItem('c', '💚'.repeat(80 * 1024)); true;")
        let continued = try await export(offset: 2, byteOffset: byteOffset, rowId: rowId, limit: 1)
        let tail = try XCTUnwrap(continued["export"] as? String)
        XCTAssertLessThanOrEqual(tail.utf8.count, 256 * 1024)
        XCTAssertEqual(continued["nextOffset"] as? Int, 3)
        XCTAssertNil(continued["nextByteOffset"])
        XCTAssertNil(continued["nextRowId"])
        let complete = text + tail
        XCTAssertTrue(complete.hasSuffix("c = " + String(repeating: "💚", count: 80 * 1024) + "\n"))
        let last = try await export(offset: 3)
        XCTAssertNil(last["nextOffset"])
        XCTAssertTrue((last["export"] as? String)?.hasSuffix("d = end\n") == true)
    }

    @MainActor
    func testAgentStorageReportsCommittedCookieDeletionAfterDocumentChanges() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/account"))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        await webView.loadHTMLStringAsync("<html></html>", baseURL: url)
        let cookieStore = MockStorageNavigator()
        let navigator = CookieStoreTestNavigator(store: cookieStore)
        navigator.attach(to: webView)
        defer { navigator.detach() }
        let storage = StorageManager()

        let cases: [(String, [String: Any], String)] = [
            ("storage_write", ["type": "cookies", "action": "remove", "key": "target"], "applied"),
            ("storage_clear", ["type": "cookies"], "cleared")
        ]
        for (tool, arguments, resultKey) in cases {
            let document = navigator.documentID
            cookieStore.cookies = [makeCookie(name: "target", value: "one", domain: "example.com")]
            cookieStore.afterDeletingCookie = { navigator.documentDidChange(in: webView) }
            let result = try await AgentDevTools.call(
                tool, arguments: arguments, navigator: navigator, storage: storage, console: ConsoleSession(), authorize: { _ in true }
            ) as? [String: Any]
            XCTAssertEqual(result?[resultKey] as? Bool, true)
            XCTAssertNotEqual(navigator.documentID, document)
            XCTAssertTrue(cookieStore.cookies.isEmpty)
        }
        XCTAssertNil(storage.lastRefreshTime)
    }

    @MainActor
    func testAgentCookieMutationsRecheckDocumentAfterNativePreflight() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/account"))
        let webView = WKWebView()
        await webView.loadHTMLStringAsync("<html></html>", baseURL: url)
        let cookieStore = MockStorageNavigator()
        let navigator = CookieStoreTestNavigator(store: cookieStore)
        navigator.attach(to: webView)
        defer { navigator.detach() }
        let storage = StorageManager()
        let cases: [(String, [String: Any], Bool)] = [
            ("storage_write", ["type": "cookies", "action": "add", "key": "new", "value": "two"], false),
            ("storage_write", ["type": "cookies", "action": "edit", "key": "target", "value": "two"], true),
            ("storage_write", ["type": "cookies", "action": "remove", "key": "target"], true),
            ("storage_clear", ["type": "cookies"], false),
            ("storage_clear", ["type": "cookies", "cookieScope": "all"], false)
        ]
        for (tool, arguments, readFirst) in cases {
            cookieStore.cookies = [makeCookie(name: "target", value: "one", domain: "example.com")]
            let navigate = { navigator.documentDidChange(in: webView) }
            cookieStore.afterReadingCookies = readFirst ? { cookieStore.afterReadingCookies = navigate } : navigate
            do {
                _ = try await AgentDevTools.call(
                    tool, arguments: arguments, navigator: navigator, storage: storage, console: ConsoleSession(),
                    authorize: { _ in true }
                )
                XCTFail("A stale approved document must not mutate cookies")
            } catch {
                XCTAssertEqual(error.localizedDescription, "The active WKWebView document changed. Try again.")
                XCTAssertEqual(cookieStore.cookies.map(\.value), ["one"])
                XCTAssertTrue(cookieStore.setCookies.isEmpty)
                XCTAssertTrue(cookieStore.deletedCookies.isEmpty)
            }
        }
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

final class StorageCookieAdditionTests: XCTestCase {
    @MainActor
    func testOverlappingNativeAndScopedAddsReserveOnlyTheSameCookie() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/account/settings"))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let nativeView = WKWebView(frame: .zero, configuration: configuration)
        let scopedView = WKWebView(frame: .zero, configuration: configuration)
        await nativeView.loadHTMLStringAsync("<html></html>", baseURL: url)
        await scopedView.loadHTMLStringAsync("<html></html>", baseURL: url)
        let cookieStore = InterleavedCookieStore(store: configuration.websiteDataStore.httpCookieStore)
        let nativeNavigator = CookieStoreTestNavigator(store: cookieStore)
        let scopedNavigator = CookieStoreTestNavigator(store: cookieStore)
        nativeNavigator.attach(to: nativeView)
        scopedNavigator.attach(to: scopedView)
        defer {
            nativeNavigator.detach()
            scopedNavigator.detach()
        }
        let native = StorageManager()
        native.setNavigator(nativeNavigator)
        let scoped = StorageManager()
        scoped.setNavigator(scopedNavigator)
        let account = StorageCookieAddScope(domain: "example.com", path: "/account")
        let root = StorageCookieAddScope(domain: nil, path: "/")
        cookieStore.afterFirstRead = {
            let duplicate = await scoped.addCookie(key: "fixture", value: "overwrite", pageURL: url, scope: account) { true }
            XCTAssertNil(duplicate)
            XCTAssertTrue(scoped.errorMessage?.contains("already in progress") == true)

            let independent = await scoped.addCookie(key: "fixture", value: "root", pageURL: url, scope: root) { true }
            XCTAssertEqual(independent?.value, "root")
        }

        let added = await native.addItem(key: "fixture", value: "native", type: .cookies, pageURL: url)
        XCTAssertTrue(added)
        let duplicate = await scoped.addCookie(key: "fixture", value: "overwrite", pageURL: url, scope: account) { true }
        XCTAssertNil(duplicate)
        XCTAssertTrue(scoped.errorMessage?.contains("already exists") == true)
        let cookies = await cookieStore.allCookies()
        XCTAssertEqual(cookies.first(where: { $0.name == "fixture" && $0.path == "/account" })?.value, "native")

        let aborted = await scoped.addCookie(key: "retry", value: "stale", pageURL: url, scope: account) { false }
        XCTAssertNil(aborted)
        let retry = await scoped.addCookie(key: "retry", value: "current", pageURL: url, scope: account) { true }
        XCTAssertEqual(retry?.value, "current")
    }

    @MainActor
    func testNativeAddCookieDoesNotWriteToAReplacementViewAtTheSameURL() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/account"))
        let firstConfiguration = WKWebViewConfiguration()
        firstConfiguration.websiteDataStore = .nonPersistent()
        let replacementConfiguration = WKWebViewConfiguration()
        replacementConfiguration.websiteDataStore = .nonPersistent()
        let first = WKWebView(frame: .zero, configuration: firstConfiguration)
        let replacement = WKWebView(frame: .zero, configuration: replacementConfiguration)
        await first.loadHTMLStringAsync("<html></html>", baseURL: url)
        await replacement.loadHTMLStringAsync("<html></html>", baseURL: url)
        let replacementStore = replacementConfiguration.websiteDataStore.httpCookieStore
        await replacementStore.setCookie(makeCookie(name: "fixture", value: "keep", domain: "example.com"))
        let cookieStore = MockStorageNavigator()
        let navigator = CookieStoreTestNavigator(store: cookieStore)
        navigator.attach(to: first)
        defer { navigator.detach() }
        let storage = StorageManager()
        storage.setNavigator(navigator)
        let document = navigator.documentID
        cookieStore.afterReadingCookies = { navigator.attach(to: replacement) }

        let added = await storage.addItem(key: "fixture", value: "overwrite", type: .cookies, pageURL: url)

        XCTAssertNotEqual(navigator.documentID, document)
        XCTAssertEqual(navigator.attachedPageURL, url)
        XCTAssertFalse(added)
        let cookies = await replacementStore.allCookies()
        XCTAssertEqual(cookies.first(where: { $0.name == "fixture" })?.value, "keep")
    }

    @MainActor
    func testNativeAddCookieKeepsExistingValueInItsDefaultPathAfterNavigation() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/account/settings"))
        let nextURL = try XCTUnwrap(URL(string: "https://example.com/orders/details"))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        await webView.loadHTMLStringAsync("<html></html>", baseURL: url)
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        defer { navigator.detach() }
        let storage = StorageManager()
        storage.setNavigator(navigator)
        let cookieStore = configuration.websiteDataStore.httpCookieStore
        await cookieStore.setCookie(makeCookie(name: "fixture", value: "root", domain: "example.com"))

        let added = await storage.addItem(key: "fixture", value: "directory", type: .cookies, pageURL: url)
        XCTAssertTrue(added)
        let duplicate = await storage.addItem(key: "fixture", value: "overwrite", type: .cookies, pageURL: url)
        XCTAssertFalse(duplicate)
        XCTAssertTrue(storage.errorMessage?.contains("/account") == true)

        await webView.loadHTMLStringAsync("<html></html>", baseURL: nextURL)
        let stale = await storage.addItem(key: "stale", value: "wrong", type: .cookies, pageURL: url)
        XCTAssertFalse(stale)
        let scoped = await storage.addItem(key: "fixture", value: "second", type: .cookies, pageURL: nextURL)
        XCTAssertTrue(scoped)
        let newDuplicate = await storage.addItem(key: "fixture", value: "overwrite", type: .cookies, pageURL: nextURL)
        XCTAssertFalse(newDuplicate)
        XCTAssertTrue(storage.errorMessage?.contains("/orders") == true)

        let cookies = await cookieStore.allCookies()
        XCTAssertFalse(cookies.contains { $0.name == "stale" })
        XCTAssertEqual(cookies.first(where: { $0.name == "fixture" && $0.path == "/" })?.value, "root")
        XCTAssertEqual(cookies.first(where: { $0.name == "fixture" && $0.path == "/account" })?.value, "directory")
        XCTAssertEqual(cookies.first(where: { $0.name == "fixture" && $0.path == "/orders" })?.value, "second")
    }
}

@MainActor
private final class CookieStoreTestNavigator: WebViewNavigator {
    private let store: any StorageCookieStore

    init(store: any StorageCookieStore) { self.store = store }

    override var attachedCookieStore: (any StorageCookieStore)? { store }
}

@MainActor
private final class InterleavedCookieStore: StorageCookieStore {
    private let store: WKHTTPCookieStore
    var afterFirstRead: (() async -> Void)?

    init(store: WKHTTPCookieStore) { self.store = store }

    func allCookies() async -> [HTTPCookie] {
        let callback = afterFirstRead
        afterFirstRead = nil
        let cookies = await store.allCookies()
        await callback?()
        return cookies
    }

    func setCookie(_ cookie: HTTPCookie) async { await store.setCookie(cookie) }
    func deleteCookie(_ cookie: HTTPCookie) async { await store.deleteCookie(cookie) }
}

@MainActor
private final class MockStorageNavigator: StorageNavigator, StorageCookieStore {
    var jsResult: Any?
    var scriptContext: JSContext?
    var acceptsCookieWrites = true
    var cookies: [HTTPCookie] = []
    var cookieStoreOverride: (any StorageCookieStore)?
    var afterReadingCookies: (() -> Void)?
    var afterDeletingCookie: (() -> Void)?
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
        let afterDelete = afterDeletingCookie
        afterDeletingCookie = nil
        afterDelete?()
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
