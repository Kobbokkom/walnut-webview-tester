import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AgentConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    let session: AgentSession
    let start: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Connect a Mac agent to this Walnut window for web development. Diagnostics and approved data go to the connected Mac and may be shared with its AI service.")
                    Text("The connected agent can navigate and reload test pages using your log retention settings. Walnut stops the connection when you turn it off or leave the app.")
                }
                Section {
                    if session.isRunning {
                        if session.isConnected {
                            Label("Mac connected", systemImage: "checkmark.circle")
                        } else if let code = session.pairingCode {
                            Button("Copy pairing code") {
                                UIPasteboard.general.setItems(
                                    [[UTType.plainText.identifier: code]],
                                    options: [.expirationDate: Date().addingTimeInterval(120)]
                                )
                            }
                            Text("On the Mac, run walnut-agent pair and paste the code. Keep the code private.")
                        } else if session.connectionError == nil {
                            ProgressView("Starting connection")
                        }
                        Button("Stop connection", role: .destructive) { session.stop() }
                    } else {
                        Button("Start connection", action: start)
                    }
                    if let error = session.connectionError {
                        Text(error)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Mac Agent")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var agentBrowserSettings: AgentBrowserSettings?
}

private struct AgentApprovalView: View {
    let request: AgentApprovalGate.Request
    let resolve: (Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: request.message).textSelection(.enabled)
                    if let preview = request.preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 420)
                            .accessibilityLabel("Screenshot preview")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Allow Mac Agent action?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Deny") { resolve(false) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Allow") { resolve(true) }
                }
            }
        }
    }
}

struct AgentApprovalPresenter: UIViewControllerRepresentable {
    let request: AgentApprovalGate.Request?
    let resolve: (UUID, Bool) -> Void

    func makeUIViewController(context: Context) -> Presenter { Presenter() }

    func updateUIViewController(_ controller: Presenter, context: Context) {
        controller.update(request: request, resolve: resolve)
    }

    final class Presenter: UIViewController {
        private var request: AgentApprovalGate.Request?
        private var resolve: ((UUID, Bool) -> Void)?
        private var presentedApproval: (id: UUID, controller: UIViewController)?
        private var transitioning = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            reconcile()
        }

        func update(request: AgentApprovalGate.Request?, resolve: @escaping (UUID, Bool) -> Void) {
            self.request = request
            self.resolve = resolve
            reconcile()
        }

        private func reconcile() {
            guard !transitioning else { return }
            if let presentedApproval {
                if presentedApproval.id != request?.id { dismiss(presentedApproval.controller) }
                return
            }
            guard let request, var host = view.window?.rootViewController else { return }
            while let presented = host.presentedViewController { host = presented }

            transitioning = true
            if let coordinator = host.transitionCoordinator,
               coordinator.animate(alongsideTransition: nil, completion: { [weak self] _ in
                   self?.finishTransition()
               }) { return }

            let id = request.id
            let approval = UIHostingController(rootView: AgentApprovalView(request: request) { [weak self] allow in
                self?.choose(id, allow: allow)
            })
            approval.modalPresentationStyle = .formSheet
            approval.isModalInPresentation = true
            presentedApproval = (request.id, approval)
            host.present(approval, animated: true) { [weak self] in self?.finishTransition() }
            if approval.presentingViewController == nil {
                presentedApproval = nil
                self.request = nil
                resolve?(request.id, false)
                finishTransition()
            }
        }

        private func choose(_ id: UUID, allow: Bool) {
            guard !transitioning, let presentedApproval, presentedApproval.id == id, request?.id == id else { return }
            // Wait for UIKit to remove the approval sheet before the action captures the app window.
            dismiss(presentedApproval.controller) { [weak self] in
                guard let self, self.request?.id == id else { return }
                self.request = nil
                self.resolve?(id, allow)
            }
        }

        private func dismiss(_ controller: UIViewController, completion: (() -> Void)? = nil) {
            transitioning = true
            let finish = { [weak self] in
                self?.presentedApproval = nil
                completion?()
                self?.finishTransition()
            }
            if controller.presentingViewController != nil {
                controller.dismiss(animated: true, completion: finish)
            } else {
                finish()
            }
        }

        private func finishTransition() {
            transitioning = false
            reconcile()
        }
    }
}
