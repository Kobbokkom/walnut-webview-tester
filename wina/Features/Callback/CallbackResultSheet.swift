//
//  CallbackResultSheet.swift
//  wina
//
//  Created by Claude on 1/15/26.
//

import SwiftUI

// MARK: - Callback Result Sheet

struct CallbackResultSheet: View {
    @State private var manager = CallbackTestManager.shared
    @State private var shareItem: ShareItem?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DevToolsHeader(
                title: "Callback",
                leftButtons: [
                    .init(icon: "xmark.circle.fill", color: .secondary, action: onClose),
                    .init(
                        icon: "trash",
                        isDisabled: manager.lastCallbackURL == nil
                    ) { manager.clearHistory() },
                    .init(
                        icon: "square.and.arrow.up",
                        isDisabled: manager.lastCallbackURL == nil
                    ) {
                        if manager.lastCallbackURL != nil {
                            shareItem = ShareItem(items: [manager.formattedResult])
                        }
                    }
                ],
                rightButtons: []
            )

            if let url = manager.lastCallbackURL {
                resultContent(url: url)
            } else {
                emptyContent
            }
        }
        .devToolsSheet()
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: item.items)
        }
    }

    // MARK: - Result Content

    @ViewBuilder
    private func resultContent(url: URL) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // URL Components
                urlComponentsSection(url: url)

                // Parameters
                if !manager.callbackParameters.isEmpty {
                    parametersSection
                }

                // Raw URL
                rawURLSection(url: url)

                // Timestamp
                if let time = manager.lastCallbackTime {
                    timestampSection(time: time)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - URL Components Section

    @ViewBuilder
    private func urlComponentsSection(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("URL Components")

            VStack(spacing: 6) {
                componentRow(label: "Scheme", value: url.scheme ?? "—", color: .blue)
                componentRow(label: "Host", value: url.host ?? "—", color: .purple)
                if !url.path.isEmpty && url.path != "/" {
                    componentRow(label: "Path", value: url.path, color: .orange)
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Parameters Section

    @ViewBuilder
    private var parametersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Parameters (\(manager.callbackParameters.count))")

            VStack(spacing: 8) {
                ForEach(
                    Array(manager.callbackParameters.enumerated()),
                    id: \.offset
                ) { _, item in
                    parameterRow(key: item.name, value: item.value ?? "—")
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Raw URL Section

    @ViewBuilder
    private func rawURLSection(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Raw URL")

            Text(url.absoluteString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Timestamp Section

    @ViewBuilder
    private func timestampSection(time: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Received")

            Text(formatTimestamp(time))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    // MARK: - Component Row

    @ViewBuilder
    private func componentRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(.subheadline))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
        }
    }

    // MARK: - Parameter Row

    @ViewBuilder
    private func parameterRow(key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.blue)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty Content

    @ViewBuilder
    private var emptyContent: some View {
        ContentUnavailableView(
            "No Callback",
            systemImage: "arrow.down.circle.dotted",
            description: Text("Tap a callback button on the test page")
        )
        .frame(maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

// MARK: - Share Item

private struct ShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

#Preview {
    CallbackResultSheet(onClose: {})
}
