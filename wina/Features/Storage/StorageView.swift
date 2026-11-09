//
//  StorageView.swift
//  wina
//
//  Web Storage debugging view for WKWebView.
//  Displays localStorage, sessionStorage, and cookies.
//

import SwiftUI
import SwiftUIBackports
import WebKit

// MARK: - Storage Manager

protocol StorageNavigator: AnyObject {
    func evaluateJavaScript(_ script: String) async -> Any?
    var attachedCookieStore: (any StorageCookieStore)? { get }
}

@MainActor
protocol StorageCookieStore: AnyObject {
    func allCookies() async -> [HTTPCookie]
    func setCookie(_ cookie: HTTPCookie) async
    func deleteCookie(_ cookie: HTTPCookie) async
}

extension WKHTTPCookieStore: StorageCookieStore {}

@Observable
class StorageManager {
    var items: [StorageItem] = []
    var lastRefreshTime: Date?
    var errorMessage: String?
    var currentURL: URL?

    private weak var navigator: StorageNavigator?
    private var refreshID = UUID()

    func setNavigator(_ navigator: StorageNavigator?) {
        if self.navigator !== navigator { refreshID = UUID() }
        self.navigator = navigator
    }

    // Sync storage with WebView (keep prior data for same page if fetch fails)
    @MainActor
    func refresh(pageURL: URL? = nil) async {
        guard let navigator else {
            errorMessage = "WebView not connected"
            return
        }

        let id = UUID()
        refreshID = id
        let cookieStore = navigator.attachedCookieStore
        let previousItems = items
        let didChangeURL = pageURL != currentURL

        // If URL changed, clear items immediately to avoid stale data flashing
        if let newURL = pageURL, didChangeURL {
            currentURL = newURL
            items.removeAll()
        }
        currentURL = pageURL

        errorMessage = nil

        // Fetch new data in background
        var newItems: [StorageItem] = []

        var readError: String?
        for type in [StorageItem.StorageType.localStorage, .sessionStorage] {
            let result = await Self.fetchStorage(type: type, navigator: navigator)
            if let entries = result.items {
                newItems.append(contentsOf: entries)
            } else if !didChangeURL {
                newItems.append(contentsOf: previousItems.filter { $0.storageType == type })
            }
            if let message = result.error { readError = message }
        }
        if let cookieStore { newItems += await Self.fetchCookies(in: cookieStore, pageURL: pageURL) }

        guard refreshID == id else { return }
        items = newItems
        errorMessage = readError
        lastRefreshTime = Date()
    }

    @MainActor
    static func readItems(
        type: StorageItem.StorageType?,
        pageURL: URL,
        allCookies: Bool,
        navigator: StorageNavigator
    ) async throws -> [StorageItem] {
        var items: [StorageItem] = []
        let cookieStore = navigator.attachedCookieStore
        for type in type.map({ [$0] }) ?? StorageItem.StorageType.allCases {
            if type == .cookies {
                guard let cookieStore else { throw ReadError(errorDescription: "The active cookie store is unavailable.") }
                items += await fetchCookies(in: cookieStore, pageURL: pageURL, allCookies: allCookies)
            } else {
                let result = await fetchStorage(type: type, navigator: navigator)
                guard let entries = result.items else {
                    throw ReadError(errorDescription: "Could not read \(type.rawValue) for the active document.")
                }
                items += entries
            }
        }
        return items
    }

    private struct ReadError: LocalizedError {
        let errorDescription: String?
    }

