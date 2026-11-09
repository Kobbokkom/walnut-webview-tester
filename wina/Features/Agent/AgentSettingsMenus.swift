import Foundation

extension AgentSettings {
    static let menuTools = [
        AgentTool.definition("menus", "Inspect, reorder, hide, or restore the WKWebView and SafariVC toolbar and App Bar items. Omitted items in visibleOrder are hidden.", [
            "menu": choices(AgentMenu.allCases.map(\.rawValue)),
            "action": choices(["get", "apply", "reset"]),
            "visibleOrder": ["type": "array", "items": ["type": "string"], "uniqueItems": true],
            "persist": ["type": "boolean", "default": false],
        ], required: ["menu", "action"]),
    ]

    static func menus(_ input: AgentSettingsInput) async throws -> Any {
        guard let menu = AgentMenu(rawValue: try input.string("menu")) else { throw AgentError("Unknown menu.") }
        let settings = AgentBrowserSettings.shared
        switch try input.string("action") {
        case "get": break
        case "apply":
            let allowed = menu.items
            guard let order = input.arguments["visibleOrder"] as? [String], Set(order).count == order.count,
                  order.allSatisfy(allowed.contains) else { throw AgentError("Provide an ordered list of unique menu item identifiers.") }
            let persist = try input.flag("persist")
            if persist { try await input.confirm("Save the \(menu.rawValue) layout in Walnut?") }
            let rows = order.map { AgentMenu.Row(menuItem: $0, isVisible: true) } +
                allowed.filter { !order.contains($0) }.map { AgentMenu.Row(menuItem: $0, isVisible: false) }
            let data = try JSONEncoder().encode(rows)
            settings.apply([menu.key: data], persist: persist)
        case "reset":
            let persist = try input.flag("persist")
            if persist {
                try await input.confirm("Restore Walnut's default \(menu.rawValue) layout?")
                UserDefaults.standard.removeObject(forKey: menu.key)
            }
            settings.reset(keys: [menu.key])
        default: throw AgentError("Unknown menu action.")
        }
        let saved = UserDefaults.standard.data(forKey: menu.key) ?? Data()
        let data = settings.value(menu.key, fallback: saved)
        let rows = (try? JSONDecoder().decode([AgentMenu.Row].self, from: data)).flatMap { $0.isEmpty ? nil : $0 }
        return ["menu": menu.rawValue, "availableItems": menu.items, "visibleOrder": rows?.filter(\.isVisible).map(\.menuItem) ?? menu.items]
    }
}

private enum AgentMenu: String, CaseIterable {
    case wkToolbar = "wk_toolbar"
    case wkAppBar = "wk_app_bar"
    case safariToolbar = "safari_toolbar"
    case safariAppBar = "safari_app_bar"

    struct Row: Codable {
        let menuItem: String
        let isVisible: Bool
    }

    var key: String {
        switch self {
        case .wkToolbar: "toolbarItemsOrder"
        case .wkAppBar: "appBarItemsOrder"
        case .safariToolbar: "safariToolbarItemsOrder"
        case .safariAppBar: "safariAppBarItemsOrder"
        }
    }

    var items: [String] {
        switch self {
        case .wkToolbar: DevToolsMenuItem.defaultOrder.map(\.rawValue)
        case .wkAppBar: AppBarMenuItem.defaultOrder.map(\.rawValue)
        case .safariToolbar: SafariVCToolbarMenuItem.defaultOrder.map(\.rawValue)
        case .safariAppBar: SafariVCAppBarMenuItem.defaultOrder.map(\.rawValue)
        }
    }
}
