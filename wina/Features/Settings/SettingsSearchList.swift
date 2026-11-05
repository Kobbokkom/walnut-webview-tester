import SwiftUI

enum SettingsSearchRole {
    case item(String), result, notice
}

extension ContainerValues {
    @Entry var settingsSearchRole: SettingsSearchRole?
}

extension View {
    func settingsSearchItem(_ id: String) -> some View {
        containerValue(\.settingsSearchRole, .item(id))
    }
}

struct SettingsSearchList<Content: View>: View {
    let screen: SettingsSearchScreen
    @Binding var search: SettingsSearch
    @ViewBuilder let content: Content
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if search.isActive {
                Group(sections: content) { sections in
                    let visibleSections = sections.filter { $0.content.contains(where: isVisible) }
                    let hasResults = visibleSections.contains { section in
                        section.content.contains { isVisible($0) && isResult($0) }
                    }
                    List {
                        ForEach(visibleSections) { section in
                            Section {
                                ForEach(section.content.filter(isVisible)) { row in
                                    row.moveDisabled(true)
                                }
                            } header: {
                                section.header
                            } footer: {
                                section.footer
                            }
                        }
                    }
                    .overlay {
                        if !hasResults { ContentUnavailableView.search(text: search.normalizedQuery) }
                    }
                }
            } else {
                List { content }
            }
        }
        .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
    }

    private func isVisible(_ row: Subview) -> Bool {
        switch row.containerValues.settingsSearchRole {
        case .item(let id):
            guard let item = SettingsSearchCatalog.items(for: screen).first(where: { $0.id == id }) else { return false }
            return search.matches(item, screen: screen, locale: locale)
        case .result, .notice: return true
        case nil: return false
        }
    }

    private func isResult(_ row: Subview) -> Bool {
        if case .notice = row.containerValues.settingsSearchRole { return false }
        return true
    }
}

struct SettingsSearchResults<Destination: View>: View {
    let results: [SettingsSearchResult]
    @ViewBuilder let destination: (SettingsSearchResult) -> Destination
    @Environment(\.locale) private var locale

    var body: some View {
        ForEach(results) { result in
            NavigationLink {
                destination(result)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SettingsSearchItem.localized(result.item.title, locale: locale))
                    Text([result.screen.title, result.item.section]
                        .filter { !$0.isEmpty }
                        .map { SettingsSearchItem.localized($0, locale: locale) }
                        .joined(separator: " › "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .containerValue(\.settingsSearchRole, .result)
        }
    }
}
