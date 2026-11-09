import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class AgentApprovalGate {
    struct Request {
        let id = UUID()
        let message: String
        let preview: UIImage?
    }

    private(set) var pending: Request?
    @ObservationIgnored private var continuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var timeout: Task<Void, Never>?

    func authorize(_ message: String, preview: UIImage? = nil) async -> Bool {
        guard pending == nil, !Task.isCancelled else { return false }
        let request = Request(message: message, preview: preview)
        let id = request.id
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                self.continuation = continuation
                pending = request
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(45)) } catch { return }
                    self?.resolve(id, allow: false)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.resolve(id, allow: false) }
        }
    }

    func resolve(_ id: UUID, allow: Bool) {
        guard pending?.id == id else { return }
        timeout?.cancel()
        timeout = nil
        pending = nil
        let waiting = continuation
        continuation = nil
        waiting?.resume(returning: allow)
    }
}
