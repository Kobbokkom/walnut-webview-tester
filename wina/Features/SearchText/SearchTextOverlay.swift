//
//  SearchTextOverlay.swift
//  wina
//
//  Search and highlight text on the current page.
//  Based on Eruda's Search Text snippet.
//

import SwiftUI
import SwiftUIBackports
import WebKit

// MARK: - Search Text Overlay

struct SearchTextOverlay: View {
    static let searchWorld = WKContentWorld.world(name: "WalnutPageSearch")

    let navigator: WebViewNavigator
    @Binding var isPresented: Bool
    let bottomPaddingCalculator: (CGFloat) -> CGFloat

    @State private var searchText: String = ""
    @State private var matchCount: Int = 0
    @State private var currentIndex: Int = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var hasCompletedSearch: Bool = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let bottomPadding = bottomPaddingCalculator(proxy.safeAreaInsets.bottom)

            VStack {
                Spacer()

                // Search bar at bottom (Liquid Glass UI)
                HStack(spacing: 12) {
                    // Close 버튼
                    GlassIconButton(
                        icon: "xmark",
                        size: .small,
                        color: .secondary
                    ) {
                        isPresented = false
                    }

                    // Search field
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)

                        TextField("Search in page", text: $searchText)
                            .font(.system(size: 15))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isTextFieldFocused)
                            .submitLabel(.search)
                            .onSubmit {
                                scheduleSearch()
                            }

                        // Clear 버튼
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

