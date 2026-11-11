import CoreFoundation
import Foundation

extension AgentSettings {
    static let menuTools = [
        AgentTool.definition("menus", "Inspect or set Walnut's WKWebView toolbar and App Bar layout. Apply accepts items or visibleOrder. Reset discards the session override. Set persist to restore the saved layout to Walnut defaults.", [
            "menu": choices(AgentMenu.allCases.map(\.rawValue)),
            "action": choices(["get", "apply", "reset"]),
            "visibleOrder": ["type": "array", "items": ["type": "string"], "uniqueItems": true],
            "items": [
                "type": "array",
                "description": "Ordered rows with explicit visibility. Unlisted items are placed at the end and hidden.",
                "items": [
                    "type": "object", "required": ["menuItem", "isVisible"], "additionalProperties": false,
                    "properties": ["menuItem": ["type": "string"], "isVisible": ["type": "boolean"]]
                ]
            ],
            "persist": ["type": "boolean", "default": false],
        ], required: ["menu", "action"]),
    ]

    static func menus(_ input: AgentSettingsInput) async throws -> Any {
        guard let menu = AgentMenu(rawValue: try input.string("menu")) else {
            throw AgentError("Walnut menu layout settings apply to WKWebView. Choose wk_toolbar or wk_app_bar.")
        }
        let settings = AgentBrowserSettings.shared
        switch try input.string("action") {
        case "get": break
        case "apply":
            let rows = try menu.rowsForApply(input.arguments)
            let persist = try input.flag("persist")
            if persist { try await input.confirm("Save the \(menu.rawValue) layout in Walnut?") }
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
        let available = menu.items
        let decoded = try? JSONDecoder().decode([AgentMenu.Row].self, from: data)
        let rows = decoded.flatMap { rows in
            !rows.isEmpty && rows.allSatisfy { available.contains($0.menuItem) } ? rows : nil
        } ?? available.map { AgentMenu.Row(menuItem: $0, isVisible: true) }
        return [
            "menu": menu.rawValue, "availableItems": available, "visibleOrder": rows.filter(\.isVisible).map(\.menuItem),
            "items": try AgentTool.json(rows)
        ]
    }
}

private enum AgentMenu: String, CaseIterable {
    case wkToolbar = "wk_toolbar"
    case wkAppBar = "wk_app_bar"

    struct Row: Codable {
        let menuItem: String
        let isVisible: Bool
    }

    var key: String {
        switch self {
        case .wkToolbar: "toolbarItemsOrder"
        case .wkAppBar: "appBarItemsOrder"
        }
    }

    var items: [String] {
        switch self {
        case .wkToolbar: DevToolsMenuItem.defaultOrder.map(\.rawValue)
        case .wkAppBar: AppBarMenuItem.defaultOrder.map(\.rawValue)
        }
    }

    func rowsForApply(_ arguments: [String: Any]) throws -> [Row] {
        let invalid = AgentError("Provide unique menu item identifiers in either items or visibleOrder.")
        let available = items
        let rows: [Row]
        if let raw = arguments["items"] as? [[String: Any]], arguments["visibleOrder"] == nil, raw.count <= available.count {
            rows = try raw.map { row in
                guard row.count == 2, let item = row["menuItem"] as? String,
                      let visible = row["isVisible"] as? NSNumber, CFGetTypeID(visible) == CFBooleanGetTypeID() else { throw invalid }
                return Row(menuItem: item, isVisible: visible.boolValue)
            }
        } else if let visible = arguments["visibleOrder"] as? [String], arguments["items"] == nil, visible.count <= available.count {
            rows = visible.map { Row(menuItem: $0, isVisible: true) }
        } else {
            throw invalid
        }
        let supplied = Set(rows.map(\.menuItem))
        guard supplied.count == rows.count, supplied.isSubset(of: available) else { throw invalid }
        return rows + available.filter { !supplied.contains($0) }.map { Row(menuItem: $0, isVisible: false) }
    }
}