    private static func fetchStorage(
        type: StorageItem.StorageType,
        navigator: StorageNavigator
    ) async -> (items: [StorageItem]?, error: String?) {
        let storageName = type == .localStorage ? "localStorage" : "sessionStorage"
        let script = """
            (function() {
                try {
                    var result = [];
                    for (var i = 0; i < \(storageName).length; i++) {
                        var key = \(storageName).key(i);
                        var value = \(storageName).getItem(key);
                        result.push({ key: key, value: value, origin: location.origin });
                    }
                    return JSON.stringify(result);
                } catch(e) {
                    return JSON.stringify({ error: e.message });
                }
            })();
            """

        guard let result = await navigator.evaluateJavaScript(script) as? String,
              let data = result.data(using: .utf8) else {
            return (nil, nil)
        }

        // Check for error
        if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let error = errorDict["error"] {
            return (nil, "\(type.label): \(error)")
        }

        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return (nil, nil)
        }

        let entries = items.compactMap { dict -> StorageItem? in
            guard let key = dict["key"], let value = dict["value"] else { return nil }
            return StorageItem(key: key, value: value, storageType: type, origin: dict["origin"])
        }
        return (entries, nil)
    }

    private static func fetchCookies(
        in cookieStore: any StorageCookieStore,
        pageURL: URL?,
        allCookies: Bool = false
    ) async -> [StorageItem] {
        // Use native WKHTTPCookieStore for full cookie metadata (global cookie list)
        let cookies = await cookieStore.allCookies()
        if allCookies { return storageItems(for: cookies) }
        guard let host = pageURL?.host?.lowercased() else { return [] }

        return storageItems(for: cookies.filter { cookieMatchesHost($0, host: host) })
    }

    private static func cookieMatchesHost(_ cookie: HTTPCookie, host: String) -> Bool {
        let domain = cookie.domain.lowercased()
        if domain.hasPrefix(".") {
            return host == String(domain.dropFirst()) || host.hasSuffix(domain)
        }
        return host == domain
    }

    private static func storageItems(for cookies: [HTTPCookie]) -> [StorageItem] {
        cookies.map { cookie in
            StorageItem(
                key: cookie.name,
                value: cookie.value,
                storageType: .cookies,
                cookieMetadata: CookieMetadata(from: cookie)
            )
        }
    }

    @MainActor
    func addItem(
        key: String,
        value: String,
        type: StorageItem.StorageType,
        pageURL: URL,
        cookieAtRoot: Bool = false,
        isCurrentDocument: () -> Bool = { true }
    ) async -> Bool {
        guard let navigator else { return false }
        errorMessage = nil

        let operation: String
        let arguments: [String]
        let rootCookieStore = cookieAtRoot && type == .cookies ? navigator.attachedCookieStore : nil
        var rootCookieMatches: ((HTTPCookie) -> Bool)?
        switch type {
        case .localStorage, .sessionStorage:
            arguments = [key, value]
            let storage = type == .localStorage ? "localStorage" : "sessionStorage"
            operation = """
            const [key, value] = args;
            if (\(storage).getItem(key) !== null) return false;
            \(storage).setItem(key, value);
            """
        case .cookies:
            let cookieWhitespace = CharacterSet(charactersIn: " \t")
            let cookieKey = key.trimmingCharacters(in: cookieWhitespace)
            guard !cookieKey.isEmpty, !cookieKey.contains(";") else { return false }
            let escapedKey = cookieKey.replacingOccurrences(of: "=", with: "%3D")
            let escapedValue = value.trimmingCharacters(in: cookieWhitespace).replacingOccurrences(of: ";", with: "%3B")
            if cookieAtRoot {
                guard let rootCookieStore, let host = pageURL.host?.lowercased() else { return false }
                let existing = await rootCookieStore.allCookies()
                guard isCurrentDocument() else { return false }
                if existing.contains(where: {
                    $0.name == escapedKey && $0.path == "/" && [host, ".\(host)"].contains($0.domain.lowercased())
                }) {
                    errorMessage = "A cookie with this name already exists at /."
                    return false
                }
                rootCookieMatches = { cookie in
                    cookie.name == escapedKey && cookie.path == "/" &&
                        cookie.domain.lowercased() == host && cookie.value == escapedValue
                }
            }
            let path = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
            arguments = [path.isEmpty ? "/" : path, "\(escapedKey)=\(escapedValue)", cookieAtRoot ? "; Path=/" : ""]
            operation = """
            const [path, cookie, scope] = args;
            if (location.pathname !== path) return false;
            if (scope) {
                document.cookie = cookie + scope;
                return true;
            }
            const matches = item => item.trimStart() === cookie;
            if (document.cookie.split(';').some(matches)) return false;
            document.cookie = cookie;
            if (!document.cookie.split(';').some(matches)) return false;
            """
        }

        guard let script = pageStorageScript(pageURL: pageURL, arguments: arguments, operation: operation) else { return false }
        guard await navigator.evaluateJavaScript(script) as? Bool == true else { return false }
        guard let rootCookieStore, let rootCookieMatches else { return true }
        return await rootCookieStore.allCookies().contains(where: rootCookieMatches)
    }

    @MainActor
    func updateItem(_ item: StorageItem, key: String, value: String) async -> Bool {
        guard let navigator else { return false }
        errorMessage = nil
        let success: Bool
        if item.storageType == .cookies {
            if let cookieStore = navigator.attachedCookieStore, let metadata = item.cookieMetadata,
               let cookie = makeCookie(name: key, value: value, metadata: metadata) {
                success = await updateCookie(cookie, replacing: item.key, in: cookieStore)
            } else {
                success = false
            }
        } else {
            guard let origin = item.origin,
                  let data = try? JSONSerialization.data(withJSONObject: [origin, item.key, key, value]),
                  let arguments = String(data: data, encoding: .utf8) else { return false }
            let storage = item.storageType == .localStorage ? "localStorage" : "sessionStorage"
            // Keep the rename in one document and retain the original if the write fails.
            let script = """
            (function() {
                const args = \(arguments);
                if (location.origin !== args[0]) return false;
                const oldKey = args[1], newKey = args[2], value = args[3];
                const storage = \(storage);
                if (oldKey !== newKey && storage.getItem(newKey) !== null) return false;
                storage.setItem(newKey, value);
                if (oldKey !== newKey) storage.removeItem(oldKey);
                return true;
            })();
            """
            success = await navigator.evaluateJavaScript(script) as? Bool == true
        }
        if !success {
            errorMessage = "Could not save the item. The original item was kept. Check the key and available storage, then try again."
        }
        return success
    }

    private func updateCookie(
        _ replacement: HTTPCookie,
        replacing oldName: String,
        in cookieStore: any StorageCookieStore
    ) async -> Bool {
        let matchesScope: (HTTPCookie) -> Bool = {
            $0.domain.caseInsensitiveCompare(replacement.domain) == .orderedSame && $0.path == replacement.path
        }
        let cookies = await cookieStore.allCookies().filter(matchesScope)
        let renamed = replacement.name != oldName
        guard let original = cookies.first(where: { $0.name == oldName }),
              !renamed || !cookies.contains(where: { $0.name == replacement.name }) else { return false }

        await cookieStore.setCookie(replacement)
        let verified = await cookieStore.allCookies().contains {
            matchesScope($0) && $0.name == replacement.name && $0.value == replacement.value
        }
        if verified && renamed { await cookieStore.deleteCookie(original) }
        return verified
    }

    // Remove item from storage
    @MainActor
    func removeItem(_ item: StorageItem) async -> Bool {
        guard let navigator else { return false }
        errorMessage = nil

        if item.storageType == .cookies {
            guard let cookieStore = navigator.attachedCookieStore, let metadata = item.cookieMetadata else { return false }
            let cookies = await cookieStore.allCookies()
            for cookie in cookies where cookie.name == item.key && cookie.path == metadata.path &&
                cookie.domain.caseInsensitiveCompare(metadata.domain) == .orderedSame {
                await cookieStore.deleteCookie(cookie)
            }
            return true
        }

        guard let origin = item.origin,
              let data = try? JSONSerialization.data(withJSONObject: [origin, item.key]),
              let arguments = String(data: data, encoding: .utf8) else { return false }
        let storage = item.storageType == .localStorage ? "localStorage" : "sessionStorage"
        let script = """
        (function() {
            const args = \(arguments);
            if (location.origin !== args[0]) return false;
            \(storage).removeItem(args[1]);
            return true;
        })();
        """
        let success = await navigator.evaluateJavaScript(script) as? Bool == true
        if !success { errorMessage = "Could not delete the item. Refresh and try again." }
        return success
    }

    // Clear all items of a type
    @MainActor
    func clearStorage(type: StorageItem.StorageType, pageURL: URL? = nil) async -> Bool {
        guard let navigator else { return false }

        // Use native WKHTTPCookieStore for cookies (more reliable)
        if type == .cookies {
            guard let cookieStore = navigator.attachedCookieStore else { return false }
            for cookie in await cookieStore.allCookies() { await cookieStore.deleteCookie(cookie) }
            return true
        }

        let storage = type == .localStorage ? "localStorage" : "sessionStorage"
        guard let pageURL, let script = pageStorageScript(pageURL: pageURL, operation: "\(storage).clear();") else { return false }
        return await navigator.evaluateJavaScript(script) as? Bool == true
    }

    private func pageStorageScript(pageURL: URL, arguments: [String] = [], operation: String) -> String? {
        let originURL = pageURL.scheme?.lowercased() == "blob"
            ? URL(string: String(pageURL.absoluteString.dropFirst("blob:".count)))
            : pageURL
        guard let originURL, let scheme = originURL.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = originURL.host?.lowercased(), !host.isEmpty else { return nil }
        let originHost = host.contains(":") ? "[\(host)]" : host
        var origin = "\(scheme)://\(originHost)"
        if let port = originURL.port, port != (scheme == "https" ? 443 : 80) {
            origin += ":\(port)"
        }
        guard let data = try? JSONSerialization.data(withJSONObject: [origin, arguments]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return """
        (function() {
            const values = \(json);
            if (location.origin !== values[0]) return false;
            const args = values[1];
            \(operation)
            return true;
        })();
        """
    }

    @MainActor
    func clearCookies(forDomain domain: String) async -> Bool {
        guard let cookieStore = navigator?.attachedCookieStore else { return false }
        let host = domain.lowercased()
        let cookies = await cookieStore.allCookies()
        for cookie in cookies where Self.cookieMatchesHost(cookie, host: host) {
            await cookieStore.deleteCookie(cookie)
        }
        return true
    }

    func clear() {
        refreshID = UUID()
        items.removeAll()
        lastRefreshTime = nil
        errorMessage = nil
    }

    private func makeCookie(
        name: String,
        value: String,
        metadata: CookieMetadata
    ) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: metadata.domain,
            .path: metadata.path,
            .name: name,
            .value: value
        ]

        if let expiresDate = metadata.expiresDate {
            properties[.expires] = expiresDate
        }
        if metadata.isSecure {
            properties[.secure] = "TRUE"
        }
        if metadata.isHTTPOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }
        if let sameSitePolicy = metadata.sameSitePolicy {
            properties[.sameSitePolicy] = sameSitePolicy
        }

        return HTTPCookie(properties: properties)
    }
}

