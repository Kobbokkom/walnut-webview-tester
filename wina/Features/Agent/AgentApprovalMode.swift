import SwiftUI

/// What an approval prompt protects. Call sites declare it next to the prompt text.
enum ApprovalScope {
    /// Reads or interacts with the open page only.
    case page
    /// Shares data beyond the open page, deletes data, captures the screen, or changes settings.
    case sensitive
}

/// How much the connected Mac agent may do without an on-device approval.
enum AgentApprovalMode: String, CaseIterable {
    case ask, pageActions, all

    static let defaultsKey = "macAgentApprovalMode"

    static var current: AgentApprovalMode {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(AgentApprovalMode.init) ?? .ask
    }

    var title: LocalizedStringKey {
        switch self {
        case .ask: "Ask every time"
        case .pageActions: "Allow page actions"
        case .all: "Allow everything"
        }
    }

    var summary: Text {
        switch self {
        case .ask:
            Text("Walnut asks on iPhone before each action.")
        case .pageActions:
            Text("Reading, interacting with and running scripts on the open page run without asking. Screenshots, recordings, data deletion and settings changes still ask.")
        case .all:
            Text("Every action runs without asking, including screenshots and settings changes. Use only with a Mac and agent you trust.")
        }
    }

    func approvesWithoutAsking(_ scope: ApprovalScope) -> Bool {
        switch self {
        case .ask: false
        case .pageActions: scope == .page
        case .all: true
        }
    }
}
