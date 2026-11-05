//
//  PerformanceView.swift
//  wina
//
//  Performance panel with Web Vitals 2025.
//

import SwiftUI
import SwiftUIBackports

// MARK: - Performance Tab

enum PerformanceTab: String, CaseIterable {
    case metrics = "Metrics"
    case resources = "Resources"
    case timing = "Timing"

    var icon: String {
        switch self {
        case .metrics: return "gauge.with.dots.needle.bottom.50percent"
        case .resources: return "doc.fill"
        case .timing: return "clock"
        }
    }
}

// MARK: - Performance View

struct PerformanceView: View {
    let performanceManager: PerformanceManager
    let documentID: UUID
    let onCollect: () -> Void
    let onReload: () -> Void

    @Environment(\.closeDevTools) private var closeDevTools
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: PerformanceTab = .metrics
    @State private var searchText: String = ""
    @State private var expandedTypes: Set<ResourceType> = []
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollViewHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy?

    private var hasData: Bool {
        performanceManager.data.navigation != nil || !performanceManager.data.paints.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더 영역 (닫기, 새로고침 버튼)
            performanceHeader

            // 컨텐츠 영역
            Group {
                if performanceManager.isLoading {
                    loadingState
                } else if let error = performanceManager.lastError {
                    errorState(error)
                } else if performanceManager.data.resources.isEmpty && performanceManager.data.navigation == nil {
                    emptyState
                } else {
                    mainContent
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .dismissKeyboardOnTap()
        .onChange(of: documentID, initial: true) { _, _ in
            if !hasData && !performanceManager.isReloading {
                onCollect()
            }
        }
        .task {
            await AdManager.shared.showInterstitialAd(
                options: AdOptions(id: "performance_devtools"),
                adUnitId: AdManager.interstitialAdUnitId
            )
        }
    }

    private var mainContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geometryInner in
                    Color.clear
                        .onAppear {
                            scrollViewHeight = geometryInner.size.height
                        }
                }
                .frame(height: 0)

                VStack(spacing: 16) {
                    coreWebVitalsSection
                        .id("core-vitals")

                    metricsSection
                        .id("metrics")

                    resourcesSection
                        .id("resources")

                    timingSection
                        .id("timing")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    GeometryReader { geometryContent in
                        Color.clear
                            .onAppear {
                                contentHeight = geometryContent.size.height
                            }
                    }
                )
            }
            .scrollContentBackground(.hidden)
            .onScrollGeometryChange(for: Double.self) { scrollGeometry in
                scrollGeometry.contentOffset.y
            } action: { _, newValue in
                scrollOffset = newValue
            }
            .scrollNavigationOverlay(
                scrollOffset: scrollOffset,
                contentHeight: contentHeight,
                viewportHeight: scrollViewHeight,
                onScrollUp: { scrollUp(proxy: scrollProxy) },
                onScrollDown: { scrollDown(proxy: scrollProxy) }
            )
            .onAppear {
                scrollProxy = proxy
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var performanceHeader: some View {
        DevToolsHeader(
            title: "Performance",
            leftButtons: [
                .init(icon: "xmark.circle.fill", color: .secondary) {
                    (closeDevTools ?? { dismiss() })()
                },
                .init(icon: "trash", isDisabled: !hasData) {
                    performanceManager.clear()
                }
            ],
            rightButtons: [
                .init(
                    icon: performanceManager.isLoading ? "hourglass" : "arrow.clockwise",
                    isDisabled: performanceManager.isLoading
                ) {
                    onReload()
                }
            ]
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter metrics", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
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
                ForEach(PerformanceTab.allCases, id: \.self) { tab in
                    PerformanceFilterTab(
                        label: tab.rawValue,
                        icon: tab.icon,
                        isSelected: selectedTab == tab
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 36)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        ScrollViewReader { proxy in
            GeometryReader { outerGeo in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Core Web Vitals always shown at top
                        coreWebVitalsSection
                            .id("core-vitals")

                        // Tab content
                        switch selectedTab {
                        case .metrics:
                            metricsSection
                                .id("metrics")
                        case .resources:
                            resourcesSection
                                .id("resources")
                        case .timing:
                            timingSection
                                .id("timing")
                        }
                    }
                    .padding(16)
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

    // MARK: - Core Web Vitals Section

    private var coreWebVitalsSection: some View {
        PerformanceSection {
            VStack(spacing: 16) {
                overallScoreCard
                coreVitalsGrid
                coreVitalsStatus
            }
        }
    }

    private var overallScoreCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 8)

                Circle()
                    .trim(from: 0, to: CGFloat(performanceManager.data.totalScore) / 100)
                    .stroke(
                        performanceManager.data.scoreRating.color,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text("\(performanceManager.data.totalScore)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(performanceManager.data.scoreRating.color)
            }
            .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: performanceManager.data.scoreRating.icon)
                    Text(performanceManager.data.scoreRating.rawValue)
                }
                .font(.headline)
                .foregroundStyle(performanceManager.data.scoreRating.color)

                Text(verbatim: "Web Vitals 2025")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if performanceManager.data.navigation != nil {
                    Text("Measured at \(formatTimestamp(performanceManager.data.timestamp))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
    }

    private var coreVitalsGrid: some View {
        HStack(spacing: 12) {
            CoreVitalCard(
                label: "LCP",
                value: formatLCP(performanceManager.data.largestContentfulPaint),
                rating: performanceManager.data.lcpRating,
                description: "Largest Contentful Paint"
            )
            CoreVitalCard(
                label: "CLS",
                value: formatCLS(performanceManager.data.cls),
                rating: performanceManager.data.clsRating,
                description: "Cumulative Layout Shift"
            )
        }
    }

    private var coreVitalsStatus: some View {
        let passed = performanceManager.data.coreWebVitalsPass

        return HStack(spacing: 8) {
            Image(systemName: passed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(passed ? .green : .orange)

            Text(passed ? "Passed Core Web Vitals" : "Needs Improvement")
                .font(.caption.weight(.medium))
                .foregroundStyle(passed ? .green : .orange)

            Spacer()

            Text("LCP + CLS")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Resources Section

    @ViewBuilder
    private var resourcesSection: some View {
        let summary = resourceTypeSummary

        PerformanceSection(
            title: "By Type",
            trailing: ByteFormatter.format(totalResourceSize)
        ) {
            VStack(spacing: 0) {
                ForEach(Array(summary.enumerated()), id: \.element.type) { index, item in
                    if matchesSearch(item.type.rawValue) {
                        ResourceTypeRow(
                            type: item.type,
                            count: item.count,
                            size: item.size,
                            resources: item.resources,
                            isExpanded: expandedTypes.contains(item.type),
                            onToggle: {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    if expandedTypes.contains(item.type) {
                                        expandedTypes.remove(item.type)
                                    } else {
                                        expandedTypes.insert(item.type)
                                    }
                                }
                            }
                        )
                        if index < summary.count - 1 {
                            sectionDivider
                        }
                    }
                }
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    Spacer(minLength: 0)
                    ProgressView()
                        .scaleEffect(1.2)
                    VStack(spacing: 4) {
                        Text("Collecting Metrics")
                            .font(.headline)
                        Text("Analyzing page performance...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                VStack(spacing: 16) {
                    Spacer(minLength: 0)
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    VStack(spacing: 4) {
                        Text("No Performance Data")
                            .font(.headline)
                        Text("Navigate to a page to collect metrics")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width)
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func errorState(_ error: String) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
                    Spacer(minLength: 0)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Failed to collect metrics")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                }
                .padding()
                .frame(width: geometry.size.width)
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Helpers

    var sectionDivider: some View {
        Divider()
            .padding(.leading, 36)
    }

    func matchesSearch(_ text: String) -> Bool {
        searchText.isEmpty || text.localizedCaseInsensitiveContains(searchText)
    }

    private var resourceTypeSummary: [(type: ResourceType, count: Int, size: Int, resources: [ResourceTiming])] {
        var summary: [ResourceType: (count: Int, size: Int, resources: [ResourceTiming])] = [:]
        for resource in performanceManager.data.resources {
            let type = resource.resourceType
            var current = summary[type] ?? (0, 0, [])
            current.count += 1
            current.size += resource.displaySize
            current.resources.append(resource)
            summary[type] = current
        }
        return ResourceType.allCases
            .compactMap { type in
                guard let data = summary[type] else { return nil }
                return (type, data.count, data.size, data.resources)
            }
            .sorted { $0.size > $1.size }
    }

    private var totalResourceSize: Int {
        performanceManager.data.resources.reduce(0) { $0 + $1.displaySize }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatLCP(_ value: Double?) -> String {
        guard let value, value > 0 else { return "N/A" }
        return value >= 1000 ? String(format: "%.2fs", value / 1000) : String(format: "%.0fms", value)
    }

    private func formatCLS(_ value: Double) -> String {
        guard value >= 0 else { return "N/A" }
        return String(format: "%.3f", value)
    }

    // MARK: - Scroll Helpers

    private func scrollUp(proxy: ScrollViewProxy?) {
        guard let proxy else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("core-vitals", anchor: .top)
        }
    }

    private func scrollDown(proxy: ScrollViewProxy?) {
        guard let proxy else { return }
        let lastID: String
        switch selectedTab {
        case .metrics:
            lastID = "metrics"
        case .resources:
            lastID = "resources"
        case .timing:
            lastID = "timing"
        }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}

// MARK: - Performance Filter Tab

private struct PerformanceFilterTab: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(.primary)
                        .frame(height: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Performance Section

struct PerformanceSection<Content: View>: View {
    let title: String?
    let trailing: String?
    let content: () -> Content

    init(
        title: String? = nil,
        trailing: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let trailing {
                        Text(trailing)
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 4)
            }

            VStack(spacing: 0) {
                content()
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Resource Type Row

private struct ResourceTypeRow: View {
    let type: ResourceType
    let count: Int
    let size: Int
    let resources: [ResourceTiming]
    let isExpanded: Bool
    let onToggle: () -> Void

    // Performance: pre-sort outside View body to avoid repeated sorting on each render
    private var sortedTopResources: [ResourceTiming] {
        Array(resources.sorted(by: { $0.displaySize > $1.displaySize }).prefix(15))
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 16)

                    Text(type.rawValue)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("\(count)")
                        .foregroundStyle(.secondary)

                    Text(size > 0 ? ByteFormatter.format(size) : "—")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(size > 0 ? .secondary : .tertiary)
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(sortedTopResources) { resource in
                        ResourceDetailRow(resource: resource)
                            .padding(.leading, 24)
                            .padding(.vertical, 6)
                    }
                    if resources.count > 15 {
                        Text("+ \(resources.count - 15) more")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 24)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

}

// MARK: - Preview

#Preview("Good Performance") {
    PerformanceView(
        performanceManager: {
            let manager = PerformanceManager()
            manager.data = PerformanceData(
                navigation: NavigationTiming(
                    startTime: 0,
                    redirectTime: 0,
                    dnsTime: 23,
                    tcpTime: 45,
                    tlsTime: 67,
                    requestTime: 50,
                    responseTime: 89,
                    domProcessingTime: 234,
                    domContentLoadedTime: 567,
                    loadEventTime: 1234,
                    timeToFirstByte: 150
                ),
                resources: [
                    ResourceTiming(
                        id: UUID(), name: "https://example.com/script.js",
                        initiatorType: "script", startTime: 100, duration: 200,
                        transferSize: 45000, encodedBodySize: 45000, decodedBodySize: 120000
                    ),
                    ResourceTiming(
                        id: UUID(), name: "https://example.com/style.css",
                        initiatorType: "link", startTime: 50, duration: 150,
                        transferSize: 12000, encodedBodySize: 12000, decodedBodySize: 35000
                    )
                ],
                paints: [
                    PaintTiming(name: "first-paint", startTime: 345),
                    PaintTiming(name: "first-contentful-paint", startTime: 456)
                ],
                cls: 0.05,
                tbt: 150,
                largestContentfulPaint: 1000
            )
            return manager
        }(),
        documentID: UUID(),
        onCollect: {},
        onReload: {}
    )
}
