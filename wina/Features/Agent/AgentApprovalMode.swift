import Foundation

/// How much the connected Mac agent may do without an on-device approval.
enum AgentApprovalMode: String, CaseIterable, Identifiable {
    case ask, pageActions, all

    static let defaultsKey = "macAgentApprovalMode"

    static var current: AgentApprovalMode {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(AgentApprovalMode.init) ?? .ask
    }

    var id: String { rawValue }

    /// Tools that only read or act on the open page, so page-level approval covers them.
    private static let pageTools: Set<String> = [
        "walnut_browser", "page_interact", "page_search",
        "console_list", "console_detail", "console_group", "console_evaluate", "console_clear",
        "network_list", "network_detail", "network_clear", "resources_detail",
        "sources_list", "sources_detail", "performance_read", "performance_clear",
        "accessibility_audit", "accessibility_detail", "accessibility_clear",
        "storage_list", "snippets_run"
    ]

    func approvesWithoutAsking(tool: String, arguments: [String: Any]) -> Bool {
        switch self {
        case .ask: return false
        case .all: return true
        case .pageActions:
            // Clearing website data is destructive even though it arrives through the browser tool.
            if tool == "walnut_browser", arguments["cleanStart"] as? Bool == true { return false }
            return Self.pageTools.contains(tool)
        }
    }
}