extension WebViewNavigator: StorageNavigator {}

// MARK: - Storage View

struct StorageShareContent: Identifiable {
    let id = UUID()
    let content: String
}

private struct StorageScrollMetrics: Equatable {
    let offset: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
}

struct StorageEditorTarget: Identifiable {
    enum Action {
        case edit(StorageItem)
        case add(StorageItem.StorageType, URL)
    }

    let id = UUID()
    let action: Action
}

struct StorageView: View {
    let storageManager: StorageManager
    let navigator: WebViewNavigator?
    @Environment(\.closeDevTools) private var closeDevTools
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: StorageItem.StorageType = .localStorage
    @State private var showsAllStorage: Bool = false
    @State private var searchText: String = ""
    @State private var shareItem: StorageShareContent?
    @Binding var editor: StorageEditorTarget?
    @State private var showClearFailure = false
    @State private var lastObservedURL: URL?
    @State private var urlCheckTimer: Timer?
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollViewHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy?
    @State private var feedbackState = CopiedFeedbackState()

    private var currentHost: String? {
        navigator?.currentURL?.host()
    }

    private var hasCurrentDomainCookies: Bool {
        guard let host = currentHost?.lowercased() else { return false }
        return storageManager.items.contains { item in
            guard item.storageType == .cookies,
                  let domain = item.cookieMetadata?.domain.lowercased() else {
                return false
            }
            if domain.hasPrefix(".") {
                let trimmed = String(domain.dropFirst())
                return host == trimmed || host.hasSuffix(".\(trimmed)")
            }
            return host == domain
        }
    }

