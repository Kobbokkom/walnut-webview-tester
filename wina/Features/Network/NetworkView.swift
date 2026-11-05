//
//  NetworkView.swift
//  wina
//
//  Network and resource monitoring view for WKWebView.
//  Captures fetch/XMLHttpRequest via JavaScript injection and resources via Resource Timing API.
//

import SwiftUI
import SwiftUIBackports

// MARK: - Combined Filter

enum NetworkResourceFilter: String, CaseIterable, Identifiable {
    // Network filters
    case all
    case fetchXhr  // Combined Fetch/XHR like Chrome DevTools
    case doc
    // Resource filters
    case img
    case js
    case css
    case font
    case media
    case other
    // Status filters
    case errors
    case mixed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: "All"
        case .fetchXhr: "Fetch/XHR"
        case .doc: "Doc"
        case .img: "Img"
        case .js: "JS"
        case .css: "CSS"
        case .font: "Font"
        case .media: "Media"
        case .other: "Other"
        case .errors: "Errors"
        case .mixed: "Mixed"
        }
    }

    var isNetworkFilter: Bool {
        switch self {
        case .all, .fetchXhr, .doc, .errors, .mixed: true
        default: false
        }
    }

    var isResourceFilter: Bool {
        switch self {
        case .img, .js, .css, .font, .media, .other: true
        default: false
        }
    }

    var color: Color {
        switch self {
        case .errors: .red
        case .mixed: .orange
        default: .primary
        }
    }

    func matchesNetworkRequest(_ request: NetworkRequest) -> Bool {
        switch self {
        case .all: true
        case .fetchXhr: request.requestType == .fetch || request.requestType == .xhr
        case .doc: request.requestType == .document
        case .errors: request.error != nil || (request.status ?? 0) >= 400
        case .mixed: request.isMixedContent
        default: false
        }
    }

    func matchesResource(_ resource: ResourceEntry) -> Bool {
        switch self {
        case .all: true
        case .img: resource.initiatorType == .img
        case .js: resource.initiatorType == .script
        case .css: resource.initiatorType == .link || resource.initiatorType == .css
        case .font: resource.initiatorType == .font
        case .media: resource.initiatorType == .video || resource.initiatorType == .audio
        case .other: resource.initiatorType == .other || resource.initiatorType == .beacon
        default: false
        }
    }
}

// MARK: - Network View

struct NetworkView: View {
    let networkManager: NetworkManager
    let resourceManager: ResourceManager
    @Environment(\.dismiss) private var dismiss
    @State private var filter: NetworkResourceFilter = .all
    @State private var searchText: String = ""
    @State private var shareItem: NetworkShareContent?
    @State private var showSettings: Bool = false
    @State private var selectedRequest: NetworkRequest?
    @State private var selectedResource: ResourceEntry?
    @AppStorage("networkPreserveLog") private var preserveLog: Bool = false
    @AppStorage(LogClearStrategy.networkDefaultsKey) private var clearStrategyRaw: String = LogClearStrategy.keep.rawValue
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollViewHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy?

    // MARK: - Filtered Data

