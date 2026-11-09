import Foundation
import Network

final class BridgeExchange: @unchecked Sendable {
    // All mutable state stays on the connection's callback queue.
    private struct Request {
        let id = UUID()
        let payload: Data
        let continuation: CheckedContinuation<Data, Error>
    }

    private static let responseLimit = 16 * 1024 * 1024
    private let queue = DispatchQueue(label: "walnut-agent.exchange")
    private let connection: NWConnection
    private var started = false
    private var ready = false
    private var closed = false
    private var request: Request?
    private var response = Data()

    init(to endpoint: NWEndpoint, using parameters: NWParameters) {
        connection = NWConnection(to: endpoint, using: parameters)
    }

    deinit { connection.cancel() }

    func run(_ payload: Data, timeout: TimeInterval) async throws -> Data {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    guard !closed, request == nil else {
                        continuation.resume(throwing: AgentError("The Walnut connection closed. Retry to connect again."))
                        return
                    }
                    let pending = Request(payload: payload, continuation: continuation)
                    request = pending
                    queue.asyncAfter(deadline: .now() + timeout) { [weak self, id = pending.id] in
                        guard let self, request?.id == id else { return }
                        fail(AgentError("Walnut connection timed out. Keep Walnut open and check the connection."))
                    }
                    if ready { send() }
                    if !started { start() }
                }
            }
        } onCancel: { [self] in
            queue.async { [self] in fail(CancellationError()) }
        }
    }

    private func start() {
        started = true
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !closed else { return }
            switch state {
            case .ready where !ready:
                ready = true
                receive()
                send()
            case .failed(let error),
                 .waiting(let error) where !ready:
                fail(error)
            case .cancelled:
                fail(AgentError("The Walnut connection closed."))
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func send() {
        guard let request else { return }
        connection.send(content: request.payload, completion: .contentProcessed { [weak self] error in
            if let error { self?.fail(error) }
        })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, complete, error in
            guard let self, !closed else { return }
            if let chunk, !chunk.isEmpty {
                guard let request else {
                    fail(AgentError("Walnut sent an unexpected response."))
                    return
                }
                let newline = chunk.firstIndex(of: 0x0A)
                let prefix = chunk.prefix(upTo: newline ?? chunk.endIndex)
                guard response.count + prefix.count <= Self.responseLimit else {
                    fail(AgentError("The Walnut response exceeds 16 MiB."))
                    return
                }
                response.append(prefix)
                if let newline {
                    guard chunk.index(after: newline) == chunk.endIndex else {
                        fail(AgentError("Walnut sent an unexpected response."))
                        return
                    }
                    let data = response
                    self.request = nil
                    response = Data()
                    request.continuation.resume(returning: data)
                }
            }
            if let error {
                fail(error)
            } else if complete {
                fail(AgentError("Walnut disconnected. Retry to connect again."))
            } else {
                receive()
            }
        }
    }

    private func fail(_ error: Error) {
        guard !closed else { return }
        closed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        request?.continuation.resume(throwing: error)
        request = nil
        response = Data()
    }
}
