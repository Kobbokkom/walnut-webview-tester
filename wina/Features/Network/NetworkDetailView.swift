//
//  NetworkDetailView.swift
//  wina
//
//  Network request detail view with headers, request, and response tabs.
//

import SwiftSoup
import SwiftUI
import SwiftUIBackports

struct LiveNetworkDetailView: View {
    let manager: NetworkManager
    let requestID: UUID

    var request: NetworkRequest? { manager.requests.first { $0.id == requestID } }

    var body: some View {
        if let request {
            NetworkDetailView(request: request)
        } else {
            ContentUnavailableView("Request No Longer Available", systemImage: "network.slash")
        }
    }
}

// MARK: - Network Detail View

struct NetworkDetailView: View {
    let request: NetworkRequest
    @Environment(\.dismiss) private var dismiss
    @State var selectedTab: DetailTab = .overview
    @State var feedbackState = CopiedFeedbackState()
    @State var shareItem: NetworkShareContent?
    @State var shareFileURL: URL?

    // URL expand/collapse state
    @State var isURLExpanded: Bool = false
    let urlCollapseThreshold = 80

    enum DetailTab: String, CaseIterable {
        case overview = "Overview"
        case headers = "Headers"
        case request = "Request"
        case response = "Response"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            requestSummary

            Divider()

            Picker("Tab", selection: $selectedTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            ScrollView {
                switch selectedTab {
                case .overview:
                    overviewContent
                case .headers:
                    headersContent
                case .request:
                    requestContent
                case .response:
                    responseContent
                }
            }
        }
        .copiedFeedbackOverlay($feedbackState.message)
        .dismissKeyboardOnTap()
        .sheet(item: $shareItem) { item in
            ShareSheet(content: item.content)
        }
        .sheet(item: $shareFileURL) { url in
            ShareSheet(fileURL: url)
        }
    }

    // MARK: - Header

    private var header: some View {
        DevToolsHeader(
            title: "Request Details",
            leftButtons: [
                .init(icon: "xmark.circle.fill", color: .secondary) {
                    dismiss()
                },
                .init(icon: "square.and.arrow.up") {
                    shareRequest()
                },
                .init(icon: "terminal") {
                    copyAsCurl()
                }
            ],
            rightButtons: []
        )
    }

    // MARK: - Summary

    private var isURLLong: Bool {
        request.url.count > urlCollapseThreshold
    }

    private var requestSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(request.method)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(methodColor, in: RoundedRectangle(cornerRadius: 6))

                if let status = request.status {
                    Text("\(status)")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(request.statusColor)
                }

                Text(request.durationText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                // Quick copy URL button
                CopyIconButton(text: request.url) {
                    feedbackState.showCopied("URL")
                }
            }

