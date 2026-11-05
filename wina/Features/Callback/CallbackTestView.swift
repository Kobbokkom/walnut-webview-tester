//
//  CallbackTestView.swift
//  wina
//
//  Created by Claude on 1/15/26.
//

import SafariServices
import SwiftUI

// MARK: - Callback Test Settings View

struct CallbackTestSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private let manager = CallbackTestManager.shared

    @State private var showingSafariVC = false

    var body: some View {
        List {
            urlSchemeSection
            resultsSection
        }
        .navigationTitle(Text(verbatim: "Callback Test"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSafariVC) {
            CallbackTestSafariView()
        }
    }

    // MARK: - URL Scheme Test Section

    @ViewBuilder
    private var urlSchemeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Test URL scheme callbacks from Safari")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    showingSafariVC = true
                } label: {
                    Label("Open Test Page in Safari", systemImage: "safari")
                }

                Text("The test page provides buttons to send callbacks to this app with sample data.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("URL Scheme Callback")
        } footer: {
            Text("Scheme: wina://callback?key=value")
        }
    }

    // MARK: - Results Section

    @ViewBuilder
    private var resultsSection: some View {
        Section {
            if manager.lastCallbackURL != nil {
                // Last callback info
                if let url = manager.lastCallbackURL {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "link")
                                .foregroundStyle(.blue)
                            Text("Last Callback URL")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if let time = manager.lastCallbackTime {
                                Text(time, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(url.absoluteString)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }

                // Parameters
                if !manager.callbackParameters.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                                .foregroundStyle(.purple)
                            Text("Parameters")
                                .font(.subheadline.weight(.medium))
                        }

                        ForEach(
                            Array(manager.callbackParameters.enumerated()),
                            id: \.offset
                        ) { _, item in
                            HStack {
                                Text(item.name)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(item.value ?? "—")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Clear button
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        withAnimation {
                            manager.clearHistory()
                        }
                    } label: {
                        Label("Clear Results", systemImage: "trash")
                            .font(.subheadline)
                    }
                    Spacer()
                }
                .padding(.top, 8)
            } else {
                ContentUnavailableView(
                    "No Callbacks Yet",
                    systemImage: "arrow.down.circle.dotted",
                    description: Text("Test callbacks using the options above")
                )
            }
        } header: {
            Text("Results")
        }
    }
}

// MARK: - Safari View for Test Page

struct CallbackTestSafariView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SafariViewRepresentable(url: CallbackTestManager.testPageURL)
                .ignoresSafeArea()
                .navigationTitle(Text(verbatim: "Callback Test Page"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - Safari View Representable

private struct SafariViewRepresentable: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context _: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true

        let safari = SFSafariViewController(url: url, configuration: config)
        if #unavailable(iOS 26.0) {
            safari.preferredControlTintColor = .systemBlue
        }
        return safari
    }

    func updateUIViewController(_: SFSafariViewController, context _: Context) {}
}

// MARK: - Preview

#Preview("Callback Test Settings") {
    NavigationStack {
        CallbackTestSettingsView()
    }
}
