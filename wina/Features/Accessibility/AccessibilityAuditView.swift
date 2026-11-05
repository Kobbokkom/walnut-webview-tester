//
//  AccessibilityAuditView.swift
//  wina
//
//  Accessibility audit tool using axe-core for WCAG compliance checking.
//

import SwiftUI
import SwiftUIBackports

// MARK: - Accessibility Issue Model

struct AccessibilityIssue: Identifiable, Equatable {
    let id = UUID()
    let severity: Severity
    let category: Category
    let help: String  // Short help message
    let failureSummary: String  // Detailed failure info
    let element: String  // Truncated element for display
    let fullHtml: String  // Full HTML for copy
    let selector: String?  // CSS selector for the element
    let helpUrl: String?  // Link to axe-core documentation
    let ruleId: String?  // axe-core rule ID

    enum Severity: String, CaseIterable {
        case error  // critical, serious
        case warning  // moderate
        case info  // minor

        var icon: String {
            switch self {
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .error: return .red
            case .warning: return .orange
            case .info: return .blue
            }
        }

        var label: String {
            switch self {
            case .error: return "Errors"
            case .warning: return "Warnings"
            case .info: return "Info"
            }
        }

        static func from(impact: String) -> Severity {
            switch impact.lowercased() {
            case "critical", "serious": return .error
            case "moderate": return .warning
            default: return .info
            }
        }
    }

    enum Category: String, CaseIterable {
        case images
        case links
        case buttons
        case forms
        case headings
        case aria
        case contrast
        case keyboard
        case language
        case structure
        case other

        var icon: String {
            switch self {
            case .images: return "photo"
            case .links: return "link"
            case .buttons: return "hand.tap"
            case .forms: return "list.bullet.rectangle"
            case .headings: return "textformat.size"
            case .aria: return "accessibility"
            case .contrast: return "circle.lefthalf.filled"
            case .keyboard: return "keyboard"
            case .language: return "globe"
            case .structure: return "rectangle.3.group"
            case .other: return "questionmark.circle"
            }
        }

        var label: String {
            switch self {
            case .images: return "Images"
            case .links: return "Links"
            case .buttons: return "Buttons"
            case .forms: return "Forms"
            case .headings: return "Headings"
            case .aria: return "ARIA"
            case .contrast: return "Contrast"
            case .keyboard: return "Keyboard"
            case .language: return "Language"
            case .structure: return "Structure"
            case .other: return "Other"
            }
        }

        // swiftlint:disable:next cyclomatic_complexity
        static func from(tags: [String], ruleId: String) -> Category {
            // Check rule ID first for specific mappings
            if ruleId.contains("image") || ruleId.contains("alt") {
                return .images
            }
            if ruleId.contains("link") {
                return .links
            }
            if ruleId.contains("button") {
                return .buttons
            }
            if ruleId.contains("label") || ruleId.contains("input") || ruleId.contains("form") {
                return .forms
            }
            if ruleId.contains("heading") {
                return .headings
            }
            if ruleId.contains("color") || ruleId.contains("contrast") {
                return .contrast
            }
            if ruleId.contains("focus") || ruleId.contains("keyboard") || ruleId.contains("tabindex") {
                return .keyboard
            }
            if ruleId.contains("lang") || ruleId.contains("language") {
                return .language
            }

            // Check tags for category
            for tag in tags {
                let lowered = tag.lowercased()
                if lowered.contains("image") { return .images }
                if lowered.contains("link") { return .links }
                if lowered.contains("button") { return .buttons }
                if lowered.contains("form") || lowered.contains("label") { return .forms }
                if lowered.contains("heading") || lowered.contains("structure") { return .structure }
                if lowered.contains("aria") { return .aria }
                if lowered.contains("color") { return .contrast }
                if lowered.contains("keyboard") { return .keyboard }
                if lowered.contains("language") { return .language }
            }

            return .other
        }
    }
}

// MARK: - Accessibility Audit View

struct AccessibilityAuditView: View {
    let navigator: WebViewNavigator?

    @Environment(\.dismiss) private var dismiss
    @State private var feedbackState = CopiedFeedbackState()
    @State private var showingShareSheet: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollViewHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy?

    // manager에서 상태 가져오기 (sheet 닫아도 유지됨)
    private var manager: AccessibilityManager? { navigator?.accessibilityManager }
    private var issues: [AccessibilityIssue] { manager?.issues ?? [] }
    private var isScanning: Bool { manager?.isScanning ?? false }
    private var hasScanned: Bool { manager?.hasScanned ?? false }
    private var filterSeverity: AccessibilityIssue.Severity? { manager?.filterSeverity }
    private var searchText: String { manager?.searchText ?? "" }

