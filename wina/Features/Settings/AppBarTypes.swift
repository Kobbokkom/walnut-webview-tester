//
//  AppBarTypes.swift
//  wina
//
//  Created by Claude on 12/23/25.
//

import SwiftUI

// MARK: - AppBar Menu Item

enum AppBarMenuItem: String, CaseIterable, Identifiable {
    case home
    case initialURL
    case back
    case forward
    case refresh

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .initialURL: return "flag"
        case .back: return "chevron.left"
        case .forward: return "chevron.right"
        case .refresh: return "arrow.clockwise"
        }
    }

    var label: LocalizedStringKey { LocalizedStringKey(titleKey.key) }

    var description: LocalizedStringKey { LocalizedStringKey(descriptionKey.key) }

    var titleKey: LocalizedStringResource {
        switch self {
        case .home: return "Home"
        case .initialURL: return "Initial URL"
        case .back: return "Back"
        case .forward: return "Forward"
        case .refresh: return "Refresh"
        }
    }

    var descriptionKey: LocalizedStringResource {
        switch self {
        case .home: return "Return to home screen"
        case .initialURL: return "Go to first loaded URL"
        case .back: return "Navigate to previous page"
        case .forward: return "Navigate to next page"
        case .refresh: return "Reload current page"
        }
    }

    /// Default order of all items
    static var defaultOrder: [AppBarMenuItem] {
        allCases
    }
}

// MARK: - AppBar Item State

struct AppBarItemState: Identifiable, Codable, Equatable {
    var id: String { menuItem.rawValue }
    let menuItem: AppBarMenuItem
    var isVisible: Bool

    enum CodingKeys: String, CodingKey {
        case menuItem
        case isVisible
    }

    init(menuItem: AppBarMenuItem, isVisible: Bool) {
        self.menuItem = menuItem
        self.isVisible = isVisible
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(String.self, forKey: .menuItem)
        guard let item = AppBarMenuItem(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: .menuItem,
                in: container,
                debugDescription: "Unknown menu item: \(rawValue)"
            )
        }
        self.menuItem = item
        self.isVisible = try container.decode(Bool.self, forKey: .isVisible)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(menuItem.rawValue, forKey: .menuItem)
        try container.encode(isVisible, forKey: .isVisible)
    }
}

// MARK: - Helper for Reading AppBar Settings

struct AppBarSettings {
    static func getVisibleItems() -> [AppBarMenuItem] {
        guard let data = UserDefaults.standard.data(forKey: "appBarItemsOrder"),
              let items = try? JSONDecoder().decode([AppBarItemState].self, from: data) else {
            // Default: all items visible
            return AppBarMenuItem.defaultOrder
        }

        return items.filter { $0.isVisible }.map { $0.menuItem }
    }
}
