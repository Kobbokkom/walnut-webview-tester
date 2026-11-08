//
//  SnippetsView.swift
//  wina
//
//  Pre-built debugging utilities for quick page inspection.
//  Based on Eruda's Snippets feature.
//

import SwiftUI

// MARK: - Snippet Category

enum SnippetCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case layout = "Layout"
    case content = "Content"
    case debug = "Debug"
    case style = "Style"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .layout: "square.dashed"
        case .content: "doc.text"
        case .debug: "ant"
        case .style: "paintbrush"
        }
    }
}

// MARK: - Snippet Definition

struct DebugSnippet: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let iconColor: Color
    let isToggleable: Bool
    let category: SnippetCategory
    let script: String
    let undoScript: String?

    init(
        id: String,
        name: String,
        description: String,
        icon: String,
        iconColor: Color = .blue,
        isToggleable: Bool = false,
        category: SnippetCategory = .debug,
        script: String,
        undoScript: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.iconColor = iconColor
        self.isToggleable = isToggleable
        self.category = category
        self.script = script
        self.undoScript = undoScript
    }
}

// MARK: - Snippets Manager

@Observable
class SnippetsManager {
    var activeSnippets: Set<String> = []
    private var isExecuting = false

    static let defaultSnippets: [DebugSnippet] = [
        DebugSnippet(
            id: "border_all",
            name: "Border All",
            description: "Add colored borders to all elements for layout debugging",
            icon: "square.dashed",
            iconColor: .orange,
            isToggleable: true,
            category: .layout,
            script: """
                (function() {
                    const id = '__wina_border_style__';
                    if (document.getElementById(id)) return;
                    const style = document.createElement('style');
                    style.id = id;
                    style.textContent = `
                        * { outline: 1px solid rgba(255,0,0,0.3) !important; }
                        *:nth-child(2n) { outline-color: rgba(0,255,0,0.3) !important; }
                        *:nth-child(3n) { outline-color: rgba(0,0,255,0.3) !important; }
                        *:nth-child(4n) { outline-color: rgba(255,255,0,0.3) !important; }
                        *:nth-child(5n) { outline-color: rgba(255,0,255,0.3) !important; }
                    `;
                    document.head.appendChild(style);
                    return 'Borders enabled';
                })();
                """,
            undoScript: """
                (function() {
                    const el = document.getElementById('__wina_border_style__');
                    if (el) el.remove();
                    return 'Borders disabled';
                })();
                """
        ),
        DebugSnippet(
            id: "edit_page",
            name: "Edit Page",
            description: "Make page content editable (contentEditable)",
            icon: "pencil.line",
            iconColor: .green,
            isToggleable: true,
            category: .content,
            script: """
                (function() {
                    const body = document.body;
                    if (!body) return 'No page body to edit';
                    if (!window.__wina_edit_page__) {
                        window.__wina_edit_page__ = { body, editable: body.getAttribute('contenteditable'), designMode: document.designMode };
                    }
                    body.contentEditable = 'true';
                    document.designMode = 'on';
                    return 'Page is now editable';
                })();
                """,
            undoScript: """
                (function() {
                    const state = window.__wina_edit_page__;
                    if (!state) return 'Page editing disabled';
                    if (state.editable === null) state.body.removeAttribute('contenteditable');
                    else state.body.setAttribute('contenteditable', state.editable);
                    document.designMode = state.designMode;
                    delete window.__wina_edit_page__;
                    return 'Page editing disabled';
                })();
                """
        ),
        DebugSnippet(
            id: "show_elements",
            name: "Show Hidden",
            description: "Show all hidden elements (display:none, visibility:hidden)",
            icon: "eye",
            iconColor: .purple,
            isToggleable: true,
            category: .content,
            script: """
                (function() {
                    const id = '__wina_show_hidden_style__';
                    if (document.getElementById(id)) return;
                    const style = document.createElement('style');
                    style.id = id;
                    style.textContent = `
                        [style*="display: none"], [style*="display:none"],
                        [hidden], .hidden,
                        [style*="visibility: hidden"], [style*="visibility:hidden"] {
                            display: block !important;
                            visibility: visible !important;
                            opacity: 0.5 !important;
                            outline: 2px dashed red !important;
                        }
                    `;
                    document.head.appendChild(style);
                    return 'Hidden elements revealed';
                })();
                """,
            undoScript: """
                (function() {
                    const el = document.getElementById('__wina_show_hidden_style__');
                    if (el) el.remove();
                    return 'Hidden elements restored';
                })();
                """
        ),
        DebugSnippet(
            id: "disable_css",
            name: "Disable CSS",
            description: "Remove all stylesheets to see raw HTML structure",
            icon: "paintbrush.slash",
            iconColor: .red,
            isToggleable: true,
            category: .style,
            script: """
                (function() {
                    window.__wina_disabled_styles__ = [];
                    document.querySelectorAll('link[rel="stylesheet"], style').forEach(el => {
                        if (el.id && el.id.startsWith('__wina_')) return;
                        window.__wina_disabled_styles__.push({el, parent: el.parentNode, next: el.nextSibling});
                        el.remove();
                    });
                    return 'CSS disabled (' + window.__wina_disabled_styles__.length + ' stylesheets removed)';
                })();
                """,
            undoScript: """
                (function() {
                    if (!window.__wina_disabled_styles__) return 'No styles to restore';
                    const styles = window.__wina_disabled_styles__;
                    // Restore each saved next sibling before the stylesheet that preceded it.
                    styles.slice().reverse().forEach(({el, parent, next}) => {
                        if (!parent || !parent.isConnected) return;
                        if (next && next.parentNode === parent) {
                            parent.insertBefore(el, next);
                        } else {
                            parent.appendChild(el);
                        }
                    });
                    const fallback = document.head || document.documentElement;
                    styles.forEach(({el}) => { if (!el.isConnected) fallback.appendChild(el); });
                    const count = styles.length;
                    window.__wina_disabled_styles__ = null;
                    return 'CSS restored (' + count + ' stylesheets)';
                })();
                """
        ),
        DebugSnippet(
            id: "log_dom_stats",
            name: "DOM Stats",
            description: "Log DOM statistics (element count, depth, etc.)",
            icon: "chart.bar.doc.horizontal",
            iconColor: .cyan,
            category: .debug,
            script: """
                (function() {
                    const all = document.querySelectorAll('*');
                    const tags = {};
                    let maxDepth = 0;
                    function getDepth(el) {
                        let d = 0, node = el;
                        while (node.parentElement) { d++; node = node.parentElement; }
                        return d;
                    }
                    all.forEach(el => {
                        const tag = el.tagName.toLowerCase();
                        tags[tag] = (tags[tag] || 0) + 1;
                        maxDepth = Math.max(maxDepth, getDepth(el));
                    });
                    const sorted = Object.entries(tags).sort((a,b) => b[1] - a[1]).slice(0, 10);
                    console.group('DOM Statistics');
                    console.log('Total elements:', all.length);
                    console.log('Max depth:', maxDepth);
                    console.log('Unique tags:', Object.keys(tags).length);
                    console.table(Object.fromEntries(sorted.map(([k,v]) => [k, v])));
                    console.groupEnd();
                    return 'DOM stats logged to console';
                })();
                """
        ),
        DebugSnippet(
            id: "log_images",
            name: "Log Images",
            description: "Log all images with dimensions and sources",
            icon: "photo.on.rectangle",
            iconColor: .indigo,
            category: .debug,
            script: """
                (function() {
                    const imgs = document.querySelectorAll('img');
                    const data = Array.from(imgs).map((img, i) => ({
                        '#': i + 1,
                        'Natural': img.naturalWidth + 'x' + img.naturalHeight,
                        'Display': img.width + 'x' + img.height,
                        'Src': img.src.substring(0, 60) + (img.src.length > 60 ? '...' : ''),
                        'Alt': (img.alt || '-').substring(0, 30)
                    }));
                    console.group('Images (' + imgs.length + ')');
                    console.table(data);
                    console.groupEnd();
                    return imgs.length + ' images logged to console';
                })();
                """
        ),
        DebugSnippet(
            id: "log_links",
            name: "Log Links",
            description: "Log all links and their targets",
            icon: "link",
            iconColor: .blue,
            category: .debug,
            script: """
                (function() {
                    const links = document.querySelectorAll('a[href]');
                    const internal = [], external = [];
                    const host = location.hostname;
                    links.forEach(a => {
                        try {
                            const url = new URL(a.href);
                            const item = {text: (a.innerText || a.href).substring(0, 40), href: a.href};
                            if (url.hostname === host) internal.push(item);
                            else external.push(item);
                        } catch(e) {}
                    });
                    console.group('Links (' + links.length + ' total)');
                    console.log('Internal links:', internal.length);
                    console.table(internal.slice(0, 20));
                    console.log('External links:', external.length);
                    console.table(external.slice(0, 20));
                    console.groupEnd();
                    return links.length + ' links logged to console';
                })();
                """
        ),
        DebugSnippet(
            id: "log_event_listeners",
            name: "Event Listeners",
            description: "Log elements with event listeners (requires getEventListeners)",
            icon: "hand.tap",
            iconColor: .mint,
            category: .debug,
            script: """
                (function() {
                    // This is a simplified version - full getEventListeners is Chrome-only
                    const clickable = document.querySelectorAll('[onclick], button, a, input, [role="button"]');
                    console.group('Interactive Elements (' + clickable.length + ')');
                    clickable.forEach((el, i) => {
                        if (i < 30) {
                            console.log(i + 1, el.tagName, el.className || el.id || '(no class/id)', el);
                        }
                    });
                    if (clickable.length > 30) console.log('... and', clickable.length - 30, 'more');
                    console.groupEnd();
                    return clickable.length + ' interactive elements found';
                })();
                """
        ),
        DebugSnippet(
            id: "highlight_headings",
            name: "Highlight Headings",
            description: "Highlight all heading elements (h1-h6)",
            icon: "textformat.size",
            iconColor: .yellow,
            isToggleable: true,
            category: .layout,
            script: """
                (function() {
                    const id = '__wina_heading_style__';
                    if (document.getElementById(id)) return;
                    const style = document.createElement('style');
                    style.id = id;
                    style.textContent = `
                        h1 { outline: 3px solid #FF5733 !important; background: rgba(255,87,51,0.1) !important; }
                        h2 { outline: 3px solid #33FF57 !important; background: rgba(51,255,87,0.1) !important; }
                        h3 { outline: 3px solid #3357FF !important; background: rgba(51,87,255,0.1) !important; }
                        h4 { outline: 3px solid #FF33F5 !important; background: rgba(255,51,245,0.1) !important; }
                        h5 { outline: 3px solid #33FFF5 !important; background: rgba(51,255,245,0.1) !important; }
                        h6 { outline: 3px solid #F5FF33 !important; background: rgba(245,255,51,0.1) !important; }
                        h1::before { content: 'H1 ' !important; color: #FF5733; font-size: 10px; }
                        h2::before { content: 'H2 ' !important; color: #33FF57; font-size: 10px; }
                        h3::before { content: 'H3 ' !important; color: #3357FF; font-size: 10px; }
                        h4::before { content: 'H4 ' !important; color: #FF33F5; font-size: 10px; }
                        h5::before { content: 'H5 ' !important; color: #33FFF5; font-size: 10px; }
                        h6::before { content: 'H6 ' !important; color: #F5FF33; font-size: 10px; }
                    `;
                    document.head.appendChild(style);
                    const counts = {h1:0,h2:0,h3:0,h4:0,h5:0,h6:0};
                    'h1,h2,h3,h4,h5,h6'.split(',').forEach(t => counts[t] = document.querySelectorAll(t).length);
                    console.log('Headings:', counts);
                    return 'Headings highlighted';
                })();
                """,
            undoScript: """
                (function() {
                    const el = document.getElementById('__wina_heading_style__');
                    if (el) el.remove();
                    return 'Heading highlights removed';
                })();
                """
        )
    ]

