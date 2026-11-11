import SwiftUI

struct AgentLogSettings {
    // nil inherits the user’s log setting.
    // swiftlint:disable:next discouraged_optional_boolean
    var consoleRegex: Bool?
    var consoleTypes: Set<ConsoleLog.LogType>?
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

    @MainActor
    static func consoleTypeBinding(
        _ nativeTypes: Binding<Set<ConsoleLog.LogType>>, navigator: WebViewNavigator?, group: ConsoleLog.LogType
    ) -> Binding<Bool> {
        let related = Set(group.relatedTypes)
        return Binding(
            get: { related.isSubset(of: navigator?.agentLogSettings.consoleTypes ?? nativeTypes.wrappedValue) },
            set: { enabled in
                if enabled {
                    nativeTypes.wrappedValue.formUnion(related)
                    navigator?.agentLogSettings.consoleTypes?.formUnion(related)
                } else {
                    nativeTypes.wrappedValue.subtract(related)
                    navigator?.agentLogSettings.consoleTypes?.subtract(related)
                }
            }
        )
    }
}
