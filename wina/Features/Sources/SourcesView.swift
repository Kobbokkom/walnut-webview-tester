//
//  SourcesView.swift
//  wina
//
//  Chrome DevTools style Sources panel - DOM Tree, Stylesheets, Scripts.
//

import SwiftUI

// MARK: - Source Tab

enum SourceTab: String, CaseIterable {
    case elements = "Elements"
    case styles = "Styles"
    case scripts = "Scripts"

    var icon: String {
        switch self {
        case .elements: return "chevron.left.forwardslash.chevron.right"
        case .styles: return "paintbrush"
        case .scripts: return "doc.text"
        }
    }
}

// MARK: - Elements View Mode

enum ElementsViewMode: String, CaseIterable {
    case tree = "Tree"
    case raw = "Raw HTML"

    var icon: String {
        switch self {
        case .tree: return "list.bullet.indent"
        case .raw: return "doc.plaintext"
        }
    }
}

// MARK: - Sources View

struct SourcesView: View {
    let navigator: WebViewNavigator?

    @Environment(\.closeDevTools) private var closeDevTools
    @Environment(\.dismiss) private var dismiss
    @State var manager = SourcesManager()
    @State private var selectedTab: SourceTab = .elements
    @State private var shareItem: SourcesShareContent?
    @State private var lastURL: URL?
    @State var searchText: String = ""
    @State var debouncedSearchText: String = ""

    // Elements view mode (tree vs raw HTML)
    @State var elementsViewMode: ElementsViewMode = .tree

    // Search navigation for Elements (Tree mode)
    @State var currentMatchIndex: Int = 0
    @State var matchingNodePaths: [[String]] = []

    // Search navigation for Elements (Raw HTML mode)
    @State var currentRawMatchIndex: Int = 0
    @State var rawMatchLineIndices: [Int] = []
    @State var cachedRawHTMLLines: [String] = []

    // Detail view selections
    @State private var selectedNode: DOMNode?
    @State private var selectedStylesheet: StylesheetInfo?
    @State private var selectedScript: ScriptInfo?

    // Breadcrumbs navigation
    @State var breadcrumbPath: [DOMNode] = []

    // Search task for cancellation (prevents race conditions)
    @State var searchTask: Task<Void, Never>?
    // Scroll task for cancellation (prevents stale scrolls)
    @State var scrollTask: Task<Void, Never>?

    // Centralized expand state for DOM tree nodes
    // This allows expanding entire paths at once when navigating to deep matches
    @State var expandedNodeIds: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            sourcesHeader

            searchBar

            tabPicker

            Divider()

