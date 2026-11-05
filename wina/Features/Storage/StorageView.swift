//
//  StorageView.swift
//  wina
//
//  Web Storage debugging view for WKWebView.
//  Displays localStorage, sessionStorage, and cookies.
//

import SwiftUI
import SwiftUIBackports

// MARK: - Storage Item Model

struct StorageItem: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String
    let storageType: StorageType
    var cookieMetadata: CookieMetadata?

    enum StorageType: String, CaseIterable {
        case localStorage
        case sessionStorage
        case cookies

        var icon: String {
            switch self {
            case .localStorage: return "internaldrive"
            case .sessionStorage: return "clock"
            case .cookies: return "birthday.cake"
            }
        }

        var label: String {
            switch self {
            case .localStorage: return "Local"
            case .sessionStorage: return "Session"
            case .cookies: return "Cookies"
            }
        }

        var sortOrder: Int {
            switch self {
            case .localStorage: return 0
            case .sessionStorage: return 1
            case .cookies: return 2
            }
        }

        var tintColor: Color {
            switch self {
            case .localStorage: return .blue
            case .sessionStorage: return .orange
            case .cookies: return .green
            }
        }
    }

    static func == (lhs: StorageItem, rhs: StorageItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.key == rhs.key &&
        lhs.value == rhs.value &&
        lhs.storageType == rhs.storageType &&
        lhs.cookieMetadata == rhs.cookieMetadata
    }
}

// MARK: - Storage Value Type

enum StorageValueType {
    case json, number, bool, string, empty

    static func detect(from value: String) -> StorageValueType {
        if value.isEmpty { return .empty }
        if JsonParser.isValidJson(value) { return .json }
        if value.lowercased() == "true" || value.lowercased() == "false" { return .bool }
        if Double(value) != nil { return .number }
        return .string
    }

    var color: Color {
        switch self {
        case .json: return .purple
        case .number: return .blue
        case .bool: return .green
        case .string: return .gray
        case .empty: return .gray.opacity(0.5)
        }
    }

    var badge: TypeBadge? {
        switch self {
        case .json:
            return TypeBadge(text: "JSON", color: .purple, icon: "curlybraces")
        case .number:
            return TypeBadge(text: "Number", color: .blue, icon: "number")
        case .bool:
            return TypeBadge(text: "Boolean", color: .green, icon: "checkmark")
        case .string:
            return TypeBadge(text: "Text", color: .gray, icon: "textformat")
        case .empty:
            return nil
        }
    }

    var label: String {
        switch self {
        case .json: return "JSON"
        case .number: return "Number"
        case .bool: return "Boolean"
        case .string: return "Text"
        case .empty: return "Empty"
        }
    }
}

// MARK: - Storage Manager

protocol StorageNavigator: AnyObject {
    func evaluateJavaScript(_ script: String) async -> Any?
    func getAllCookies() async -> [HTTPCookie]
    func setCookie(_ cookie: HTTPCookie) async
    func deleteCookie(name: String, domain: String?, path: String?) async
    func deleteCookies(forDomain domain: String) async
    func deleteAllCookies() async
}

@Observable
class StorageManager {
    var items: [StorageItem] = []
    var lastRefreshTime: Date?
    var errorMessage: String?
    var currentURL: URL?

    private weak var navigator: StorageNavigator?

    func setNavigator(_ navigator: StorageNavigator?) {
        self.navigator = navigator
    }

    // Sync storage with WebView (keep prior data for same page if fetch fails)
    @MainActor
    func refresh(pageURL: URL? = nil) async {
        guard let navigator else {
            errorMessage = "WebView not connected"
            return
        }

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

        // Fetch localStorage
        if let localData = await fetchStorage(type: .localStorage, navigator: navigator) {
            newItems.append(contentsOf: localData)
        } else if !didChangeURL {
            newItems.append(contentsOf: previousItems.filter { $0.storageType == .localStorage })
        }

        // Fetch sessionStorage
        if let sessionData = await fetchStorage(type: .sessionStorage, navigator: navigator) {
            newItems.append(contentsOf: sessionData)
        } else if !didChangeURL {
            newItems.append(contentsOf: previousItems.filter { $0.storageType == .sessionStorage })
        }

        // Fetch cookies
        if let cookieData = await fetchCookies(
            navigator: navigator,
            pageURL: pageURL
        ) {
            newItems.append(contentsOf: cookieData)
        } else if !didChangeURL {
            newItems.append(contentsOf: previousItems.filter { $0.storageType == .cookies })
        }

        // Update items atomically
        items = newItems
        lastRefreshTime = Date()
    }

