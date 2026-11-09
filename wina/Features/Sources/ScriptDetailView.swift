//
//  ScriptDetailView.swift
//  wina
//
//  Script detail view for JavaScript inspection.
//

import SwiftUI

// MARK: - Script Detail View

struct ScriptDetailView: View {
    let script: ScriptInfo
    let index: Int
    let navigator: WebViewNavigator?

    @Environment(\.dismiss) private var dismiss
    @State private var scriptContent: String = ""
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var feedbackState = CopiedFeedbackState()

    var body: some View {
        VStack(spacing: 0) {
            header

            metadataBadges

            Divider()

            if let error = errorMessage {
                errorView(error)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if script.isExternal {
                corsLimitationView
            } else {
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

    /// View explaining CORS limitation for external scripts
    private var corsLimitationView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)

                Text("External Script")
                    .font(.headline)

                Text("Content unavailable due to CORS policy.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let src = script.src {
                    ExpandableURLView(url: src) {
                        feedbackState.showCopied("URL")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(Color(uiColor: .systemBackground))
    }

    static func inlineContentScript(index: Int, maxLength: Int? = 50_000) -> String {
        let truncation = maxLength.map { ".substring(0, \($0))" } ?? ""
        return """
        (function() {
            const scripts = document.scripts;
            const script = scripts[\(index)];
            if (!script) return JSON.stringify({error: 'Script not found'});
            if (script.src) return JSON.stringify({error: 'External script source is unavailable'});
            return JSON.stringify({content: script.textContent\(truncation)});
        })();
        """
    }

    private func fetchDetails() async {
        guard let navigator else {
            errorMessage = "Navigator not available"
            isLoading = false
            return
        }

        if script.isExternal {
            // External scripts cannot be fetched due to CORS
            // Show limitation view instead of trying to fetch
            isLoading = false
            return
        } else {
            // Get inline script content
            let script = Self.inlineContentScript(index: index)

            if let result = await navigator.evaluateJavaScript(script) as? String,
               let data = result.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                if let error = json["error"] {
                    errorMessage = error
                } else {
                    scriptContent = json["content"] ?? ""
                }
            } else {
                errorMessage = "Failed to fetch script"
            }
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