    static let styleDependentIDs: Set<String> = ["show_elements", "highlight_headings", "border_all"]

    func execute(_ snippet: DebugSnippet, using navigator: WebViewNavigator, enabled: Bool) async throws -> String {
        guard !isExecuting else { throw SnippetExecutionError.busy }
        isExecuting = true
        defer { isExecuting = false }
        return try await apply(snippet, using: navigator, enable: enabled)
    }

    private func apply(_ snippet: DebugSnippet, using navigator: WebViewNavigator, enable: Bool) async throws -> String {
        let document = navigator.documentID
        let isActive = isActive(snippet.id)
        if snippet.isToggleable && enable == isActive { return "\(snippet.name) already \(enable ? "enabled" : "disabled")" }
        if Self.styleDependentIDs.contains(snippet.id), isActive == false, self.isActive("disable_css") {
            throw SnippetExecutionError.cssDisabled
        }

        var disabled: [String] = []
        if snippet.id == "disable_css", enable {
            for style in Self.defaultSnippets where Self.styleDependentIDs.contains(style.id) && self.isActive(style.id) {
                _ = try await apply(style, using: navigator, enable: false)
                disabled.append(style.name)
            }
        }

        guard navigator.isAttached, navigator.documentID == document, !Task.isCancelled else {
            throw SnippetExecutionError.pageChanged
        }
        let script = snippet.isToggleable && !enable ? (snippet.undoScript ?? snippet.script) : snippet.script
        let result = await navigator.evaluateJavaScript(script)
        guard navigator.documentID == document else { throw SnippetExecutionError.pageChanged }
        guard let message = result as? String else { throw SnippetExecutionError.executionFailed }
        if snippet.isToggleable, enable != self.isActive(snippet.id) {
            toggle(snippet.id)
        }
        return disabled.isEmpty ? message : "\(message) (Disabled: \(disabled.joined(separator: ", ")))"
    }

