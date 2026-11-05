//
//  ConsoleView.swift
//  wina
//
//  Console DevTools view for log inspection and JavaScript execution.
//

import SwiftUI

// MARK: - Console View

struct ConsoleView: View {
    let consoleManager: ConsoleManager
    var navigator: WebViewNavigator?  // Optional - for JS execution
    @Environment(\.closeDevTools) private var closeDevTools
    @Environment(\.dismiss) private var dismiss
    @State var filterType: ConsoleLog.LogType?
    @State var searchText: String = ""
    @State var useRegex: Bool = false
    @State var shareItem: ShareContent?
    @State var showSettings: Bool = false
    // Log types to show in "All" tab (user configurable)
    @State var enabledLogTypes: Set<ConsoleLog.LogType> = Set(ConsoleLog.LogType.displayableTypes)
    // AppStorage for settings indicator (matches ConsoleSettingsSheet)
    @AppStorage("consolePreserveLog") private var preserveLog: Bool = false
    @AppStorage(LogClearStrategy.consoleDefaultsKey) private var clearStrategyRaw: String = LogClearStrategy.keep.rawValue
    // JavaScript input
    @State var jsInput: String = ""
    @State var commandHistory: [String] = []
    @State var historyIndex: Int = -1
    let maxCommandHistory = 100
    @FocusState var isInputFocused: Bool
    @FocusState var isFilterFocused: Bool
    // Scroll navigation state
    @State var scrollOffset: CGFloat = 0
    @State var scrollViewHeight: CGFloat = 0
    @State var contentHeight: CGFloat = 0
    @State var scrollProxy: ScrollViewProxy?

    var filteredLogs: [ConsoleLog] {
        var result = consoleManager.logs

        // Filter out groupEnd (internal tracking only, not displayed)
        result = result.filter { $0.type != .groupEnd }

        // Filter out logs inside collapsed groups
        result = result.filter { log in
            // If this log belongs to a group, check if any ancestor is collapsed
            if let groupId = log.groupId, log.type != .group && log.type != .groupCollapsed {
                return !consoleManager.collapsedGroups.contains(groupId)
            }
            return true
        }

        if let filterType {
            result = result.filter { $0.type == filterType }
        } else {
            // "All" tab - filter by user-selected log types
            result = result.filter { enabledLogTypes.contains($0.type) }
        }

        if !searchText.isEmpty {
            if useRegex, case .success(let regex) = RegexFilter.compile(searchText) {
                result = result.filter { log in
                    RegexFilter.matchesLog(message: log.message, source: log.source, regex: regex)
                }
            } else if !useRegex {
                result = result.filter {
                    $0.message.localizedCaseInsensitiveContains(searchText)
                    || ($0.source?.localizedCaseInsensitiveContains(searchText) ?? false)
                }
            }
        }

        return result
    }

    // Settings button highlight when any setting is active
    private var settingsActive: Bool {
        useRegex || preserveLog ||
        clearStrategyRaw != LogClearStrategy.keep.rawValue ||
        enabledLogTypes.count != ConsoleLog.LogType.displayableTypes.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom toolbar - full control over layout
            consoleHeader

            // Search bar
            searchBar

            // Filter tabs (Chrome DevTools style)
            filterTabs

            Divider()

            // Log list
            if filteredLogs.isEmpty {
                emptyState
            } else {
                logList
            }

            // JavaScript execution input (only shown when navigator is available)
            if navigator != nil {
                jsInputField
            }
        }
        .dismissKeyboardOnTap()
        .sheet(item: $shareItem) { item in
            ShareSheet(content: item.content)
        }
        .sheet(isPresented: $showSettings) {
            ConsoleSettingsSheet(
                useRegex: $useRegex,
                enabledLogTypes: $enabledLogTypes
            )
        }
        .task {
            await AdManager.shared.showInterstitialAd(
                options: AdOptions(id: "console_devtools"),
                adUnitId: AdManager.interstitialAdUnitId
            )
        }
    }

    // MARK: - Console Header

    private var consoleHeader: some View {
        DevToolsHeader(
            title: "Console",
            leftButtons: [
                .init(icon: "xmark.circle.fill", color: .secondary) {
                    (closeDevTools ?? { dismiss() })()
                },
                .init(
                    icon: "trash",
                    isDisabled: consoleManager.logs.isEmpty
                ) {
                    consoleManager.clear()
                },
                .init(
                    icon: "square.and.arrow.up",
                    isDisabled: filteredLogs.isEmpty
                ) {
                    shareItem = ShareContent(content: ConsoleExporter.exportAsText(filteredLogs))
                }
            ],
            rightButtons: [
                .init(
                    icon: "play.fill",
                    activeIcon: "pause.fill",
                    color: .green,
                    activeColor: .red,
                    isActive: consoleManager.isCapturing
                ) {
                    consoleManager.isCapturing.toggle()
                },
                .init(
                    icon: "gearshape",
                    activeIcon: "gearshape.fill",
                    isActive: settingsActive
                ) {
                    showSettings = true
                }
            ]
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(useRegex ? "Regex" : "Filter", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isFilterFocused)
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
}

// MARK: - Preview

#Preview {
    let manager = ConsoleManager()
    manager.addLog(type: "log", message: "Application started", source: "app.js:1")
    manager.addLog(type: "info", message: "User session initialized", source: "auth.js:45")

    // Console group example
    manager.addLog(type: "group", message: "User Data Loading", source: "user.js:10")
    manager.addLog(type: "log", message: "Fetching user profile...", source: "user.js:12")
    manager.addLog(type: "log", message: "User ID: 12345", source: "user.js:15")
    manager.addLog(type: "groupEnd", message: "", source: nil)

    // Collapsed group example
    manager.addLog(type: "groupCollapsed", message: "Debug Info (collapsed)", source: "debug.js:1")
    manager.addLog(type: "debug", message: "This should be hidden", source: "debug.js:2")
    manager.addLog(type: "groupEnd", message: "", source: nil)

    manager.addLog(type: "warn", message: "Deprecated API usage: navigator.userAgent", source: "utils.js:78")
    manager.addLog(type: "error", message: "Failed to fetch: 404 Not Found", source: "api.js:31")

    // Console table example
    manager.addLog(
        type: "table",
        message: "[{\"name\":\"Alice\",\"age\":\"25\",\"city\":\"Seoul\"},{\"name\":\"Bob\",\"age\":\"30\",\"city\":\"Tokyo\"},{\"name\":\"Carol\",\"age\":\"28\",\"city\":\"NYC\"}]",
        source: "data.js:50"
    )

    // Long message to test expansion
    manager.addLog(
        type: "log",
        message: """
            Response: {
              "status": "ok",
              "data": [1, 2, 3, 4, 5],
              "metadata": {
                "page": 1,
                "total": 100,
                "hasMore": true
              }
            }
            """,
        source: "api.js:45"
    )
    manager.addLog(
        type: "error",
        message: "Uncaught TypeError: Cannot read property 'map' of undefined\n    at processData (main.js:123)\n    at handleResponse (api.js:45)\n    at XMLHttpRequest.onload (fetch.js:89)",
        source: "main.js:123"
    )

    return ConsoleView(consoleManager: manager)
        .devToolsSheet()
}
