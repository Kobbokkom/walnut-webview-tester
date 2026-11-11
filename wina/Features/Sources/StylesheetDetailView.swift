//
//  StylesheetDetailView.swift
//  wina
//
//  Stylesheet detail view for CSS rules inspection.
//

import SwiftUI
import WebKit

// MARK: - CSS Rule Info

struct CSSRuleInfo: Identifiable {
    let id: Int
    let selector: String
    let cssText: String
}

/// Represents parsed CSS content - either flat properties or nested blocks
enum ParsedCSSContent {
    case properties([(property: String, value: String)])
    case keyframes([(selector: String, properties: [(property: String, value: String)])])
}

// MARK: - Stylesheet Detail View

struct StylesheetDetailView: View {
    let sheet: StylesheetInfo
    let index: Int
    let navigator: WebViewNavigator?

    @Environment(\.dismiss) private var dismiss
    @State private var cssRules: [CSSRuleInfo] = []
    @State private var rawCSS: String = ""
    @State private var isTruncated: Bool = false
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var showRaw: Bool = false
    @State private var feedbackState = CopiedFeedbackState()

    var body: some View {
        VStack(spacing: 0) {
            header

            if let error = errorMessage {
                errorView(error)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if isTruncated {
                    Text("Showing the first 50,000 characters.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
                content
            }
        }
        .copiedFeedbackOverlay($feedbackState.message)
        .task {
            await fetchDetails()
        }
    }

    private var header: some View {
        DevToolsHeader(
            title: sheet.href.flatMap { URL(string: $0)?.lastPathComponent } ?? "<style>",
            leftButtons: [
                .init(icon: "xmark.circle.fill", color: .secondary) {
                    dismiss()
                }
            ],
            rightButtons: [
                .init(icon: showRaw ? "list.bullet" : "doc.plaintext") {
                    showRaw.toggle()
                },
                .init(icon: "doc.on.doc") {
                    UIPasteboard.general.string = rawCSS
                    feedbackState.showCopied("CSS")
                }
            ]
        )
    }

    @ViewBuilder
    private var content: some View {
        if showRaw {
            ScrollView {
                CodeBlock(code: rawCSS, language: .css)
                    .padding()
            }
            .background(Color(uiColor: .systemBackground))
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(cssRules) { rule in
                        CSSRuleRow(rule: rule)
                        Divider()
                    }
                }
                .padding(.horizontal, 16)
            }
            .background(Color(uiColor: .systemBackground))
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    static func contentScript(index: Int, expected: String, result: String? = nil) -> String {
        let output = result.map { "return \($0);" } ?? nativePreview
        return SourceResourceScript.read(.stylesheet, index: index, expected: expected, body: """
        function ruleRows(sheet) {
            return Array.from(sheet.cssRules, rule => ({
                selector: rule.selectorText || rule.cssText.substring(0, 50), text: rule.cssText
            }));
        }
        let rules, rawCSS, retrieval = 'loaded-cssom';
        try {
            rules = ruleRows(source);
            rawCSS = rules.map(rule => rule.text).join('\\n\\n');
        } catch (_) {
            if (!approved.url) throw new Error('Stylesheet source is unavailable.');
            rawCSS = await fetchSource(approved.url, approved.credentials, approved.referrerPolicy);
            retrieval = 'requested-resource';
            // A detached parser keeps fetched CSS from changing the inspected page.
            const parsed = new CSSStyleSheet();
            parsed.replaceSync(rawCSS);
            rules = ruleRows(parsed);
        }
        \(output)
        """)
    }

    private static let nativePreview = """
    const previewRules = [];
    let remaining = 50000;
    for (const rule of rules) {
        if (remaining <= 0) break;
        previewRules.push({selector: rule.selector.slice(0, remaining).toWellFormed(), text: rule.text.slice(0, remaining).toWellFormed()});
        remaining -= rule.text.length + 2;
    }
    return JSON.stringify({rules: previewRules, raw: rawCSS.slice(0, 50000).toWellFormed(), truncated: rawCSS.length > 50000 || previewRules.length < rules.length});
    """

    private func fetchDetails() async {
        guard let navigator else {
            errorMessage = "Navigator not available"
            isLoading = false
            return
        }

        guard let expected = sheet.selection else {
            errorMessage = "Refresh Sources and select the stylesheet again."
            isLoading = false
            return
        }
        let script = Self.contentScript(index: index, expected: expected)
        let document = navigator.documentID
        let result = try? await navigator.callAsyncJavaScriptReportingErrors("return \(script)", contentWorld: .defaultClient)
        guard navigator.documentID == document else {
            errorMessage = "The active WKWebView document changed. Try again."
            isLoading = false
            return
        }
        if let result = result as? String,
           let data = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? String {
                errorMessage = error
            } else if let rulesArray = json["rules"] as? [[String: String]] {
                cssRules = rulesArray.enumerated().map { idx, item in
                    CSSRuleInfo(
                        id: idx,
                        selector: item["selector"] ?? "",
                        cssText: item["text"] ?? ""
                    )
                }
                rawCSS = json["raw"] as? String ?? ""
                isTruncated = json["truncated"] as? Bool ?? false
            }
        } else {
            errorMessage = "Failed to fetch stylesheet"
        }

        isLoading = false
    }
}

// MARK: - CSS Rule Row

struct CSSRuleRow: View {
    let rule: CSSRuleInfo
    @State private var isExpanded: Bool = false

    /// Parsed CSS content from cssText
    private var parsedContent: ParsedCSSContent {
        CSSFormatter.parseRule(from: rule.cssText)
    }

    /// Count for badge display
    private var itemCount: Int {
        switch parsedContent {
        case .properties(let props):
            return props.count
        case .keyframes(let frames):
            return frames.count
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text(rule.selector)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(itemCount)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedContent
                    .padding(.leading, 20)
                    .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        switch parsedContent {
        case .properties(let props):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(props.enumerated()), id: \.offset) { _, prop in
                    FormattedCSSPropertyRow(property: prop.property, value: prop.value)
                }
            }
        case .keyframes(let frames):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                    KeyframeBlockView(selector: frame.selector, properties: frame.properties)
                }
            }
        }
    }
}

#Preview("Stylesheet Detail") {
    StylesheetDetailView(
        sheet: StylesheetInfo(
            index: 0,
            href: "styles.css",
            rulesCount: 42,
            isExternal: true,
            mediaText: nil,
            cssContent: nil
        ),
        index: 0,
        navigator: nil
    )
}
