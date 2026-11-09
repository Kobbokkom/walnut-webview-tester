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
    let message: String
    let resolve: (Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(verbatim: message)
                    .textSelection(.enabled)
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
    let message: String?
    let resolve: (Bool) -> Void

    func makeUIViewController(context: Context) -> Presenter { Presenter() }

    func updateUIViewController(_ controller: Presenter, context: Context) {
        controller.update(message: message, resolve: resolve)
    }

    final class Presenter: UIViewController {
        private weak var approvalController: UIViewController?

        func update(message: String?, resolve: @escaping (Bool) -> Void) {
            guard let message else {
                approvalController?.dismiss(animated: true)
                approvalController = nil
                return
            }
            guard approvalController == nil, var host = view.window?.rootViewController else { return }
            while let presented = host.presentedViewController { host = presented }
            let approval = UIHostingController(rootView: AgentApprovalView(message: message, resolve: resolve))
            approval.modalPresentationStyle = .formSheet
            approval.isModalInPresentation = true
            approvalController = approval
            host.present(approval, animated: true)
        }
    }
}