    private func fetchStorage(
        type: StorageItem.StorageType,
        navigator: StorageNavigator
    ) async -> [StorageItem]? {
        let storageName = type == .localStorage ? "localStorage" : "sessionStorage"
        let script = """
            (function() {
                try {
                    var result = [];
                    for (var i = 0; i < \(storageName).length; i++) {
                        var key = \(storageName).key(i);
                        var value = \(storageName).getItem(key);
                        result.push({ key: key, value: value });
                    }
                    return JSON.stringify(result);
                } catch(e) {
                    return JSON.stringify({ error: e.message });
                }
            })();
            """

        guard let result = await navigator.evaluateJavaScript(script) as? String,
              let data = result.data(using: .utf8) else {
            return nil
        }

        // Check for error
        if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let error = errorDict["error"] {
            await MainActor.run {
                self.errorMessage = "\(type.label): \(error)"
            }
            return nil
        }

        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return nil
        }

        return items.compactMap { dict in
            guard let key = dict["key"], let value = dict["value"] else { return nil }
            return StorageItem(key: key, value: value, storageType: type)
        }
    }

    private func fetchCookies(
        navigator: StorageNavigator,
        pageURL: URL?
    ) async -> [StorageItem]? {
        // Use native WKHTTPCookieStore for full cookie metadata (global cookie list)
        let cookies = await navigator.getAllCookies()
        guard let host = pageURL?.host?.lowercased() else {
            return []
        }

        let filtered = cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            if domain.hasPrefix(".") {
                let trimmed = String(domain.dropFirst())
                return host == trimmed || host.hasSuffix(".\(trimmed)")
            }
            return host == domain
        }

        return filtered.map { cookie in
            StorageItem(
                key: cookie.name,
                value: cookie.value,
                storageType: .cookies,
                cookieMetadata: CookieMetadata(from: cookie)
            )
        }
    }

    // Set item in storage
    @MainActor
    func setItem(
        key: String,
        value: String,
        type: StorageItem.StorageType,
        cookieMetadata: CookieMetadata? = nil
    ) async -> Bool {
        guard let navigator else { return false }

        // Use JSON encoding for safe JavaScript string escaping
        guard let keyData = try? JSONSerialization.data(withJSONObject: key, options: .fragmentsAllowed),
              let valueData = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed),
              let jsonKey = String(data: keyData, encoding: .utf8),
              let jsonValue = String(data: valueData, encoding: .utf8)
        else { return false }

        let script: String
        switch type {
        case .localStorage:
            script = "localStorage.setItem(\(jsonKey), \(jsonValue)); true;"
        case .sessionStorage:
            script = "sessionStorage.setItem(\(jsonKey), \(jsonValue)); true;"
        case .cookies:
            // Prefer native cookie set when we know domain/path metadata.
            if let cookieMetadata,
               let cookie = makeCookie(
                name: key,
                value: value,
                metadata: cookieMetadata
               ) {
                await navigator.setCookie(cookie)
                return true
            }
            let escapedKey = key.replacingOccurrences(of: "=", with: "%3D")
            let escapedValue = value.replacingOccurrences(of: ";", with: "%3B")
            let cookieString = "\(escapedKey)=\(escapedValue)"
            guard let cookieData = try? JSONSerialization.data(
                withJSONObject: cookieString,
                options: .fragmentsAllowed
            ),
            let jsonCookie = String(data: cookieData, encoding: .utf8) else {
                return false
            }
            script = "document.cookie = \(jsonCookie); true;"
        }

        let result = await navigator.evaluateJavaScript(script)
        return result as? Bool == true
    }

    @MainActor
    func updateItem(_ item: StorageItem, key: String, value: String) async -> Bool {
        guard let navigator else { return false }
        errorMessage = nil
        let success: Bool
        if item.storageType == .cookies {
            if let metadata = item.cookieMetadata,
               let cookie = makeCookie(name: key, value: value, metadata: metadata) {
                let cookies = await navigator.getAllCookies()
                let collision = key != item.key && cookies.contains {
                    $0.name == key && $0.domain == metadata.domain && $0.path == metadata.path
                }
                if collision {
                    success = false
                } else {
                    await navigator.setCookie(cookie)
                    success = await navigator.getAllCookies().contains {
                        $0.name == key && $0.value == value && $0.domain == metadata.domain && $0.path == metadata.path
                    }
                    if success, key != item.key {
                        await navigator.deleteCookie(name: item.key, domain: metadata.domain, path: metadata.path)
                    }
                }
            } else {
                success = false
            }
        } else {
            guard let data = try? JSONSerialization.data(withJSONObject: [item.key, key, value]),
                  let arguments = String(data: data, encoding: .utf8) else { return false }
            let storage = item.storageType == .localStorage ? "localStorage" : "sessionStorage"
            // Keep the rename in one document and retain the original if the write fails.
            let script = """
            (function() {
                const [oldKey, newKey, value] = \(arguments);
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

    // Remove item from storage
    @MainActor
    func removeItem(
        key: String,
        type: StorageItem.StorageType,
        cookieMetadata: CookieMetadata? = nil
    ) async -> Bool {
        guard let navigator else { return false }

        // Use native WKHTTPCookieStore for cookies (more reliable)
        if type == .cookies {
            // Match by name + optional domain/path to avoid cross-domain deletes.
            await navigator.deleteCookie(
                name: key,
                domain: cookieMetadata?.domain,
                path: cookieMetadata?.path
            )
            return true
        }

        guard let keyData = try? JSONSerialization.data(withJSONObject: key, options: .fragmentsAllowed),
              let jsonKey = String(data: keyData, encoding: .utf8) else {
            return false
        }

        let script: String
        switch type {
        case .localStorage:
            script = "localStorage.removeItem(\(jsonKey)); true;"
        case .sessionStorage:
            script = "sessionStorage.removeItem(\(jsonKey)); true;"
        case .cookies:
            return false  // Handled above
        }

        let result = await navigator.evaluateJavaScript(script)
        return result as? Bool == true
    }

    // Clear all items of a type
    @MainActor
    func clearStorage(type: StorageItem.StorageType) async -> Bool {
        guard let navigator else { return false }

        // Use native WKHTTPCookieStore for cookies (more reliable)
        if type == .cookies {
            await navigator.deleteAllCookies()
            return true
        }

        let script: String
        switch type {
        case .localStorage:
            script = "localStorage.clear(); true;"
        case .sessionStorage:
            script = "sessionStorage.clear(); true;"
        case .cookies:
            return false  // Handled above
        }

        let result = await navigator.evaluateJavaScript(script)
        return result as? Bool == true
    }

    @MainActor
    func clearCookies(forDomain domain: String) async -> Bool {
        guard let navigator else { return false }
        await navigator.deleteCookies(forDomain: domain)
        return true
    }

    func clear() {
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

struct StorageView: View {
    let storageManager: StorageManager
    let navigator: WebViewNavigator?
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: StorageItem.StorageType = .localStorage
    @State private var showsAllStorage: Bool = false
    @State private var searchText: String = ""
    @State private var shareItem: StorageShareContent?
    @State private var selectedItem: StorageItem?
    @State private var showAddSheet: Bool = false
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
        .sheet(item: $selectedItem) { item in
            StorageEditSheet(
                item: item,
                storageManager: storageManager,
                onSave: {
                    Task { await storageManager.refresh(pageURL: navigator?.currentURL) }
                },
                onDelete: {
                    Task { await storageManager.refresh(pageURL: navigator?.currentURL) }
                }
            )
        }
        .sheet(isPresented: $showAddSheet) {
            StorageAddSheet(
                storageManager: storageManager,
                storageType: selectedType,
                onSave: {
                    Task { await storageManager.refresh(pageURL: navigator?.currentURL) }
                }
            )
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

    // MARK: - Storage Header

    private var storageHeaderLeftButtons: [DevToolsHeader.HeaderButton] {
        var buttons: [DevToolsHeader.HeaderButton] = [
            .init(icon: "xmark.circle.fill", color: .secondary) {
                dismiss()
            },
            .init(
                icon: "trash",
                isDisabled: filteredItems.isEmpty || showsAllStorage
            ) {
                Task {
                    if selectedType == .cookies {
                        // For cookies: clear current domain only
                        guard let host = currentHost else { return }
                        if await storageManager.clearCookies(forDomain: host) {
                            await storageManager.refresh(pageURL: navigator?.currentURL)
                        }
                    } else {
                        // For localStorage/sessionStorage: clear all
                        if await storageManager.clearStorage(type: selectedType) {
                            await storageManager.refresh(pageURL: navigator?.currentURL)
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
                    isDisabled: showsAllStorage
                ) {
                    showAddSheet = true
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
                                    onEdit: { selectedItem = $0 },
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
                            onEdit: { selectedItem = $0 },
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
            if await storageManager.removeItem(
                key: item.key,
                type: item.storageType,
                cookieMetadata: item.cookieMetadata
            ) {
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
    return StorageView(storageManager: manager, navigator: nil)
        .devToolsSheet()
}
