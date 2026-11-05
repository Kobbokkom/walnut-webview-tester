//
//  SafariVCMenuSettingsView.swift
//  wina
//
//  Created by Claude on 1/9/26.
//

import SwiftUI

// MARK: - SafariVC Menu Settings View

struct SafariVCMenuSettingsView: View {
    @State var settingsSearch = SettingsSearch()
    @State private var didLoadFromStorage = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editMode) private var editMode

    // Stored (persistent) - separate keys from WKWebView
    @AppStorage("safariToolbarItemsOrder") private var storedToolbarData = Data()
    @AppStorage("safariAppBarItemsOrder") private var storedAppBarData = Data()

    // Local state (editable)
    @State private var toolbarItems: [SafariVCToolbarItemState] = []
    @State private var appBarItems: [SafariVCAppBarItemState] = []

    private var hasChanges: Bool {
        hasToolbarChanges || hasAppBarChanges
    }

    private var hasToolbarChanges: Bool {
        guard let stored = try? JSONDecoder().decode([SafariVCToolbarItemState].self, from: storedToolbarData) else {
            let defaults = SafariVCToolbarMenuItem.defaultOrder.map {
                SafariVCToolbarItemState(menuItem: $0, isVisible: true)
            }
            return toolbarItems != defaults
        }
        return toolbarItems != stored
    }

    private var hasAppBarChanges: Bool {
        guard let stored = try? JSONDecoder().decode([SafariVCAppBarItemState].self, from: storedAppBarData) else {
            let defaults = SafariVCAppBarMenuItem.defaultOrder.map {
                SafariVCAppBarItemState(menuItem: $0, isVisible: true)
            }
            return appBarItems != defaults
        }
        return appBarItems != stored
    }

    var body: some View {
        SettingsSearchList(screen: .safariMenu, search: $settingsSearch) {
            // MARK: - Toolbar Section
            Section {
                ForEach(toolbarItems) { item in
                    SafariVCMenuItemRow(
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
                SafariVCSectionHeader(
                    title: "Toolbar",
                    subtitle: "Screenshot and recording. Long press to reorder.",
                    isSearching: settingsSearch.isActive,
                    onAll: { enableAllToolbar() },
                    onNone: { disableAllToolbar() }
                )
            }

            // MARK: - App Bar Section
            Section {
                ForEach(appBarItems) { item in
                    SafariVCMenuItemRow(
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
                SafariVCSectionHeader(
                    title: "App Bar",
                    subtitle: "Home button. Info and Settings are always visible.",
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

    private func loadFromStorage() {
        // Load toolbar items
        if let decoded = try? JSONDecoder().decode([SafariVCToolbarItemState].self, from: storedToolbarData),
           !decoded.isEmpty {
            var loadedItems = decoded
            let loadedIds = Set(loadedItems.map { $0.menuItem })
            for menuItem in SafariVCToolbarMenuItem.allCases where !loadedIds.contains(menuItem) {
                loadedItems.append(SafariVCToolbarItemState(menuItem: menuItem, isVisible: true))
            }
            toolbarItems = loadedItems
        } else {
            toolbarItems = SafariVCToolbarMenuItem.defaultOrder.map {
                SafariVCToolbarItemState(menuItem: $0, isVisible: true)
            }
        }

        // Load app bar items
        if let decoded = try? JSONDecoder().decode([SafariVCAppBarItemState].self, from: storedAppBarData),
           !decoded.isEmpty {
            var loadedItems = decoded
            let loadedIds = Set(loadedItems.map { $0.menuItem })
            for menuItem in SafariVCAppBarMenuItem.allCases where !loadedIds.contains(menuItem) {
                loadedItems.append(SafariVCAppBarItemState(menuItem: menuItem, isVisible: true))
            }
            appBarItems = loadedItems
        } else {
            appBarItems = SafariVCAppBarMenuItem.defaultOrder.map {
                SafariVCAppBarItemState(menuItem: $0, isVisible: true)
            }
        }
    }

    private func applyChanges() {
        if let encoded = try? JSONEncoder().encode(toolbarItems) {
            storedToolbarData = encoded
        }
        if let encoded = try? JSONEncoder().encode(appBarItems) {
            storedAppBarData = encoded
        }
        dismiss()
    }

    // MARK: - Toolbar Actions

    private func toggleToolbarItem(_ item: SafariVCToolbarItemState) {
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

    private func toggleAppBarItem(_ item: SafariVCAppBarItemState) {
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
            toolbarItems = SafariVCToolbarMenuItem.defaultOrder.map {
                SafariVCToolbarItemState(menuItem: $0, isVisible: true)
            }
            appBarItems = SafariVCAppBarMenuItem.defaultOrder.map {
                SafariVCAppBarItemState(menuItem: $0, isVisible: true)
            }
        }
    }
}

// MARK: - Section Header

private struct SafariVCSectionHeader: View {
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

private struct SafariVCMenuItemRow: View {
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
        SafariVCMenuSettingsView()
    }
}