    func undoAll(using navigator: WebViewNavigator) async throws {
        guard !isExecuting else { throw SnippetExecutionError.busy }
        isExecuting = true
        defer { isExecuting = false }
        for snippet in Self.defaultSnippets where isActive(snippet.id) {
            _ = try await apply(snippet, using: navigator, enable: false)
        }
    }

    func isActive(_ snippetId: String) -> Bool {
        activeSnippets.contains(snippetId)
    }

    func toggle(_ snippetId: String) {
        if isActive(snippetId) {
            deactivate(snippetId)
        } else {
            activeSnippets.insert(snippetId)
        }
    }

    func deactivate(_ snippetId: String) {
        activeSnippets.remove(snippetId)
    }

    func resetActiveSnippets() {
        activeSnippets.removeAll()
    }
}

private enum SnippetExecutionError: LocalizedError {
    case cssDisabled, pageChanged, executionFailed, busy

    var errorDescription: String? {
        switch self {
        case .cssDisabled: "This snippet is unavailable while Disable CSS is active."
        case .pageChanged: "The page changed during snippet execution."
        case .executionFailed: "Could not run this snippet on the page."
        case .busy: "Another snippet is running."
        }
    }
}

// MARK: - Snippets View (DevTools Sheet)

struct SnippetsView: View {
    @Bindable var navigator: WebViewNavigator
    @Environment(\.closeDevTools) private var closeDevTools
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: SnippetCategory = .all
    @State private var searchText: String = ""
    @State private var executionResult: String?
    @State private var showResult: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollViewHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy?

