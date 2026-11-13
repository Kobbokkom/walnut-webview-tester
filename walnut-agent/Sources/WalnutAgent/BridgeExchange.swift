import Foundation
import Network

final class BridgeExchange: @unchecked Sendable {
    // All mutable state stays on the connection's callback queue.
    private struct Request {
        let id = UUID()
        let payload: Data
        let continuation: CheckedContinuation<Data, Error>
    }

    private let queue = DispatchQueue(label: "walnut-agent.exchange")
    private let connection: NWConnection
    private let responseLimit: Int
    private var started = false
    private var ready = false
    private var closed = false
    private var request: Request?
    private var response = Data()
    private var closing: CheckedContinuation<Void, Never>?

    init(to endpoint: NWEndpoint, using parameters: NWParameters, responseLimit: Int = 16 * 1024 * 1024) {
        connection = NWConnection(to: endpoint, using: parameters)
        self.responseLimit = responseLimit
    }

    deinit { connection.cancel() }

    func close() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard ready, !closed, closing == nil else {
                    continuation.resume()
                    return
                }
                closing = continuation
                let finish = AgentError("The Walnut connection closed.")
                // An empty NDJSON frame asks the phone to release its peer before the process exits.
                connection.send(content: Data([0x0A]), completion: .contentProcessed { [weak self] error in
                    if let error { self?.fail(error) }
                })
                queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.fail(finish) }
            }
        }
    }

    func run(_ payload: Data, timeout: TimeInterval) async throws -> Data {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    guard !closed, closing == nil, request == nil else {
                        continuation.resume(throwing: AgentError("The Walnut connection closed. Retry to connect again."))
                        return
                    }
                    let pending = Request(payload: payload, continuation: continuation)
                    request = pending
                    queue.asyncAfter(deadline: .now() + timeout) { [weak self, id = pending.id] in
                        guard let self, request?.id == id else { return }
                        fail(connectionError(timeoutError()))
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
                fail(connectionError(error))
            case .cancelled:
                fail(AgentError("The Walnut connection closed."))
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func connectionError(_ error: Error) -> Error {
        // DNS-SD's kDNSServiceErr_PolicyDenied also covers Bonjour resolution blocked before TCP.
        if (error as? NWError) == .dns(-65570) || connection.currentPath?.unsatisfiedReason == .localNetworkDenied {
            return AgentError("Allow Walnut Agent or its host app in Mac System Settings → Privacy & Security → Local Network, then retry.")
        }
        return error
    }

    private func timeoutError() -> AgentError {
        let message = "Walnut connection timed out. Keep Walnut open and check the connection."
        if case .service = connection.endpoint {
            // macOS can wait for Bonjour permission without reporting a denied path.
            return AgentError(message + " If prompted on the Mac, allow Local Network access and retry.")
        }
        return AgentError(message)
    }

    private func send() {
        guard let request else { return }
        connection.send(content: request.payload, completion: .contentProcessed { [weak self] error in
            if let error { self?.fail(error) }
        })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: min(responseLimit + 1, 64 * 1024)) { [weak self] chunk, _, complete, error in
            guard let self, !closed else { return }
            if let chunk, !chunk.isEmpty {
                guard let request else {
                    fail(AgentError("Walnut sent an unexpected response."))
                    return
                }
                let newline = chunk.firstIndex(of: 0x0A)
                let prefix = chunk.prefix(upTo: newline ?? chunk.endIndex)
                guard response.count + prefix.count <= responseLimit else {
                    fail(AgentError("The Walnut response exceeds the \(responseLimit)-byte limit."))
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
        closing?.resume()
        closing = nil
    }
}
