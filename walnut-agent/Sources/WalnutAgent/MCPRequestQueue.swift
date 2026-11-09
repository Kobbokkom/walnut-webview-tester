import CoreFoundation
import Foundation

enum MCPRequestID: Hashable {
    case text(String)
    case number(NSNumber)

    init?(_ value: Any?) {
        if let text = value as? String {
            self = .text(text)
        } else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            self = .number(number)
        } else {
            return nil
        }
    }
}

actor MCPRequestQueue {
    private struct Work {
        let id: MCPRequestID?
        let isToolCall: Bool
        let task: Task<Void, Error>
    }

    private let operation: @Sendable (Data) async throws -> Void
    private var tail: Task<Void, Error>?
    private var pending: [UUID: Work] = [:]

    init(operation: @escaping @Sendable (Data) async throws -> Void) {
        self.operation = operation
    }

    func receive(_ data: Data) {
        let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let method = message?["method"] as? String
        if message?["jsonrpc"] as? String == "2.0", message?["id"] == nil,
           method == "notifications/cancelled" {
            let params = message?["params"] as? [String: Any]
            if let id = MCPRequestID(params?["requestId"]) {
                for work in pending.values where work.id == id { work.task.cancel() }
            }
            return
        }

        let previous = tail
        let id = MCPRequestID(message?["id"])
        let token = UUID()
        let task = Task {
            defer { pending.removeValue(forKey: token) }
            try await previous?.value
            if !Task.isCancelled { try await operation(data) }
        }
        tail = task
        pending[token] = Work(id: id, isToolCall: method == "tools/call", task: task)
    }

    func finish() async throws {
        for work in pending.values where work.isToolCall { work.task.cancel() }
        try await tail?.value
    }
}