    private var filteredRequests: [NetworkRequest] {
        guard filter.isNetworkFilter || filter == .all else { return [] }

        var result = networkManager.requests

        if filter != .all {
            result = result.filter { filter.matchesNetworkRequest($0) }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.url.localizedCaseInsensitiveContains(searchText)
                    || $0.method.localizedCaseInsensitiveContains(searchText)
                    || ($0.statusText?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return result
    }

    private var filteredResources: [ResourceEntry] {
        guard filter.isResourceFilter else { return [] }

        var result = resourceManager.resources
        result = result.filter { filter.matchesResource($0) }

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    /// Resources shown in "All" filter - excludes fetch/xhr to avoid duplication with network requests
    private var allFilterResources: [ResourceEntry] {
        guard filter == .all else { return [] }

        var result = resourceManager.resources.filter {
            $0.initiatorType != .fetch && $0.initiatorType != .xmlhttprequest
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    private var showingNetworkData: Bool {
        filter == .all || filter.isNetworkFilter
    }

    private var showingResourceData: Bool {
        filter == .all || filter.isResourceFilter
    }

    private var hasAnyData: Bool {
        !networkManager.requests.isEmpty || !resourceManager.resources.isEmpty
    }

    private var hasFilteredData: Bool {
        !filteredRequests.isEmpty || !filteredResources.isEmpty || !allFilterResources.isEmpty
    }

    private var settingsActive: Bool {
        preserveLog || clearStrategyRaw != LogClearStrategy.keep.rawValue
    }

    private var isCapturing: Bool {
        networkManager.isCapturing && resourceManager.isCapturing
    }

    // MARK: - Counts

    private func count(for filterType: NetworkResourceFilter) -> Int {
        switch filterType {
        case .all:
            networkManager.requests.count + resourceManager.resources.count
        case .fetchXhr:
            networkManager.requests.filter { $0.requestType == .fetch || $0.requestType == .xhr }.count
        case .doc:
            networkManager.requests.filter { $0.requestType == .document }.count
        case .img:
            resourceManager.count(for: .img)
        case .js:
            resourceManager.count(for: .script)
        case .css:
            resourceManager.count(for: .css)
        case .font:
            resourceManager.count(for: .font)
        case .media:
            resourceManager.count(for: .media)
        case .other:
            resourceManager.count(for: .other) + networkManager.requests.filter { $0.requestType == .other }.count
        case .errors:
            networkManager.errorCount
        case .mixed:
            networkManager.mixedContentCount
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            networkHeader
            searchBar
            filterTabs

            Divider()

            if !hasFilteredData {
                emptyState
            } else {
                contentList
            }
        }
        .dismissKeyboardOnTap()
        .sheet(item: $shareItem) { item in
            ExportContentSheet(content: item.content)
        }
        .sheet(isPresented: $showSettings) {
            NetworkSettingsSheet()
        }
        .sheet(item: $selectedRequest) { request in
            LiveNetworkDetailView(manager: networkManager, requestID: request.id)
        }
        .sheet(item: $selectedResource) { resource in
            ResourceDetailView(resource: resource)
        }
        .task {
            await AdManager.shared.showInterstitialAd(
                options: AdOptions(id: "network_devtools"),
                adUnitId: AdManager.interstitialAdUnitId
            )
        }
    }

    // MARK: - Network Header

    private var networkHeader: some View {
        DevToolsHeader(
            title: "Network",
            leftButtons: [
                .init(icon: "xmark.circle.fill", color: .secondary) {
                    dismiss()
                },
                .init(
                    icon: "trash",
                    isDisabled: !hasAnyData
                ) {
                    networkManager.clear()
                    resourceManager.clear()
                },
                .init(
                    icon: "square.and.arrow.up",
                    isDisabled: !hasAnyData
                ) {
                    shareItem = NetworkShareContent(content: exportAsText())
                }
            ],
            rightButtons: [
                .init(
                    icon: "play.fill",
                    activeIcon: "pause.fill",
                    color: .green,
                    activeColor: .red,
                    isActive: isCapturing
                ) {
                    networkManager.isCapturing.toggle()
                    resourceManager.isCapturing.toggle()
                },
                .init(
                    icon: "gearshape",
                    activeIcon: "gearshape.fill",
                    isActive: settingsActive
                ) {
                    showSettings = true
                }
            ]
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter", text: $searchText)
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
        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Filter Tabs

    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                // All tab
                NetworkFilterTab(
                    label: "All",
                    count: count(for: .all),
                    isSelected: filter == .all
                ) {
                    filter = .all
                }

                // Network request tabs
                ForEach([NetworkResourceFilter.fetchXhr, .doc], id: \.self) { filterType in
                    NetworkFilterTab(
                        label: filterType.displayName,
                        count: count(for: filterType),
                        isSelected: filter == filterType
                    ) {
                        filter = filterType
                    }
                }

                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 4)

                // Resource tabs
                ForEach([NetworkResourceFilter.img, .js, .css, .font, .media], id: \.self) { filterType in
                    NetworkFilterTab(
                        label: filterType.displayName,
                        count: count(for: filterType),
                        isSelected: filter == filterType
                    ) {
                        filter = filterType
                    }
                }

                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 4)

                // Status tabs
                NetworkFilterTab(
                    label: "Errors",
                    count: count(for: .errors),
                    isSelected: filter == .errors,
                    color: .red
                ) {
                    filter = .errors
                }

                if networkManager.pageIsSecure {
                    NetworkFilterTab(
                        label: "Mixed",
                        count: count(for: .mixed),
                        isSelected: filter == .mixed,
                        color: .orange
                    ) {
                        filter = .mixed
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 36)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Image(systemName: "network")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text(!hasAnyData ? "No activity" : "No matches")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !isCapturing {
                        Label("Paused", systemImage: "pause.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width)
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Content List

    private var contentList: some View {
        ScrollViewReader { proxy in
            GeometryReader { outerGeo in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Show network requests for network filters
                        if showingNetworkData {
                            ForEach(filteredRequests) { request in
                                NetworkRequestRow(request: request)
                                    .id("request-\(request.id)")
                                    .onTapGesture {
                                        selectedRequest = request
                                    }
                            }
                        }

                        // Show resources for resource filters (but not for "All" to avoid duplication with XHR/Fetch)
                        if showingResourceData && filter != .all {
                            ForEach(filteredResources) { resource in
                                ResourceRow(resource: resource)
                                    .id("resource-\(resource.id)")
                                    .onTapGesture {
                                        selectedResource = resource
                                    }
                            }
                        }

                        // For "All" filter, only show resources that aren't captured by Network (exclude fetch/xhr)
                        ForEach(allFilterResources) { resource in
                            ResourceRow(resource: resource)
                                .id("resource-\(resource.id)")
                                .onTapGesture {
                                    selectedResource = resource
                                }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        GeometryReader { innerGeo in
                            Color.clear
                                .onAppear {
                                    contentHeight = innerGeo.size.height
                                }
                                .onChange(of: innerGeo.size.height) { _, newHeight in
                                    contentHeight = newHeight
                                }
                        }
                    )
                }
                .background(Color(uiColor: .systemBackground))
                .scrollContentBackground(.hidden)
                .onScrollGeometryChange(for: Double.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, newValue in
                    scrollOffset = newValue
                }
                .onAppear {
                    scrollViewHeight = outerGeo.size.height
                }
                .onChange(of: outerGeo.size.height) { _, newHeight in
                    scrollViewHeight = newHeight
                }
                .onChange(of: networkManager.requests.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: resourceManager.resources.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .scrollNavigationOverlay(
                    scrollOffset: scrollOffset,
                    contentHeight: contentHeight,
                    viewportHeight: scrollViewHeight,
                    onScrollUp: { scrollUp(proxy: scrollProxy) },
                    onScrollDown: { scrollDown(proxy: scrollProxy) }
                )
            }
            .onAppear {
                scrollProxy = proxy
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollUp(proxy: ScrollViewProxy?) {
        guard let proxy else { return }

        var firstID: String?

        if showingNetworkData && !filteredRequests.isEmpty {
            firstID = "request-\(filteredRequests.first!.id)"
        } else if showingResourceData && filter != .all && !filteredResources.isEmpty {
            firstID = "resource-\(filteredResources.first!.id)"
        } else if filter == .all && !allFilterResources.isEmpty {
            firstID = "resource-\(allFilterResources.first!.id)"
        }

        if let id = firstID {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .top)
            }
        }
    }

    private func scrollDown(proxy: ScrollViewProxy?) {
        guard let proxy else { return }

        var lastID: String?

        if filter == .all {
            if !allFilterResources.isEmpty {
                lastID = "resource-\(allFilterResources.last!.id)"
            } else if !filteredRequests.isEmpty {
                lastID = "request-\(filteredRequests.last!.id)"
            }
        } else if showingResourceData && !filteredResources.isEmpty {
            lastID = "resource-\(filteredResources.last!.id)"
        } else if showingNetworkData && !filteredRequests.isEmpty {
            lastID = "request-\(filteredRequests.last!.id)"
        }

        if let id = lastID {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy?) {
        // Get the last item ID based on current filter
        var lastID: String?

        if showingNetworkData, let lastRequest = filteredRequests.last {
            lastID = "request-\(lastRequest.id)"
        }

        if showingResourceData, let lastResource = filteredResources.last {
            lastID = "resource-\(lastResource.id)"
        }

        // For "All" filter, check allFilterResources
        if filter == .all, let lastResource = allFilterResources.last {
            lastID = "resource-\(lastResource.id)"
        }

        if let lastID, let proxy {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    // MARK: - Export

    private func exportAsText() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"

        // Build header with filter info
        var header = "Network & Resources Export"
        if filter != .all {
            header += " (Filter: \(filter.displayName))"
        }
        if !searchText.isEmpty {
            header += " (Search: \(searchText))"
        }
        header += "\nExported: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))"
        header += "\nRequests: \(filteredRequests.count), Resources: \(filteredResources.count)"
        header += "\n" + String(repeating: "─", count: 50) + "\n\n"

        // Network requests
        var body = ""
        if !filteredRequests.isEmpty {
            body += "=== NETWORK REQUESTS ===\n\n"
            body += filteredRequests
                .map { req in
                    var line = "[\(dateFormatter.string(from: req.startTime))] \(req.method) \(req.url)"
                    if let status = req.status {
                        line += " → \(status)"
                    }
                    if let duration = req.duration {
                        line += " (\(String(format: "%.0fms", duration * 1000)))"
                    }
                    if let error = req.error {
                        line += " ERROR: \(error)"
                    }
                    return line
                }
                .joined(separator: "\n\n")
        }

        // Resources
        let resourcesToExport = filter == .all ? allFilterResources : filteredResources

        if !resourcesToExport.isEmpty {
            if !body.isEmpty { body += "\n\n" }
            body += "=== RESOURCES ===\n\n"
            body += resourcesToExport
                .map { res in
                    var line = "[\(res.initiatorType.displayName)] \(res.name)"
                    line += "\n  Duration: \(res.displayDuration)"
                    line += ", Size: \(res.displaySize)"
                    if res.isCrossOriginRestricted {
                        line += " (cross-origin)"
                    }
                    return line
                }
                .joined(separator: "\n\n")
        }

        return header + body
    }
}

// MARK: - Network Filter Tab

private struct NetworkFilterTab: View {
    let label: String
    let count: Int
    let isSelected: Bool
    var color: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                if count != 0 {  // swiftlint:disable:this empty_count
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            isSelected ? color.opacity(0.2) : Color.secondary.opacity(0.15),
                            in: Capsule()
                        )
                }
            }
            .foregroundStyle(isSelected ? color : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(color)
                        .frame(height: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Network Request Row

private struct NetworkRequestRow: View {
    let request: NetworkRequest

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Status indicator (subtle)
            Circle()
                .fill(request.isPending ? Color.orange.opacity(0.6) : (request.error != nil ? Color.red.opacity(0.6) : Color.secondary.opacity(0.3)))
                .frame(width: 6, height: 6)

            // Method badge
            Text(request.method)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(methodTextColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(methodColor, in: RoundedRectangle(cornerRadius: 4))

            // URL
            VStack(alignment: .leading, spacing: 2) {
                Text(request.path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(request.host)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Right side info
            VStack(alignment: .trailing, spacing: 2) {
                // Status code or pending
                if let status = request.status {
                    Text("\(status)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(request.statusColor)
                } else if request.error != nil {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                } else {
                    ProgressView()
                        .scaleEffect(0.6)
                }

                // Duration
                Text(request.durationText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            // Response content type
            Text(request.responseContentType)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(request.responseContentTypeColor)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(request.error != nil ? Color.red.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 12)
        }
    }

    private var methodColor: Color {
        switch request.method {
        case "GET": return .blue.opacity(0.15)
        case "POST": return .green.opacity(0.15)
        case "PUT": return .orange.opacity(0.15)
        case "DELETE": return .red.opacity(0.15)
        case "PATCH": return .purple.opacity(0.15)
        default: return .secondary.opacity(0.1)
        }
    }

    private var methodTextColor: Color {
        switch request.method {
        case "GET": return .blue.opacity(0.9)
        case "POST": return .green.opacity(0.9)
        case "PUT": return .orange.opacity(0.9)
        case "DELETE": return .red.opacity(0.9)
        case "PATCH": return .purple.opacity(0.9)
        default: return .secondary
        }
    }
}

// MARK: - Resource Row

private struct ResourceRow: View {
    let resource: ResourceEntry

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Type icon (monochrome)
            Image(systemName: resource.initiatorType.icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            // Resource info
            VStack(alignment: .leading, spacing: 2) {
                Text(resource.displayName)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let host = resource.host {
                    Text(host)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Right side info
            VStack(alignment: .trailing, spacing: 2) {
                Text(resource.displayDuration)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(resource.displaySize)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            // Type badge (only colored element)
            Text(resource.initiatorType.displayName)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(resource.initiatorType.color)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 12)
        }
    }
}

// MARK: - Network Settings Sheet

private struct NetworkSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("networkPreserveLog") private var preserveLog: Bool = false
    @AppStorage(LogClearStrategy.networkDefaultsKey) private var clearStrategyRaw: String = LogClearStrategy.keep.rawValue

    private var clearStrategy: Binding<LogClearStrategy> {
        Binding(
            get: { LogClearStrategy(rawValue: clearStrategyRaw) ?? .keep },
            set: { clearStrategyRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Logging") {
                    HStack {
                        Picker("Clear Strategy", selection: clearStrategy) {
                            ForEach(LogClearStrategy.allCases, id: \.self) { strategy in
                                Text(strategy.displayName).tag(strategy)
                            }
                        }
                        InfoPopoverButton(
                            text: """
                            When to clear logs during navigation:
                            • Keep All: Manual clear only
                            • Same Origin: Clear when leaving domain
                            • Each Page: Clear on every navigation
                            """
                        )
                    }

                    HStack {
                        Toggle("Preserve on Reload", isOn: $preserveLog)
                        InfoPopoverButton(text: "Keep logs when the page is reloaded.")
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Network Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Export Content Sheet

private struct ExportContentSheet: View {
    let content: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(content)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(Text(verbatim: "Export"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: content) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

#Preview {
    let networkManager = NetworkManager()
    let resourceManager = ResourceManager()

    networkManager.addRequest(
        id: UUID().uuidString,
        method: "GET",
        url: "https://api.example.com/users",
        requestType: "fetch",
        headers: ["Authorization": "Bearer token123"],
        body: nil
    )

    return NetworkView(networkManager: networkManager, resourceManager: resourceManager)
        .devToolsSheet()
}
