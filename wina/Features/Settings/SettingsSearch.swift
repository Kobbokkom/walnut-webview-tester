import Foundation

enum SettingsSearchScreen: String, CaseIterable {
    case settings, loaded, safari, app, menu, live, configuration, emulation, permissions
    case safariMenu, safariConfiguration

    var title: String {
        switch self {
        case .settings, .loaded: "Settings"
        case .safari: "SafariVC Settings"
        case .app: "App Settings"
        case .menu, .safariMenu: "Menu"
        case .live: "Live Settings"
        case .configuration, .safariConfiguration: "Configuration"
        case .emulation: "Emulation"
        case .permissions: "Permissions"
        }
    }

    var children: [Self] {
        switch self {
        case .settings: [.app]
        case .loaded: [.app, .menu, .live, .configuration, .emulation, .permissions]
        case .safari: [.app, .safariMenu, .safariConfiguration]
        default: []
        }
    }
}

struct SettingsSearchItem: Identifiable, Hashable {
    let id: String
    let title: String
    let section: String
    let details: String
    let keywords: [String]

    init(_ id: String, _ title: String, _ section: String, _ details: String = "", keywords: [String] = []) {
        self.id = id
        self.title = title
        self.section = section
        self.details = details
        self.keywords = keywords
    }

    static func localized(_ key: String, locale: Locale) -> String {
        let language = Bundle.preferredLocalizations(
            from: Bundle.main.localizations, forPreferences: [locale.identifier]
        ).first
        guard let language,
              let url = Bundle.main.url(forResource: language, withExtension: "lproj"),
              let bundle = Bundle(url: url) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    func matches(_ query: String, screen: SettingsSearchScreen, locale: Locale) -> Bool {
        ([title, section, details, screen.title] + keywords).contains { key in
            key.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil ||
            Self.localized(key, locale: locale).range(
                of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: locale
            ) != nil
        }
    }
}

struct SettingsSearch {
    var query = "" {
        didSet {
            if query != oldValue { selectedID = nil }
        }
    }
    private(set) var selectedID: String?

    init(item: SettingsSearchItem? = nil, locale: Locale = .current) {
        query = item.map { SettingsSearchItem.localized($0.title, locale: locale) } ?? ""
        selectedID = item?.id
    }

    var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isActive: Bool { !normalizedQuery.isEmpty }

    func matches(_ item: SettingsSearchItem, screen: SettingsSearchScreen, locale: Locale) -> Bool {
        guard isActive else { return true }
        if let selectedID { return item.id == selectedID }
        return item.matches(normalizedQuery, screen: screen, locale: locale)
    }

    func results(in root: SettingsSearchScreen, locale: Locale) -> [SettingsSearchResult] {
        guard isActive else { return [] }
        return root.children.flatMap { screen in
            SettingsSearchCatalog.items(for: screen)
                .filter { $0.matches(normalizedQuery, screen: screen, locale: locale) }
                .map { SettingsSearchResult(screen: screen, item: $0) }
        }
    }
}

struct SettingsSearchResult: Identifiable {
    let screen: SettingsSearchScreen
    let item: SettingsSearchItem
    var id: String { screen.rawValue + "." + item.id }
}