    private var filteredIssues: [AccessibilityIssue] {
        var result = issues

        if let severity = filterSeverity {
            result = result.filter { $0.severity == severity }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.help.localizedCaseInsensitiveContains(searchText)
                    || $0.element.localizedCaseInsensitiveContains(searchText)
                    || $0.category.label.localizedCaseInsensitiveContains(searchText)
                    || ($0.ruleId?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return result
    }

    private var issueCountBySeverity: [AccessibilityIssue.Severity: Int] {
        Dictionary(grouping: issues, by: \.severity).mapValues(\.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            filterTabs

            Divider()

            if isScanning {
                scanningState
            } else if let error = manager?.errorMessage {
                ContentUnavailableView {
                    Label("Audit Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await runAudit() } }
                }
            } else if !hasScanned {
                initialState
            } else if filteredIssues.isEmpty {
                emptyState
            } else {
                issuesList
            }
        }
        .copiedFeedbackOverlay($feedbackState.message)
        .dismissKeyboardOnTap()
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(content: generateShareText())
        }
        .task {
            await AdManager.shared.showInterstitialAd(
                options: AdOptions(id: "accessibility_devtools"),
                adUnitId: AdManager.interstitialAdUnitId
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        DevToolsHeader(
            title: "Accessibility",
            leftButtons: [
                .init(icon: "xmark.circle.fill", color: .secondary) {
                    dismiss()
                },
                .init(
                    icon: "trash",
                    isDisabled: issues.isEmpty || isScanning
                ) {
                    // manager의 clear 메서드로 결과 초기화
                    manager?.clear()
                },
                .init(
                    icon: "square.and.arrow.up",
                    isDisabled: issues.isEmpty || isScanning
                ) {
                    showingShareSheet = true
                }
            ],
            rightButtons: [
                .init(
                    icon: "arrow.clockwise",
                    isDisabled: isScanning
                ) {
                    Task { await runAudit() }
                }
            ]
        )
    }

    private func generateShareText() -> String {
        var lines: [String] = []

        // Header
        lines.append("# Accessibility Audit Report")
        lines.append("")
        if let url = navigator?.currentURL?.absoluteString {
            lines.append("URL: \(url)")
        }
        lines.append("Date: \(Date().formatted(date: .abbreviated, time: .shortened))")
        lines.append("")

        // Summary
        let errorCount = issueCountBySeverity[.error] ?? 0
        let warningCount = issueCountBySeverity[.warning] ?? 0
        let infoCount = issueCountBySeverity[.info] ?? 0
        lines.append("## Summary")
        lines.append("- Errors: \(errorCount)")
        lines.append("- Warnings: \(warningCount)")
        lines.append("- Info: \(infoCount)")
        lines.append("- Total: \(issues.count)")
        lines.append("")

        // Issues by severity
        for severity in AccessibilityIssue.Severity.allCases {
            let severityIssues = issues.filter { $0.severity == severity }
            if severityIssues.isEmpty { continue }

            lines.append("## \(severity.label) (\(severityIssues.count))")
            lines.append("")

            for (index, issue) in severityIssues.enumerated() {
                lines.append("### \(index + 1). \(issue.help)")
                if let ruleId = issue.ruleId {
                    lines.append("- Rule: \(ruleId)")
                }
                lines.append("- Category: \(issue.category.label)")
                if !issue.failureSummary.isEmpty {
                    lines.append("- Details: \(issue.failureSummary)")
                }
                if let selector = issue.selector {
                    lines.append("- Selector: \(selector)")
                }
                lines.append("- HTML: \(issue.fullHtml)")
                if let helpUrl = issue.helpUrl {
                    lines.append("- Help: \(helpUrl)")
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Search Bar

    // searchText binding (manager 연결)
    private var searchTextBinding: Binding<String> {
        Binding(
            get: { manager?.searchText ?? "" },
            set: { manager?.searchText = $0 }
        )
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter issues", text: searchTextBinding)
                .textFieldStyle(.plain)
            if !searchTextBinding.wrappedValue.isEmpty {
                Button {
                    searchTextBinding.wrappedValue = ""
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
                FilterTab(
                    label: "All",
                    count: issues.count,
                    isSelected: filterSeverity == nil
                ) {
                    manager?.filterSeverity = nil
                }

                ForEach(AccessibilityIssue.Severity.allCases, id: \.self) { severity in
                    FilterTab(
                        label: severity.label,
                        count: issueCountBySeverity[severity] ?? 0,
                        isSelected: filterSeverity == severity,
                        color: severity.color
                    ) {
                        manager?.filterSeverity = severity
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 36)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: - States

    private var initialState: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    Spacer(minLength: 0)
                    Image(systemName: "accessibility")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text(verbatim: "Accessibility Audit")
                        .font(.headline)
                    Text("Scan the current page for accessibility issues")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    GlassActionButton("Run Audit", icon: "play.fill", style: .primary) {
                        Task { await runAudit() }
                    }
                    Spacer(minLength: 0)
                }
                .padding()
                .frame(width: geometry.size.width)
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var scanningState: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    Spacer(minLength: 0)
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Scanning...")
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

    private var emptyState: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                    Text(issues.isEmpty ? "No issues found" : "No matching issues")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if issues.isEmpty {
                        Text("Great! This page passes basic accessibility checks.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer(minLength: 0)
                }
                .padding()
                .frame(width: geometry.size.width)
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Issues List

    private var issuesList: some View {
        ScrollViewReader { proxy in
            GeometryReader { outerGeo in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredIssues) { issue in
                            IssueRow(issue: issue) {
                                feedbackState.showCopied()
                            }
                            .id(issue.id)
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
                }
                .onChange(of: outerGeo.size.height) { _, newHeight in
                    scrollViewHeight = newHeight
                }
                .scrollNavigationOverlay(
                    scrollOffset: scrollOffset,
                    contentHeight: contentHeight,
                    viewportHeight: scrollViewHeight,
                    onScrollUp: { scrollUp(proxy: scrollProxy) },
                    onScrollDown: { scrollDown(proxy: scrollProxy) }
                )
            }
            .onAppear {
                scrollProxy = proxy
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollUp(proxy: ScrollViewProxy?) {
        guard let proxy, let firstIssue = filteredIssues.first else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(firstIssue.id, anchor: .top)
        }
    }

    private func scrollDown(proxy: ScrollViewProxy?) {
        guard let proxy, let lastIssue = filteredIssues.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastIssue.id, anchor: .bottom)
        }
    }

    // MARK: - Audit Logic

    private func runAudit() async {
        guard let navigator, let manager else { return }
        await manager.runAudit(navigator: navigator)
    }

}

// MARK: - Filter Tab

private struct FilterTab: View {
    let label: String
    let count: Int
    let isSelected: Bool
    var color: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                if count != 0 {  // swiftlint:disable:this empty_count
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            isSelected ? color.opacity(0.2) : Color.secondary.opacity(0.15),
                            in: Capsule()
                        )
                }
            }
            .foregroundStyle(isSelected ? color : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(color)
                        .frame(height: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Issue Row

private struct IssueRow: View {
    let issue: AccessibilityIssue
    let onCopy: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var isExpanded: Bool = false

    private var fullMessage: String {
        issue.failureSummary.isEmpty ? issue.help : "\(issue.help): \(issue.failureSummary)"
    }

    private var copyText: String {
        var parts: [String] = []
        if let ruleId = issue.ruleId {
            parts.append("Rule: \(ruleId)")
        }
        parts.append("Severity: \(issue.severity.rawValue)")
        parts.append("Category: \(issue.category.label)")
        parts.append("Issue: \(issue.help)")
        if !issue.failureSummary.isEmpty {
            parts.append("Details: \(issue.failureSummary)")
        }
        if let selector = issue.selector {
            parts.append("Selector: \(selector)")
        }
        parts.append("HTML: \(issue.fullHtml)")
        if let helpUrl = issue.helpUrl {
            parts.append("Help: \(helpUrl)")
        }
        return parts.joined(separator: "\n")
    }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                // Severity icon
                Image(systemName: issue.severity.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(issue.severity.color)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    // Category badge + rule ID
                    HStack(spacing: 6) {
                        Label(issue.category.label, systemImage: issue.category.icon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(issue.severity.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(issue.severity.color.opacity(0.15), in: Capsule())

                        if let ruleId = issue.ruleId {
                            Text(ruleId)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        // Chevron indicator
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }

                    // Help message (compact when collapsed, full when expanded)
                    Text(isExpanded ? fullMessage : issue.help)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(isExpanded ? nil : 1)
                        .multilineTextAlignment(.leading)

                    // Element (truncated when collapsed)
                    Text(isExpanded ? issue.fullHtml : issue.element)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? 12 : 1)
                        .multilineTextAlignment(.leading)

                    // Expanded details
                    if isExpanded {
                        expandedDetails
                    }
                }

                // Action buttons
                actionButtons
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(issue.severity == .error ? Color.red.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 42)
        }
    }

    @ViewBuilder
    private var expandedDetails: some View {
        // Selector only (failureSummary is now shown in fullMessage)
        if let selector = issue.selector {
            VStack(alignment: .leading, spacing: 2) {
                Text("Selector")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(selector)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 4) {
            // Copy button
            CopyIconButton(text: copyText, onCopy: onCopy)

            // Help link button
            if let helpUrl = issue.helpUrl, let url = URL(string: helpUrl) {
                Button {
                    openURL(url)
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    AccessibilityAuditView(navigator: WebViewNavigator())
}
