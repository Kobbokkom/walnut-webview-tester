//
//  ConsoleView+Components.swift
//  wina
//
//  Console view UI components: filter tabs, empty state, log list.
//

import SwiftUI

// MARK: - Console View Components

extension ConsoleView {
    // MARK: - Filter Tabs

    var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ConsoleFilterTab(label: "All", count: consoleManager.logs.count, isSelected: session.filterType == nil) {
                    session.filterType = nil
                }

                ConsoleFilterTab(label: "Errors", count: consoleManager.errorCount, isSelected: session.filterType == .error, color: .red) {
                    session.filterType = .error
                }

                ConsoleFilterTab(label: "Warnings", count: consoleManager.warnCount, isSelected: session.filterType == .warn, color: .orange) {
                    session.filterType = .warn
                }

                ForEach([ConsoleLog.LogType.info, .log, .debug], id: \.self) { type in
                    ConsoleFilterTab(
                        label: type.label,
                        count: consoleManager.logs.filter { $0.type == type }.count,
                        isSelected: session.filterType == type
                    ) {
                        session.filterType = type
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 36)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: - Empty State

    var emptyState: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Image(systemName: "terminal")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text(consoleManager.logs.isEmpty ? "No logs" : "No matches")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !consoleManager.isCapturing {
                        Label("Paused", systemImage: "pause.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width)
                .frame(minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Log List

    var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredLogs) { log in
                        LogRow(log: log, consoleManager: consoleManager)
                            .id(log.id)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemBackground))
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(
                    offset: geometry.contentOffset.y,
                    contentHeight: geometry.contentSize.height,
                    viewportHeight: geometry.visibleRect.height
                )
            } action: { oldValue, newValue in
                // Batch update to reduce state changes
                if oldValue != newValue {
                    scrollOffset = newValue.offset
                    contentHeight = newValue.contentHeight
                    scrollViewHeight = newValue.viewportHeight
                }
            }
            .onAppear {
                scrollProxy = proxy
            }
            .onChange(of: consoleManager.logs.count) { _, _ in
                if let lastLog = filteredLogs.last {
                    proxy.scrollTo(lastLog.id, anchor: .bottom)
                }
            }
            // 스크롤 네비게이션 버튼 오버레이
            .scrollNavigationOverlay(
                scrollOffset: scrollOffset,
                contentHeight: contentHeight,
                viewportHeight: scrollViewHeight,
                onScrollUp: { scrollUp(proxy: scrollProxy) },
                onScrollDown: { scrollDown(proxy: scrollProxy) }
            )
        }
    }

    // MARK: - Scroll Navigation

    func scrollUp(proxy: ScrollViewProxy?) {
        guard let proxy, let firstLog = filteredLogs.first else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(firstLog.id, anchor: .top)
        }
    }

    func scrollDown(proxy: ScrollViewProxy?) {
        guard let proxy, let lastLog = filteredLogs.last else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(lastLog.id, anchor: .bottom)
        }
    }
}