            // Content based on selected tab
            Group {
                switch selectedTab {
                case .elements:
                    elementsContent
                case .styles:
                    stylesContent
                case .scripts:
                    scriptsContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .dismissKeyboardOnTap()
        .onAppear {
            manager.setNavigator(navigator)
            lastURL = navigator?.currentURL
            Task {
                await fetchCurrentTab()
            }
        }
        .task {
            await AdManager.shared.showInterstitialAd(
                options: AdOptions(id: "sources_devtools"),
                adUnitId: AdManager.interstitialAdUnitId
            )
        }
        .task(id: searchText) {
            // Debounce search: wait 400ms before processing
            guard !searchText.isEmpty else {
                debouncedSearchText = ""
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText
        }
        .onChange(of: selectedTab) { _, _ in
            // Clear search when switching tabs
            searchText = ""
            currentMatchIndex = 0
            matchingNodePaths = []
            currentRawMatchIndex = 0
            rawMatchLineIndices = []
            breadcrumbPath = []
            expandedNodeIds = []

            Task {
                await fetchCurrentTab()
            }
        }
        .onChange(of: debouncedSearchText) { _, _ in
            // Trigger search when debounced text changes
            if selectedTab == .elements {
                if elementsViewMode == .tree {
                    updateMatchingNodes()
                } else {
                    updateRawHTMLMatches()
                }
            }
        }
        .onChange(of: manager.domTreeRevision) { _, _ in
            // Update search results when DOM tree reloads
            if !debouncedSearchText.isEmpty && elementsViewMode == .tree {
                updateMatchingNodes()
            }
        }
        .onChange(of: manager.rawHTML) { _, newHTML in
            // Cache raw HTML lines for search
            // Use "\n" instead of .newlines to match Runestone's line parsing
            if let html = newHTML {
                cachedRawHTMLLines = html.components(separatedBy: "\n")
                // Update search results if needed
                if !debouncedSearchText.isEmpty && elementsViewMode == .raw {
                    updateRawHTMLMatches()
                }
            } else {
                cachedRawHTMLLines = []
            }
        }
        .onChange(of: elementsViewMode) { _, newMode in
            // Clear breadcrumbs when switching view modes
            breadcrumbPath = []

            // Update search results when view mode changes
            if !debouncedSearchText.isEmpty {
                if newMode == .tree {
                    updateMatchingNodes()
                } else {
                    updateRawHTMLMatches()
                }
            }
        }
        .onChange(of: navigator?.currentURL) { _, newURL in
            // Auto-refresh when page URL changes
            if let newURL, newURL != lastURL {
                lastURL = newURL
                breadcrumbPath = []
                expandedNodeIds = []
                Task {
                    // Small delay to let page load
                    try? await Task.sleep(for: .milliseconds(500))
                    await fetchCurrentTab()
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(content: item.content)
        }
        .sheet(item: $selectedNode) { node in
            ElementDetailView(node: node, navigator: navigator)
                .devToolsSheet()
        }
        .sheet(item: $selectedStylesheet) { sheet in
            StylesheetDetailView(sheet: sheet, index: sheet.index, navigator: navigator)
                .devToolsSheet()
        }
        .sheet(item: $selectedScript) { script in
            ScriptDetailView(script: script, index: script.index, navigator: navigator)
                .devToolsSheet()
        }
    }

    private func fetchCurrentTab() async {
        switch selectedTab {
        case .elements:
            if elementsViewMode == .tree {
                await manager.fetchDOMTree()
            } else {
                await manager.fetchRawHTML()
            }
        case .styles:
            await manager.fetchStylesheets()
        case .scripts:
            await manager.fetchScripts()
        }
    }

    private var currentItemCount: Int {
        switch selectedTab {
        case .elements:
            return manager.domTree != nil ? 1 : 0
        case .styles:
            return filteredStylesheets.count
        case .scripts:
            return filteredScripts.count
        }
    }

    private var filteredStylesheets: [StylesheetInfo] {
        guard !debouncedSearchText.isEmpty else { return manager.stylesheets }
        let query = debouncedSearchText
        return manager.stylesheets.filter { sheet in
            // Search in href (URL), mediaText, and CSS content
            sheet.href?.localizedCaseInsensitiveContains(query) == true ||
            sheet.mediaText?.localizedCaseInsensitiveContains(query) == true ||
            sheet.cssContent?.localizedCaseInsensitiveContains(query) == true
        }
    }

    private var filteredScripts: [ScriptInfo] {
        guard !debouncedSearchText.isEmpty else { return manager.scripts }
        let query = debouncedSearchText
        return manager.scripts.filter { script in
            // Search in src (URL) and inline script content
            script.src?.localizedCaseInsensitiveContains(query) == true ||
            script.content?.localizedCaseInsensitiveContains(query) == true
        }
    }

    private func shareCurrentTab() {
        var content = ""
        switch selectedTab {
        case .elements:
            if elementsViewMode == .raw, let html = manager.rawHTML {
                content = html
            } else if let root = manager.domTree {
                content = DOMTreeSerializer.serialize(root)
            }
        case .styles:
            content = filteredStylesheets
                .map { $0.href ?? "<style> tag (\($0.rulesCount) rules)" }
                .joined(separator: "\n")
        case .scripts:
            content = filteredScripts
                .map { $0.src ?? "<inline script>" }
                .joined(separator: "\n")
        }
        shareItem = SourcesShareContent(content: content)
    }

    // MARK: - Header

    private var sourcesHeader: some View {
        DevToolsHeader(
            title: "Sources",
            leftButtons: [
                .init(icon: "xmark.circle.fill", color: .secondary) {
                    (closeDevTools ?? { dismiss() })()
                },
                .init(icon: "arrow.clockwise") {
                    Task {
                        await fetchCurrentTab()
                    }
                },
                .init(
                    icon: "square.and.arrow.up",
                    isDisabled: currentItemCount == 0
                ) {
                    shareCurrentTab()
                }
            ],
            rightButtons: []
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(selectedTab == .elements ? "Search" : "Filter", text: $searchText)
                .textFieldStyle(.plain)

            // Search navigation - always reserve space (use debounced for stability)
            Group {
                if selectedTab == .elements && !debouncedSearchText.isEmpty {
                    searchNavigationView
                }
            }
            .frame(minWidth: 100, alignment: .trailing)

            // Clear button - always reserve space
            Button {
                clearSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(searchText.isEmpty ? 0 : 1)
            .disabled(searchText.isEmpty)

            Divider()
                .frame(height: 20)
                .opacity(selectedTab == .elements ? 1 : 0)

            // View mode toggle - always reserve space
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    elementsViewMode = elementsViewMode == .tree ? .raw : .tree
                }
                Task {
                    await fetchCurrentTab()
                }
            } label: {
                Image(systemName: elementsViewMode.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(elementsViewMode == .raw ? .primary : .secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(selectedTab == .elements ? 1 : 0)
            .disabled(selectedTab != .elements)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var searchNavigationView: some View {
        if elementsViewMode == .tree {
            treeSearchNavigation
        } else {
            rawHTMLSearchNavigation
        }
    }

    @ViewBuilder
    private var treeSearchNavigation: some View {
        if matchingNodePaths.isEmpty {
            SearchMatchCountBadge(text: "0")
        } else {
            HStack(spacing: 4) {
                SearchMatchCountBadge(text: "\(currentMatchIndex + 1)/\(matchingNodePaths.count)")
                SearchNavigationButtons(
                    onPrevious: navigateToPreviousMatch,
                    onNext: navigateToNextMatch,
                    isDisabled: matchingNodePaths.count <= 1
                )
            }
        }
    }

    @ViewBuilder
    private var rawHTMLSearchNavigation: some View {
        if rawMatchLineIndices.isEmpty {
            SearchMatchCountBadge(text: "0")
        } else {
            HStack(spacing: 4) {
                SearchMatchCountBadge(text: "\(currentRawMatchIndex + 1)/\(rawMatchLineIndices.count)")
                SearchNavigationButtons(
                    onPrevious: navigateToPreviousRawMatch,
                    onNext: navigateToNextRawMatch,
                    isDisabled: rawMatchLineIndices.count <= 1
                )
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(SourceTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12))
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.ultraThinMaterial)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Elements Content

    @ViewBuilder
    private var elementsContent: some View {
        if manager.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
        } else if let error = manager.errorMessage {
            SourcesErrorView(message: error)
        } else {
            switch elementsViewMode {
            case .tree:
                if let root = manager.domTree {
                    VStack(spacing: 0) {
                        // Breadcrumbs bar
                        if !breadcrumbPath.isEmpty {
                            breadcrumbsBar
                        }

                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    DOMNodeRow(
                                        node: root,
                                        depth: 0,
                                        manager: manager,
                                        searchText: debouncedSearchText,
                                        currentMatchPath: currentMatchPath,
                                        onSelect: { node in
                                            selectedNode = node
                                        },
                                        onBreadcrumbTap: { node in
                                            updateBreadcrumbs(for: node, root: root)
                                        },
                                        expandedNodeIds: $expandedNodeIds
                                    )
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .onChange(of: currentMatchIndex) { _, _ in
                                expandPathToCurrentMatch()
                                scrollToCurrentMatch(proxy: proxy)
                            }
                            .onChange(of: matchingNodePaths) { _, newPaths in
                                // Auto-scroll to first match when search results appear
                                if !newPaths.isEmpty {
                                    expandPathToCurrentMatch()
                                    scrollToCurrentMatch(proxy: proxy)
                                }
                            }
                            .onChange(of: breadcrumbPath) { _, newPath in
                                // Scroll to the last breadcrumb node (use row- prefix)
                                if let last = newPath.last {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        proxy.scrollTo("row-\(last.id)", anchor: .top)
                                    }
                                }
                            }
                        }
                    }
                    .background(Color(uiColor: .systemBackground))
                } else {
                    SourcesEmptyView(message: "No DOM tree available")
                }
            case .raw:
                if let html = manager.rawHTML {
                    HTMLSyntaxView(
                        html: html,
                        searchText: debouncedSearchText,
                        currentMatchLineIndex: rawMatchLineIndices.isEmpty ? nil : currentRawMatchIndex,
                        matchingLineIndices: rawMatchLineIndices
                    )
                } else {
                    SourcesEmptyView(message: "No HTML available")
                }
            }
        }
    }

    // MARK: - Breadcrumbs

    private var breadcrumbsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(breadcrumbPath.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }

                    Button {
                        // Trim breadcrumb path to this node
                        breadcrumbPath = Array(breadcrumbPath.prefix(index + 1))
                    } label: {
                        Text(node.displayName)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(index == breadcrumbPath.count - 1 ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 32)
        }
        .contentMargins(.horizontal, 12, for: .scrollContent)
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.leading)
        .background(.ultraThinMaterial)
    }

    // MARK: - Styles Content

    @ViewBuilder
    private var stylesContent: some View {
        if manager.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
        } else if let error = manager.errorMessage {
            SourcesErrorView(message: error)
        } else if manager.stylesheets.isEmpty {
            SourcesEmptyView(message: "No stylesheets found")
        } else if filteredStylesheets.isEmpty {
            SourcesEmptyView(message: debouncedSearchText.isEmpty ? "No stylesheets found" : "No matches")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredStylesheets) { sheet in
                        StylesheetRow(sheet: sheet)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedStylesheet = sheet
                            }
                        Divider()
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
        }
    }

    // MARK: - Scripts Content

    @ViewBuilder
    private var scriptsContent: some View {
        if manager.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
        } else if let error = manager.errorMessage {
            SourcesErrorView(message: error)
        } else if filteredScripts.isEmpty {
            SourcesEmptyView(message: debouncedSearchText.isEmpty ? "No scripts found" : "No matches")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredScripts) { script in
                        ScriptRow(script: script)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedScript = script
                            }
                        Divider()
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
        }
    }

}

// MARK: - Share Content

struct SourcesShareContent: Identifiable {
    let id = UUID()
    let content: String
}

// MARK: - Preview

#Preview {
    SourcesView(navigator: nil)
}