    private var snippetsManager: SnippetsManager {
        navigator.snippetsManager
    }

    private var filteredSnippets: [DebugSnippet] {
        var result = SnippetsManager.defaultSnippets

        // Filter by category
        if selectedCategory != .all {
            result = result.filter { $0.category == selectedCategory }
        }

        // Filter by search
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    private var activeCount: Int {
        snippetsManager.activeSnippets.count
    }

    private func count(for category: SnippetCategory) -> Int {
        if category == .all {
            return SnippetsManager.defaultSnippets.count
        }
        return SnippetsManager.defaultSnippets.filter { $0.category == category }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            snippetsHeader
            searchBar
            filterTabs

            Divider()

            if filteredSnippets.isEmpty {
                emptyState
            } else {
                snippetsList
            }
        }
        .overlay(alignment: .bottom) {
            resultToast
        }
        .animation(.easeInOut(duration: 0.2), value: showResult)
        .dismissKeyboardOnTap()
        .task {
            await AdManager.shared.showInterstitialAd(
                options: AdOptions(id: "snippets_devtools"),
                adUnitId: AdManager.interstitialAdUnitId
            )
        }
    }

    // MARK: - Header

    private var snippetsHeader: some View {
        DevToolsHeader(
            title: "Snippets",
            leftButtons: [
                .init(icon: "xmark.circle.fill", color: .secondary) {
                    (closeDevTools ?? { dismiss() })()
                },
                .init(
                    icon: "arrow.counterclockwise",
                    isDisabled: activeCount == 0
                ) {
                    resetAllSnippets()
                }
            ],
            rightButtons: []
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search snippets", text: $searchText)
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
                ForEach(SnippetCategory.allCases) { category in
                    SnippetFilterTab(
                        label: category.rawValue,
                        count: count(for: category),
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
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
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text(searchText.isEmpty ? "No snippets" : "No matches")
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

    // MARK: - Snippets List

    private var snippetsList: some View {
        GeometryReader { outerGeo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSnippets) { snippet in
                            SnippetRow(
                                snippet: snippet,
                                isActive: snippetsManager.isActive(snippet.id),
                                isDisabled: snippetsManager.isActive("disable_css")
                                    && SnippetsManager.styleDependentIDs.contains(snippet.id)
                            ) {
                                executeSnippet(snippet)
                            }
                            .id(snippet.id)
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
                    scrollProxy = proxy
                }
                .scrollNavigationOverlay(
                    scrollOffset: scrollOffset,
                    contentHeight: contentHeight,
                    viewportHeight: scrollViewHeight,
                    onScrollUp: { scrollUp(proxy: scrollProxy) },
                    onScrollDown: { scrollDown(proxy: scrollProxy) }
                )
            }
        }
    }

    // MARK: - Result Toast

    @ViewBuilder
    private var resultToast: some View {
        if showResult, let result = executionResult {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(result)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(2)
                Spacer()
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Scroll Navigation

    private func scrollUp(proxy: ScrollViewProxy?) {
        guard let proxy, let firstSnippet = filteredSnippets.first else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(firstSnippet.id, anchor: .top)
        }
    }

    private func scrollDown(proxy: ScrollViewProxy?) {
        guard let proxy, let lastSnippet = filteredSnippets.last else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(lastSnippet.id, anchor: .bottom)
        }
    }

    // MARK: - Actions

    private func executeSnippet(_ snippet: DebugSnippet) {
        Task {
            do {
                let enable = !snippetsManager.isActive(snippet.id)
                showSnippetResult(try await snippetsManager.execute(snippet, using: navigator, enabled: enable))
            } catch {
                showSnippetResult(error.localizedDescription)
            }
        }
    }

    private func resetAllSnippets() {
        Task {
            do {
                try await snippetsManager.undoAll(using: navigator)
                showSnippetResult("All snippets reset")
            } catch {
                showSnippetResult(error.localizedDescription)
            }
        }
    }

    private func showSnippetResult(_ result: String) {
        executionResult = result
        showResult = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showResult = false
        }
    }
}

// MARK: - Snippet Filter Tab

private struct SnippetFilterTab: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    // swiftlint:disable:next empty_count
    private var showBadge: Bool { count > 0 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                if showBadge {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                            in: Capsule()
                        )
                        .foregroundStyle(isSelected ? .white : .secondary)
                }
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Snippet Row

private struct SnippetRow: View {
    let snippet: DebugSnippet
    let isActive: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon - 항상 동일한 스타일 유지
                Image(systemName: snippet.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(snippet.iconColor.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(
                        snippet.iconColor.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8)
                    )

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(snippet.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(snippet.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                    if isDisabled {
                        Text("Disable CSS is active")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Spacer()

                // Action indicator - 활성화 상태에 따라 색상 변경
                if snippet.isToggleable {
                    Image(systemName: isActive ? "stop.circle.fill" : "play.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isActive ? Color.green : Color.gray)
                } else {
                    Image(systemName: "bolt.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.gray)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)

        Divider()
            .padding(.leading, 64)
    }
}

// MARK: - Legacy Navigation View (Settings)

struct SnippetsSettingsView: View {
    let navigator: WebViewNavigator

    var body: some View {
        SnippetsView(navigator: navigator)
            .navigationBarHidden(true)
    }
}

#Preview {
    SnippetsView(navigator: WebViewNavigator())
}