            // Collapsible URL with selectable text
            if isURLLong {
                VStack(alignment: .leading, spacing: 4) {
                    if isURLExpanded {
                        SelectableTextView(
                            text: request.url,
                            font: .monospacedSystemFont(ofSize: 12, weight: .regular),
                            padding: .zero
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(String(request.url.prefix(urlCollapseThreshold)) + "...")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isURLExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isURLExpanded ? "Show less" : "Show full URL")
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: isURLExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
                }
            } else {
                SelectableTextView(
                    text: request.url,
                    font: .monospacedSystemFont(ofSize: 12, weight: .regular),
                    padding: .zero
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Mixed Content warning
            if request.isMixedContent {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text("Mixed Content")
                        .font(.system(size: 12, weight: .medium))
                    Text("– insecure request on secure page")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            if let error = request.error {
                Text("Error: \(error)")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
    }

}

// MARK: - Detail Section

struct DetailSection<Content: View>: View {
    let title: String
    let rawText: String?
    var onCopy: ((String, String) -> Void)?
    var onShare: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @State private var showRaw: Bool = false
    @State private var isExpanded: Bool = true

    init(
        title: String,
        rawText: String? = nil,
        onCopy: ((String, String) -> Void)? = nil,
        onShare: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.rawText = rawText
        self.onCopy = onCopy
        self.onShare = onShare
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header with expand/collapse, Raw toggle, Share, and Copy buttons
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    // Chevron to indicate expand/collapse
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let rawText, !rawText.isEmpty {
                        // Raw/Table toggle button
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showRaw.toggle()
                            }
                        } label: {
                            Text(showRaw ? "Table" : "Raw")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .backport.glassEffect(in: .capsule)

                        // Share button (optional)
                        if let onShare {
                            GlassIconButton(
                                icon: "square.and.arrow.up",
                                size: .small,
                                accessibilityLabel: "Share"
                            ) {
                                onShare()
                            }
                        }

                        // Copy button
                        GlassIconButton(
                            icon: "doc.on.doc",
                            size: .small,
                            accessibilityLabel: "Copy to clipboard"
                        ) {
                            onCopy?(rawText, title)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    if showRaw, let rawText {
                        // Raw text view with UITextView for proper text selection
                        SelectableTextView(text: rawText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        content()
                    }
                }
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

// MARK: - Detail Table Row

struct DetailTableRow: View {
    let key: String
    let value: String
    var onCopy: ((String, String) -> Void)?
    var showBorder: Bool = true
    @State private var isExpanded: Bool = false

    init(key: String, value: String, onCopy: ((String, String) -> Void)? = nil, showBorder: Bool = true) {
        self.key = key
        self.value = value
        self.onCopy = onCopy
        self.showBorder = showBorder
    }

    private var isLongValue: Bool {
        value.count > 60 || value.contains("\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                Text(key)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.blue)
                    .frame(width: 100, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)

                if isLongValue && !isExpanded {
                    Text(value.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(value)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isLongValue {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: 16)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isLongValue {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if showBorder {
                Divider()
                    .background(Color(uiColor: .separator))
            }
        }
        .contextMenu {
            Button {
                onCopy?(value, key)
            } label: {
                Label("Copy Value", systemImage: "doc.on.doc")
            }
        }
    }
}

// MARK: - Body Header View

struct BodyHeaderView: View {
    let contentType: NetworkContentType
    let size: Int
    let discrepancyMessage: String?

    @State private var showDiscrepancyInfo = false

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            contentType.badge

            Text(formatBytes(size))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            if let discrepancyMessage {
                Button {
                    showDiscrepancyInfo = true
                } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDiscrepancyInfo) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Discrepancy detected")
                                .fontWeight(.semibold)
                        }
                        Text(discrepancyMessage)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.footnote)
                    .padding()
                    .frame(maxWidth: 280)
                    .presentationCompactAdaptation(.popover)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(uiColor: .tertiarySystemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - Response Search Bar

struct ResponseSearchBar: View {
    @Binding var searchText: String
    let currentMatch: Int
    let totalMatches: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    private var hasMatches: Bool { !searchText.isEmpty && totalMatches > 0 }

    var body: some View {
        HStack(spacing: 8) {
            // Search input field - fixed height to prevent layout shift on focus
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField("Search in response...", text: $searchText)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Placeholder to maintain consistent width
                    Color.clear
                        .frame(width: 14, height: 14)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))

            // Fixed-width navigation area to prevent layout shift
            HStack(spacing: 4) {
                if hasMatches {
                    Text("\(currentMatch + 1)/\(totalMatches)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else if !searchText.isEmpty {
                    Text("0/0")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Button(action: onPrevious) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!hasMatches)

                Button(action: onNext) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!hasMatches)
            }
            .foregroundStyle(hasMatches ? .primary : .tertiary)
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }
}

// MARK: - Content Type Mapping

extension NetworkContentType {
    /// Maps NetworkContentType to ResponseContentType for the ResponseFormatterView
    func toResponseContentType() -> ResponseContentType {
        switch self {
        case .json:
            return .json
        case .html:
            return .html
        case .xml:
            return .xml
        case .text:
            return .text
        case .formUrlEncoded:
            // Form-encoded data is displayed as plain text
            return .text
        }
    }
}
