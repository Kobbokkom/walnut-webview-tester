//
//  ScriptDetailView.swift
//  wina
//
//  Script detail view for JavaScript inspection.
//

import SwiftUI
import WebKit

// MARK: - Script Detail View

struct ScriptDetailView: View {
    let script: ScriptInfo
    let index: Int
    let navigator: WebViewNavigator?

    @Environment(\.dismiss) private var dismiss
    @State private var scriptContent: String = ""
    @State private var isTruncated: Bool = false
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var feedbackState = CopiedFeedbackState()

    var body: some View {
        VStack(spacing: 0) {
            header

            metadataBadges
            if let url = script.src {
                ExpandableURLView(url: url) { feedbackState.showCopied("URL") }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider()

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
                        .padding(.top, 8)
                }
                ScrollView(.vertical) {
                    ScrollView(.horizontal, showsIndicators: true) {
                        CodeBlock(code: scriptContent, language: .javascript)
                            .padding()
                    }
                }
                .background(Color(uiColor: .systemBackground))
            }
        }
        .copiedFeedbackOverlay($feedbackState.message)
        .task {
            await fetchDetails()
        }
    }

    private var header: some View {
        DevToolsHeader(
            title: script.src.flatMap { URL(string: $0)?.lastPathComponent } ?? "<script>",
            leftButtons: [
                .init(icon: "xmark.circle.fill", color: .secondary) {
                    dismiss()
                }
            ],
            rightButtons: [
                .init(icon: "doc.on.doc") {
                    UIPasteboard.general.string = scriptContent
                    feedbackState.showCopied("Script")
                }
            ]
        )
    }

    private var metadataBadges: some View {
        HStack(spacing: 8) {
            if script.isModule {
                badge("module")
            }
            if script.isAsync {
                badge("async")
            }
            if script.isDefer {
                badge("defer")
            }
            if script.isExternal {
                badge("external")
            } else {
                badge("inline")
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.secondary.opacity(0.1), in: Capsule())
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color(uiColor: .systemBackground))
    }

    static func contentScript(
        index: Int,
        expected: String,
        result: String = "JSON.stringify({content: content.slice(0, 50000).toWellFormed(), truncated: content.length > 50000})"
    ) -> String {
        SourceResourceScript.read(.script, index: index, expected: expected, body: """
        const retrieval = approved.url ? 'requested-resource' : 'inline';
        const content = approved.url
            ? await fetchSource(approved.url, approved.credentials, approved.referrerPolicy)
            : source.textContent;
        return \(result);
        """)
    }

    private func fetchDetails() async {
        guard let navigator else {
            errorMessage = "Navigator not available"
            isLoading = false
            return
        }

        let document = navigator.documentID
        do {
            guard let expected = script.selection else { throw AgentError("Refresh Sources and select the script again.") }
            let source = Self.contentScript(index: index, expected: expected)
            let result = try await navigator.callAsyncJavaScriptReportingErrors("return \(source)", contentWorld: .defaultClient)
            guard navigator.documentID == document else {
                throw AgentError("The active WKWebView document changed. Try again.")
            }
            if let result = result as? String,
               let data = result.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                errorMessage = json["error"] as? String
                scriptContent = json["content"] as? String ?? ""
                isTruncated = json["truncated"] as? Bool ?? false
            } else {
                errorMessage = "Failed to fetch script"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview("Script Detail") {
    ScriptDetailView(
        script: ScriptInfo(
            index: 0,
            src: "app.js",
            isExternal: true,
            isModule: true,
            isAsync: false,
            isDefer: true,
            content: nil
        ),
        index: 0,
        navigator: nil
    )
}
