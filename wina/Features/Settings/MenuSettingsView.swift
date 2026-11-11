//
//  MenuSettingsView.swift
//  wina
//
//  Created by Claude on 12/28/25.
//

import SwiftUI

// MARK: - Menu Settings View (Unified Toolbar + AppBar)

struct MenuSettingsView: View {
    @State var settingsSearch = SettingsSearch()
    @State private var didLoadFromStorage = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editMode) private var editMode

    // Stored (persistent)
    @AppStorage("toolbarItemsOrder") private var storedToolbarData = Data()
    @AppStorage("appBarItemsOrder") private var storedAppBarData = Data()

    // Local state (editable)
    @State private var toolbarItems: [ToolbarItemState] = []
    @State private var appBarItems: [AppBarItemState] = []
    @State private var initialToolbarItems: [ToolbarItemState] = []
    @State private var initialAppBarItems: [AppBarItemState] = []
    @State private var didResetAll = false

    private var hasChanges: Bool {
        hasToolbarChanges || hasAppBarChanges
    }

    private var hasToolbarChanges: Bool {
        toolbarItems != initialToolbarItems || didResetAll && toolbarItems != toolbarRows(from: storedToolbarData)
    }

    private var hasAppBarChanges: Bool {
        appBarItems != initialAppBarItems || didResetAll && appBarItems != appBarRows(from: storedAppBarData)
    }

    var body: some View {
        SettingsSearchList(screen: .menu, search: $settingsSearch) {
            // MARK: - Toolbar Section
            Section {
                ForEach(toolbarItems) { item in
                    MenuItemRow(
                        icon: item.menuItem.icon,
                        label: item.menuItem.label,
                        description: item.menuItem.description,
                        isVisible: item.isVisible,
                        onToggle: { toggleToolbarItem(item) }
                    )
                    .settingsSearchItem("toolbar.\(item.menuItem.rawValue)")
                }
                .onMove(perform: moveToolbarItems)
            } header: {
                SectionHeader(
                    title: "Toolbar",
                    subtitle: "DevTools menu items. Long press to reorder.",
                    isSearching: settingsSearch.isActive,
                    onAll: { enableAllToolbar() },
                    onNone: { disableAllToolbar() }
                )
            }

            // MARK: - App Bar Section
            Section {
                ForEach(appBarItems) { item in
                    MenuItemRow(
                        icon: item.menuItem.icon,
                        label: item.menuItem.label,
                        description: item.menuItem.description,
                        isVisible: item.isVisible,
                        onToggle: { toggleAppBarItem(item) }
                    )
                    .settingsSearchItem("appBar.\(item.menuItem.rawValue)")
                }
                .onMove(perform: moveAppBarItems)
            } header: {
                SectionHeader(
                    title: "App Bar",
                    subtitle: "Navigation buttons. Info and Settings are always visible.",
                    isSearching: settingsSearch.isActive,
                    onAll: { enableAllAppBar() },
                    onNone: { disableAllAppBar() }
                )
            }

            // MARK: - Reset Section
            Section {
                HStack {
                    Spacer()
                    GlassActionButton("Reset All", icon: "arrow.counterclockwise", style: .destructive) {
                        resetToDefaults()
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(Text(verbatim: "Menu"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Apply") { applyChanges() }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if hasChanges {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Changes will apply to menus")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hasChanges)
        .onAppear {
            guard !didLoadFromStorage else { return }
            didLoadFromStorage = true
            loadFromStorage()
            editMode?.wrappedValue = .active
        }
    }

    // MARK: - Storage

    private func toolbarRows(from data: Data) -> [ToolbarItemState] {
        if let rows = try? JSONDecoder().decode([ToolbarItemState].self, from: data), !rows.isEmpty { return rows }
        return DevToolsMenuItem.defaultOrder.map { ToolbarItemState(menuItem: $0, isVisible: true) }
    }

    private func appBarRows(from data: Data) -> [AppBarItemState] {
        if let rows = try? JSONDecoder().decode([AppBarItemState].self, from: data), !rows.isEmpty { return rows }
        return AppBarMenuItem.defaultOrder.map { AppBarItemState(menuItem: $0, isVisible: true) }
    }

    private func loadFromStorage() {
        let settings = AgentBrowserSettings.shared
        let toolbarData = settings.value("toolbarItemsOrder", fallback: storedToolbarData)
        let appBarData = settings.value("appBarItemsOrder", fallback: storedAppBarData)
        initialToolbarItems = toolbarRows(from: toolbarData)
        initialAppBarItems = appBarRows(from: appBarData)

        let toolbarIds = Set(initialToolbarItems.map(\.menuItem))
        toolbarItems = initialToolbarItems + DevToolsMenuItem.allCases.filter { !toolbarIds.contains($0) }
            .map { ToolbarItemState(menuItem: $0, isVisible: true) }
        let appBarIds = Set(initialAppBarItems.map(\.menuItem))
        appBarItems = initialAppBarItems + AppBarMenuItem.allCases.filter { !appBarIds.contains($0) }
            .map { AppBarItemState(menuItem: $0, isVisible: true) }
    }

    private func applyChanges() {
        var changes: [String: AnyHashable] = [:]
        if hasToolbarChanges, let encoded = try? JSONEncoder().encode(toolbarItems) {
            changes["toolbarItemsOrder"] = encoded
        }
        if hasAppBarChanges, let encoded = try? JSONEncoder().encode(appBarItems) {
            changes["appBarItemsOrder"] = encoded
        }
        AgentBrowserSettings.shared.apply(changes, persist: true)
        dismiss()
    }

    // MARK: - Toolbar Actions

    private func toggleToolbarItem(_ item: ToolbarItemState) {
        guard let index = toolbarItems.firstIndex(where: { $0.id == item.id }) else { return }
        toolbarItems[index].isVisible.toggle()
    }

    private func moveToolbarItems(from source: IndexSet, to destination: Int) {
        guard !settingsSearch.isActive else { return }
        toolbarItems.move(fromOffsets: source, toOffset: destination)
    }

    private func enableAllToolbar() {
        withAnimation {
            for index in toolbarItems.indices {
                toolbarItems[index].isVisible = true
            }
        }
    }

    private func disableAllToolbar() {
        withAnimation {
            for index in toolbarItems.indices {
                toolbarItems[index].isVisible = false
            }
        }
    }

    // MARK: - App Bar Actions

    private func toggleAppBarItem(_ item: AppBarItemState) {
        guard let index = appBarItems.firstIndex(where: { $0.id == item.id }) else { return }
        appBarItems[index].isVisible.toggle()
    }

    private func moveAppBarItems(from source: IndexSet, to destination: Int) {
        guard !settingsSearch.isActive else { return }
        appBarItems.move(fromOffsets: source, toOffset: destination)
    }

    private func enableAllAppBar() {
        withAnimation {
            for index in appBarItems.indices {
                appBarItems[index].isVisible = true
            }
        }
    }

    private func disableAllAppBar() {
        withAnimation {
            for index in appBarItems.indices {
                appBarItems[index].isVisible = false
            }
        }
    }

    // MARK: - Reset

    private func resetToDefaults() {
        withAnimation {
            didResetAll = true
            toolbarItems = DevToolsMenuItem.defaultOrder.map { ToolbarItemState(menuItem: $0, isVisible: true) }
            appBarItems = AppBarMenuItem.defaultOrder.map { AppBarItemState(menuItem: $0, isVisible: true) }
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let isSearching: Bool
    let onAll: () -> Void
    let onNone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                if !isSearching {
                    Button("All") { onAll() }
                        .font(.caption)
                    Text("/")
                        .foregroundStyle(.tertiary)
                    Button("None") { onNone() }
                        .font(.caption)
                }
            }
            if !isSearching {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
    }
}

// MARK: - Menu Item Row

private struct MenuItemRow: View {
    let icon: String
    let label: LocalizedStringKey
    let description: LocalizedStringKey
    let isVisible: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(isVisible ? .primary : .tertiary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .foregroundStyle(isVisible ? .primary : .secondary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isVisible },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        MenuSettingsView()
    }
}