    private var filteredItems: [StorageItem] {
        var result: [StorageItem]
        if showsAllStorage {
            result = storageManager.items
        } else {
            result = storageManager.items.filter { $0.storageType == selectedType }
        }

        if !searchText.isEmpty {
            result = result.filter {
                let matchesKeyValue = $0.key.localizedCaseInsensitiveContains(searchText)
                    || $0.value.localizedCaseInsensitiveContains(searchText)
                if $0.storageType == .cookies, let metadata = $0.cookieMetadata {
                    return matchesKeyValue
                        || metadata.domain.localizedCaseInsensitiveContains(searchText)
                        || metadata.path.localizedCaseInsensitiveContains(searchText)
                }
                return matchesKeyValue
            }
        }

        return result.sorted { lhs, rhs in
            if showsAllStorage, lhs.storageType != rhs.storageType {
                return lhs.storageType.sortOrder < rhs.storageType.sortOrder
            }
            return lhs.key < rhs.key
        }
    }

    private var cookieGroups: [(domain: String, items: [StorageItem])] {
        // Group by domain for cookie-only view to reduce visual noise.
        let cookies = filteredItems.filter { $0.storageType == .cookies }
        let grouped = Dictionary(grouping: cookies) { item in
            item.cookieMetadata?.domain.lowercased() ?? ""
        }
        return grouped.keys.sorted().compactMap { domainKey in
            guard let items = grouped[domainKey], !items.isEmpty else { return nil }
            let displayDomain = items.first?.cookieMetadata?.domain ?? domainKey
            let sortedItems = items.sorted { $0.key < $1.key }
            return (displayDomain, sortedItems)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            storageHeader
            searchBar
            if !showsAllStorage {
                storageTypePicker
            }

            Divider()

            if filteredItems.isEmpty && searchText.isEmpty {
                emptyState
            } else if filteredItems.isEmpty {
                noMatchState
            } else {
                tableHeader
                itemList
            }
        }
        .dismissKeyboardOnTap()
        .sheet(item: $shareItem) { item in
            ShareSheet(content: item.content)
        }
        .sheet(item: $editor) { target in
            switch target.action {
            case .edit(let item):
                StorageEditSheet(
                    item: item, storageManager: storageManager,
                    onSave: refreshStorage, onDelete: refreshStorage
                )
            case .add(let type, let pageURL):
                StorageAddSheet(
                    storageManager: storageManager, storageType: type,
                    pageURL: pageURL, onSave: refreshStorage
                )
            }
        }
        .alert("Could not clear storage", isPresented: $showClearFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Refresh storage for the current page and try again.")
        }
        .task {
            await AdManager.shared.showInterstitialAd(
                options: AdOptions(id: "storage_devtools"),
                adUnitId: AdManager.interstitialAdUnitId
            )
            storageManager.setNavigator(navigator)
            lastObservedURL = navigator?.currentURL
            await storageManager.refresh(pageURL: navigator?.currentURL)
        }
        .onChange(of: navigator?.currentURL) { _, newURL in
            if newURL != lastObservedURL {
                lastObservedURL = newURL
                Task { await storageManager.refresh(pageURL: newURL) }
            }
        }
        .onAppear {
            // Start timer to detect URL changes even during swipe navigation
            urlCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                if navigator?.currentURL != lastObservedURL {
                    lastObservedURL = navigator?.currentURL
                    Task { await storageManager.refresh(pageURL: navigator?.currentURL) }
                }
            }
        }
        .onDisappear {
            // Stop timer when drawer closes
            urlCheckTimer?.invalidate()
            urlCheckTimer = nil
        }
        .copiedFeedbackOverlay($feedbackState.message)
    }

    private func refreshStorage() {
        Task { await storageManager.refresh(pageURL: navigator?.currentURL) }
    }

    // MARK: - Storage Header

    private var storageHeaderLeftButtons: [DevToolsHeader.HeaderButton] {
        var buttons: [DevToolsHeader.HeaderButton] = [
            .init(icon: "xmark.circle.fill", color: .secondary) {
                (closeDevTools ?? { dismiss() })()
            },
            .init(
                icon: "trash",
                isDisabled: filteredItems.isEmpty || showsAllStorage
            ) {
                let type = selectedType
                let pageURL = storageManager.currentURL
                Task {
                    if type == .cookies {
                        // For cookies: clear current domain only
                        guard let host = pageURL?.host else { return }
                        if await storageManager.clearCookies(forDomain: host) {
                            await storageManager.refresh(pageURL: navigator?.currentURL)
                        }
                    } else {
                        // For localStorage/sessionStorage: clear all
                        if await storageManager.clearStorage(type: type, pageURL: pageURL) {
                            await storageManager.refresh(pageURL: navigator?.currentURL)
                        } else {
                            showClearFailure = true
                        }
                    }
                }
            }
        ]

        // Delete all cookies button - only visible on cookie tab
        if selectedType == .cookies && !showsAllStorage {
            buttons.append(
                .init(
                    icon: "trash.slash",
                    color: .red
                ) {
                    Task {
                        if await storageManager.clearStorage(type: .cookies) {
                            await storageManager.refresh(pageURL: navigator?.currentURL)
                        }
                    }
                }
            )
        }

        buttons.append(
            .init(
                icon: "square.and.arrow.up",
                isDisabled: filteredItems.isEmpty
            ) {
                shareItem = StorageShareContent(content: exportAsText())
            }
        )

        return buttons
    }

    private var storageHeader: some View {
        DevToolsHeader(
            title: "Storage",
            leftButtons: storageHeaderLeftButtons,
            rightButtons: [
                .init(
                    icon: "square.stack.3d.up",
                    activeIcon: "square.stack.3d.up.fill",
                    color: .secondary,
                    activeColor: .blue,
                    isActive: showsAllStorage
                ) {
                    showsAllStorage.toggle()
                },
                .init(
                    icon: "plus",
                    isDisabled: showsAllStorage || navigator?.currentURL == nil
                ) {
                    guard let pageURL = navigator?.currentURL else { return }
                    editor = StorageEditorTarget(action: .add(selectedType, pageURL))
                },
                .init(icon: "arrow.clockwise") {
                    Task { await storageManager.refresh(pageURL: navigator?.currentURL) }
                }
            ]
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter by key or value", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .backport.glassEffect(in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Storage Type Picker

    private var storageTypePicker: some View {
        Picker("Storage Type", selection: $selectedType) {
            ForEach(StorageItem.StorageType.allCases, id: \.self) { type in
                Text(type.label).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Table Header

    private let typeColumnWidth: CGFloat = 24
    private let keyColumnWidth: CGFloat = 140

    private var tableHeader: some View {
        HStack(spacing: 12) {
            if showsAllStorage {
                Image(systemName: "tag")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: typeColumnWidth, alignment: .center)
            }

            Text("Key")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .frame(width: keyColumnWidth, alignment: .leading)

            Text("Value")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Placeholder for chevron alignment
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.clear)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - States

    private var emptyState: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Image(systemName: showsAllStorage ? "tray.full" : selectedType.icon)
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text(showsAllStorage ? "No storage data" : "No \(selectedType.label.lowercased()) data")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let error = storageManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width)
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var noMatchState: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No matches")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width)
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Item List

    private func scrollUp(proxy: ScrollViewProxy?) {
        guard let proxy else { return }
        guard !filteredItems.isEmpty else { return }
        guard let firstItem = filteredItems.first else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("item-\(firstItem.id)", anchor: .top)
        }
    }

    private func scrollDown(proxy: ScrollViewProxy?) {
        guard let proxy else { return }
        guard !filteredItems.isEmpty else { return }
        guard let lastItem = filteredItems.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("item-\(lastItem.id)", anchor: .bottom)
        }
    }

    @ViewBuilder
    private func cookieGroupHeader(domain: String, count: Int) -> some View {
        HStack {
            Text(domain.isEmpty ? "(no domain)" : domain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 16)
        }
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            List {
                if selectedType == .cookies && !showsAllStorage {
                    ForEach(cookieGroups, id: \.domain) { group in
                        Section {
                            ForEach(group.items) { item in
                                StorageItemRow(
                                    item: item,
                                    typeColumnWidth: typeColumnWidth,
                                    keyColumnWidth: keyColumnWidth,
                                    searchText: searchText,
                                    onEdit: { editor = StorageEditorTarget(action: .edit($0)) },
                                    onDelete: { deleteItem($0) },
                                    onCopy: { copyToClipboard($0) },
                                    onCopyKeyValue: { copyKeyValue($0) },
                                    showsTypeIcon: showsAllStorage
                                )
                                .id("item-\(item.id)")
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color(uiColor: .systemBackground))
                            }
                        } header: {
                            cookieGroupHeader(domain: group.domain, count: group.items.count)
                                .listRowInsets(EdgeInsets())
                        }
                        .listSectionSeparator(.hidden, edges: .all)
                    }
                } else {
                    ForEach(filteredItems) { item in
                        StorageItemRow(
                            item: item,
                            typeColumnWidth: typeColumnWidth,
                            keyColumnWidth: keyColumnWidth,
                            searchText: searchText,
                            onEdit: { editor = StorageEditorTarget(action: .edit($0)) },
                            onDelete: { deleteItem($0) },
                            onCopy: { copyToClipboard($0) },
                            onCopyKeyValue: { copyKeyValue($0) },
                            showsTypeIcon: showsAllStorage
                        )
                        .id("item-\(item.id)")
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(uiColor: .systemBackground))
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .onScrollGeometryChange(for: StorageScrollMetrics.self) { geometry in
                StorageScrollMetrics(
                    offset: geometry.contentOffset.y,
                    contentHeight: geometry.contentSize.height,
                    viewportHeight: geometry.visibleRect.height
                )
            } action: { oldValue, newValue in
                if oldValue != newValue {
                    scrollOffset = newValue.offset
                    contentHeight = newValue.contentHeight
                    scrollViewHeight = newValue.viewportHeight
                }
            }
            .scrollNavigationOverlay(
                scrollOffset: scrollOffset,
                contentHeight: contentHeight,
                viewportHeight: scrollViewHeight,
                onScrollUp: { scrollUp(proxy: scrollProxy) },
                onScrollDown: { scrollDown(proxy: scrollProxy) }
            )
            .onAppear {
                scrollProxy = proxy
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deleteItem(_ item: StorageItem) {
        Task {
            if await storageManager.removeItem(item) {
                await storageManager.refresh(pageURL: navigator?.currentURL)
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = JSONParser.prettyPrintIfJSON(text)
        feedbackState.showCopied("Value")
    }

    private func copyKeyValue(_ item: StorageItem) {
        UIPasteboard.general.string = "\(item.key)=\(item.value)"
        feedbackState.showCopied("Key=Value")
    }

    // MARK: - Export

    private func exportAsText() -> String {
        let title = showsAllStorage ? "All Storage Export" : "\(selectedType.label) Storage Export"
        var output = "# \(title)\n"
        output += "# \(Date().formatted())\n\n"

        for item in filteredItems {
            if showsAllStorage {
                output += "[\(item.storageType.label)] \(item.key) = \(item.value)\n"
            } else {
                output += "\(item.key) = \(item.value)\n"
            }
        }

        return output
    }
}

// MARK: - Storage Item Row

private struct StorageItemRow: View {
    let item: StorageItem
    let typeColumnWidth: CGFloat
    let keyColumnWidth: CGFloat
    let searchText: String
    let onEdit: (StorageItem) -> Void
    let onDelete: (StorageItem) -> Void
    let onCopy: (String) -> Void
    let onCopyKeyValue: (StorageItem) -> Void
    var showsDivider: Bool = true
    var showsTypeIcon: Bool = false

    // MARK: - Value Analysis

    private var isEmpty: Bool {
        item.value.isEmpty
    }

    private var valueType: StorageValueType {
        StorageValueType.detect(from: item.value)
    }

    private var displayValue: String {
        if isEmpty { return "(empty)" }
        let truncated = item.value.replacingOccurrences(of: "\n", with: " ")
        if truncated.count > 50 {
            return String(truncated.prefix(50)) + "…"
        }
        return truncated
    }

    // MARK: - Body

    var body: some View {
        Button {
            onEdit(item)
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onCopy(item.value)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                onEdit(item)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Divider()

            Button {
                onCopy(item.key)
            } label: {
                Label("Copy Key", systemImage: "doc.on.doc")
            }

            Button {
                onCopy(item.value)
            } label: {
                Label("Copy Value", systemImage: "doc.on.doc.fill")
            }

            Button {
                onCopyKeyValue(item)
            } label: {
                Label("Copy Key=Value", systemImage: "equal.circle")
            }

            Divider()

            Button(role: .destructive) {
                onDelete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Row Content

    private var rowContent: some View {
        HStack(spacing: 8) {
            if showsTypeIcon {
                Image(systemName: item.storageType.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.storageType.tintColor)
                    .frame(width: typeColumnWidth, alignment: .center)
                    .accessibilityLabel(item.storageType.label)
            }

            // Key column with highlight
            highlightedText(item.key, searchText: searchText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.leading, 4)
                .frame(width: keyColumnWidth, alignment: .leading)

            // Value column with highlight
            highlightedText(displayValue, searchText: searchText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(isEmpty ? .tertiary : .secondary)
                .lineLimit(1)
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Type label (colored text only in list)
            if valueType != .empty {
                Text(valueType.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(valueType.color)
            }

            // Chevron indicator
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if showsDivider {
                Divider()
                    .padding(.leading, 16)
            }
        }
    }

    // MARK: - Search Highlight

    private func highlightedText(_ text: String, searchText: String) -> Text {
        guard !searchText.isEmpty,
              let range = text.range(of: searchText, options: .caseInsensitive)
        else {
            return Text(text)
        }

        var attributed = AttributedString(text)
        if let attrRange = Range(range, in: attributed) {
            attributed[attrRange].font = .body.bold()
            attributed[attrRange].foregroundColor = .yellow
        }
        return Text(attributed)
    }
}

#Preview {
    let manager = StorageManager()
    return StorageView(storageManager: manager, navigator: nil, editor: .constant(nil))
        .devToolsSheet()
}
