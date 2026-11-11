//
//  CallbackTestView.swift
//  wina
//
//  Created by Claude on 1/15/26.
//

import SwiftUI

// MARK: - Callback Test Settings View

struct CallbackTestSettingsView: View {
    private let manager = CallbackTestManager.shared

    @State private var showingSafariVC = false

    var body: some View {
        List {
            urlSchemeSection
            resultsSection
        }
        .navigationTitle(Text(verbatim: "Callback Test"))
        .navigationBarTitleDisplayMode(.inline)
        .background {
            SafariModalPresenter(
                url: showingSafariVC ? CallbackTestManager.testPageURL : nil,
                usesBrowserSettings: false,
                onDismiss: { _ in showingSafariVC = false }
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
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

// MARK: - Preview

#Preview("Callback Test Settings") {
    NavigationStack {
        CallbackTestSettingsView()
    }
}