                    // Match count & navigation
                    if matchCount > 0 {
                        HStack(spacing: 4) {
                            Text("\(currentIndex + 1)/\(matchCount)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 40)

                            // 이전 매치로 이동
                            GlassIconButton(
                                icon: "chevron.up",
                                size: .small,
                                isDisabled: matchCount <= 1
                            ) {
                                navigate(using: Self.previousScript)
                            }

                            // 다음 매치로 이동
                            GlassIconButton(
                                icon: "chevron.down",
                                size: .small,
                                isDisabled: matchCount <= 1
                            ) {
                                navigate(using: Self.nextScript)
                            }
                        }
                    } else if !searchText.isEmpty && hasCompletedSearch {
                        Text("No matches")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .backport.glassEffect(in: .rect(cornerRadius: 20))
                .padding(.horizontal, 12)
                .padding(.bottom, bottomPadding)
            }
        }
        .onAppear {
            isTextFieldFocused = true
        }
        // 외부에서 닫힐 때 하이라이트 제거
        .onDisappear {
            clearHighlights()
        }
        .onChange(of: searchText) { _, _ in
            scheduleSearch(debounce: true)
        }
        .onChange(of: navigator.documentID) { _, _ in
            scheduleSearch(waitForDocument: true)
        }
    }

    // MARK: - Search Actions

    private func scheduleSearch(debounce: Bool = false, waitForDocument: Bool = false) {
        searchTask?.cancel()
        matchCount = 0
        currentIndex = 0
        hasCompletedSearch = false
        guard !searchText.isEmpty, let script = Self.searchScript(for: searchText) else {
            clearHighlights()
            return
        }

        let document = navigator.documentID
        let query = searchText
        let readyScript = Self.readySearchScript(script, waitForDocument: waitForDocument)
        searchTask = Task {
            if debounce { try? await Task.sleep(for: .milliseconds(300)) }
            // The new document may not have a body yet when WebKit commits it.
            while navigator.isAttached {
                guard !Task.isCancelled, navigator.documentID == document, searchText == query else { return }
                let result = try? await navigator.evaluateJavaScriptReportingErrors(readyScript, contentWorld: Self.searchWorld)
                guard !Task.isCancelled, navigator.documentID == document, searchText == query,
                      let jsonString = result as? String else { return }
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    matchCount = json["count"] as? Int ?? 0
                    currentIndex = json["index"] as? Int ?? 0
                    hasCompletedSearch = true
                    return
                }
                guard jsonString == "wait" else { return }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    static func readySearchScript(_ script: String, waitForDocument: Bool) -> String {
        """
        if (document.readyState === 'loading' && (\(waitForDocument) || !document.body)) { 'wait'; }
        else if (document.body) { \(script) }
        else { JSON.stringify({count: 0, index: 0}); }
        """
    }

    static func searchScript(for keyword: String, sharingWith scope: UUID? = nil) -> String? {
        guard let keywordData = try? JSONSerialization.data(
            withJSONObject: keyword,
            options: .fragmentsAllowed
        ),
        let jsonKeyword = String(data: keywordData, encoding: .utf8) else {
            return nil
        }

        let sharedScope = scope.map { "'\($0.uuidString)'" } ?? "null"
        return """
        (function() {
            window.__wina_search_scope__ = null;
            // Remove previous highlights
            document.querySelectorAll('.__wina_search_highlight__').forEach(el => {
                const parent = el.parentNode;
                parent.replaceChild(document.createTextNode(el.textContent), el);
                parent.normalize();
            });

            const keyword = \(jsonKeyword);
            if (!keyword) return JSON.stringify({count: 0, index: 0});

            const escapedKeyword = keyword.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
            const regex = new RegExp(escapedKeyword, 'gi');
            let matchCount = 0;
            const elements = [];

            function traverse(node) {
                if (node.nodeType === 3) { // Text node
                    const text = node.nodeValue;
                    regex.lastIndex = 0;
                    const matches = Array.from(text.matchAll(regex));
                    if (matches.length > 0) {
                        const frag = document.createDocumentFragment();
                        let offset = 0;
                        for (const match of matches) {
                            frag.appendChild(document.createTextNode(text.slice(offset, match.index)));
                            const highlight = document.createElement('span');
                            highlight.className = '__wina_search_highlight__';
                            highlight.style.cssText = 'background-color: #FFEB3B; color: #000; padding: 1px 2px; border-radius: 2px;';
                            highlight.textContent = match[0];
                            frag.appendChild(highlight);
                            elements.push(highlight);
                            offset = match.index + match[0].length;
                        }
                        frag.appendChild(document.createTextNode(text.slice(offset)));
                        matchCount += matches.length;
                        node.parentNode.replaceChild(frag, node);
                    }
                } else if (node.nodeType === 1 && !['SCRIPT', 'STYLE', 'NOSCRIPT'].includes(node.tagName)) {
                    Array.from(node.childNodes).forEach(traverse);
                }
            }

            traverse(document.body);

            // Scroll to first match
            if (elements.length > 0) {
                elements[0].scrollIntoView({behavior: 'smooth', block: 'center'});
                elements[0].style.backgroundColor = '#FF9800';
            }

            window.__wina_search_elements__ = elements;
            window.__wina_search_index__ = 0;
            window.__wina_search_scope__ = \(sharedScope);

            return JSON.stringify({count: matchCount, index: 0});
        })();
        """
    }

    static let nextScript = navigationScript(step: 1)
    static let previousScript = navigationScript(step: -1)

    static func navigationScript(step: Int, sharingWith scope: UUID? = nil) -> String {
        let requireSharedSearch = scope.map { scope in
            """
            if (window.__wina_search_scope__ !== '\(scope.uuidString)') {
                return JSON.stringify({index: 0, requiresFind: true});
            }
            """
        } ?? ""
        return """
        (function() {
            \(requireSharedSearch)
            const previousElements = window.__wina_search_elements__ || [];
            const previousIndex = window.__wina_search_index__ || 0;
            const previous = previousElements[previousIndex];
            const inDocument = element => element.isConnected && element.ownerDocument === document;
            const elements = previousElements.filter(inDocument);
            const count = elements.length;
            window.__wina_search_elements__ = elements;
            if (!count) {
                window.__wina_search_index__ = 0;
                return JSON.stringify({count: 0, index: 0, moved: false});
            }

            const current = elements.indexOf(previous);
            let offset = current + \(step);
            if (current < 0) {
                const precedingCount = previousElements.slice(0, previousIndex).filter(inDocument).length;
                offset = precedingCount + Math.min(\(step), 0);
            }
            const index = (offset + count) % count;
            window.__wina_search_index__ = index;
            if (current >= 0) previous.style.backgroundColor = '#FFEB3B';
            elements[index].style.backgroundColor = '#FF9800';
            elements[index].scrollIntoView({behavior: 'smooth', block: 'center'});
            return JSON.stringify({count, index, moved: current !== index});
        })();
        """
    }

    private func navigate(using script: String) {
        let document = navigator.documentID
        let query = searchText
        Task {
            let result = try? await navigator.evaluateJavaScriptReportingErrors(script, contentWorld: Self.searchWorld)
            await MainActor.run {
                guard navigator.documentID == document, searchText == query else { return }
                if let jsonString = result as? String,
                   let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    currentIndex = json["index"] as? Int ?? 0
                    matchCount = json["count"] as? Int ?? 0
                }
            }
        }
    }

    static let clearScript = """
        (function() {
            window.__wina_search_scope__ = null;
            document.querySelectorAll('.__wina_search_highlight__').forEach(el => {
                const parent = el.parentNode;
                parent.replaceChild(document.createTextNode(el.textContent), el);
                parent.normalize();
            });
            window.__wina_search_elements__ = [];
            window.__wina_search_index__ = 0;
        })();
        """

    private func clearHighlights() {
        searchTask?.cancel()
        matchCount = 0
        currentIndex = 0
        hasCompletedSearch = false

        let script = Self.clearScript
        let document = navigator.documentID

        Task {
            guard navigator.documentID == document else { return }
            _ = try? await navigator.evaluateJavaScriptReportingErrors(script, contentWorld: Self.searchWorld)
        }
    }
}

#Preview {
    ZStack {
        Color.blue.opacity(0.3)
            .ignoresSafeArea()

        SearchTextOverlay(
            navigator: WebViewNavigator(),
            isPresented: .constant(true),
            bottomPaddingCalculator: { _ in 12 }
        )
    }
}
