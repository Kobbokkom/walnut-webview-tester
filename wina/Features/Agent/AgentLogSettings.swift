import SwiftUI

struct AgentLogSettings {
    // nil inherits the user’s saved log setting.
    // swiftlint:disable:next discouraged_optional_boolean
    var consolePreserveLog: Bool?
    // swiftlint:disable:next discouraged_optional_boolean
    var networkPreserveLog: Bool?
    var consoleClearStrategy: LogClearStrategy?
    var networkClearStrategy: LogClearStrategy?

    @MainActor
    static func binding<Value>(
        _ saved: Binding<Value>,
        navigator: WebViewNavigator?,
        override: WritableKeyPath<Self, Value?>
    ) -> Binding<Value> {
        Binding(
            get: { navigator?.agentLogSettings[keyPath: override] ?? saved.wrappedValue },
            set: { value in
                saved.wrappedValue = value
                navigator?.agentLogSettings[keyPath: override] = nil
            }
        )
    }
}
