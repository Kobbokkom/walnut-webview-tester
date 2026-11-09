//
//  SearchTextOverlay.swift
//  wina
//
//  Search and highlight text on the current page.
//  Based on Eruda's Search Text snippet.
//

import SwiftUI
import SwiftUIBackports

// MARK: - Search Text Overlay

struct SearchTextOverlay: View {
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
                                navigateToPrevious()
                            }

                            // 다음 매치로 이동
                            GlassIconButton(
                                icon: "chevron.down",
                                size: .small,
                                isDisabled: matchCount <= 1
                            ) {
                                navigateToNext()
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
        searchTask = Task {
            if debounce { try? await Task.sleep(for: .milliseconds(300)) }
            // The new document may not have a body yet when WebKit commits it.
            while navigator.isAttached {
                guard !Task.isCancelled, navigator.documentID == document, searchText == query else { return }
                let result = await navigator.evaluateJavaScript("""
                if (document.readyState === 'loading' && (\(waitForDocument) || !document.body)) { 'wait'; }
                else if (document.body) { \(script) }
                else { JSON.stringify({count: 0, index: 0}); }
                """)
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

    static func searchScript(for keyword: String) -> String? {
        guard let keywordData = try? JSONSerialization.data(
            withJSONObject: keyword,
            options: .fragmentsAllowed
        ),
        let jsonKeyword = String(data: keywordData, encoding: .utf8) else {
            return nil
        }

        return """
        (function() {
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

            return JSON.stringify({count: matchCount, index: 0});
        })();
        """
    }

    static let nextScript = """
        (function() {
            const elements = window.__wina_search_elements__ || [];
            if (elements.length === 0) return JSON.stringify({index: 0});

            let index = window.__wina_search_index__ || 0;

            // Reset previous highlight
            if (elements[index]) {
                elements[index].style.backgroundColor = '#FFEB3B';
            }

            // Move to next
            index = (index + 1) % elements.length;
            window.__wina_search_index__ = index;

            // Highlight current
            if (elements[index]) {
                elements[index].style.backgroundColor = '#FF9800';
                elements[index].scrollIntoView({behavior: 'smooth', block: 'center'});
            }

            return JSON.stringify({index: index});
        })();
        """

    private func navigateToNext() {
        let script = Self.nextScript

        let document = navigator.documentID
        let query = searchText
        Task {
            let result = await navigator.evaluateJavaScript(script)
            await MainActor.run {
                guard navigator.documentID == document, searchText == query else { return }
                if let jsonString = result as? String,
                   let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    currentIndex = json["index"] as? Int ?? 0
                }
            }
        }
    }

    static let previousScript = """
        (function() {
            const elements = window.__wina_search_elements__ || [];
            if (elements.length === 0) return JSON.stringify({index: 0});

            let index = window.__wina_search_index__ || 0;

            // Reset previous highlight
            if (elements[index]) {
                elements[index].style.backgroundColor = '#FFEB3B';
            }

            // Move to previous
            index = (index - 1 + elements.length) % elements.length;
            window.__wina_search_index__ = index;

            // Highlight current
            if (elements[index]) {
                elements[index].style.backgroundColor = '#FF9800';
                elements[index].scrollIntoView({behavior: 'smooth', block: 'center'});
            }

            return JSON.stringify({index: index});
        })();
        """

    private func navigateToPrevious() {
        let script = Self.previousScript

        let document = navigator.documentID
        let query = searchText
        Task {
            let result = await navigator.evaluateJavaScript(script)
            await MainActor.run {
                guard navigator.documentID == document, searchText == query else { return }
                if let jsonString = result as? String,
                   let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    currentIndex = json["index"] as? Int ?? 0
                }
            }
        }
    }

    static let clearScript = """
        (function() {
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

        Task {
            await navigator.evaluateJavaScript(script)
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
