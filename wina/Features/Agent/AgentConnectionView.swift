import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AgentConnectionView: View {
    private enum StepState { case done, current, upcoming }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AgentSession.autoConnectKey) private var autoConnect = false
    @AppStorage(AgentApprovalMode.defaultsKey) private var approvalMode = AgentApprovalMode.ask
    @AppStorage("macAgentInstallConfirmed") private var installConfirmed = false
    @State private var copyFeedback = CopiedFeedbackState()
    @State private var showOtherPairing = false
    @State private var reopenedSteps: Set<Int> = []
    @AccessibilityFocusState private var focusPairAgain: Bool
    @State private var pairingFile: AgentPairingFile?
    @State private var pairingShareFailed = false
    @State private var confirmForgetMac = false
    let session: AgentSession
    let start: (_ rememberedOnly: Bool) -> Void

    static let installCommandLines = ["brew tap kobbokkom/tap", "brew install --cask kobbokkom/tap/walnut-agent"]
    static let installCommands = installCommandLines.joined(separator: "\n")
    private static let setupGuide = URL(string: "https://github.com/Kobbokkom/walnut-webview-tester/tree/walnut-agent-v0.1.5/walnut-agent#install-on-mac")!

    private var isPaired: Bool { session.hasPairingGrant }

    var body: some View {
        @Bindable var feedback = copyFeedback
        let state = session.state
        NavigationStack {
            Form {
                stepsSection(state)
                approvalSection
                if session.hasRememberedMac || session.pairingStorageError != nil { pairedMacSection }
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: state)
            .navigationTitle("Mac Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .copiedFeedbackOverlay($feedback.message)
        .sheet(item: $pairingFile) { file in
            ShareSheet(fileURL: file.url)
                .onDisappear { file.remove() }
        }
        .alert("Could not prepare pairing file", isPresented: $pairingShareFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Copy the pairing token instead, or try again.")
        }
        .alert("Forget this Mac?", isPresented: $confirmForgetMac) {
            Button("Forget Mac", role: .destructive) { session.forgetRememberedMac() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Walnut removes the saved pairing. Pair again to use this Mac.")
        }
        .onAppear { session.refreshRememberedMac() }
        .onChange(of: session.pairingCode) { _, _ in
            showOtherPairing = false
            clearPairingFile()
        }
        .onChange(of: state) { _, state in
            if state == .connected {
                showOtherPairing = false
                clearPairingFile()
            }
            if state == .pairingEnded { focusPairAgain = true }
            announce(state)
        }
    }

    // MARK: - Status

    private func statusLine(_ state: AgentConnectionState) -> some View {
        HStack(spacing: 6) {
            if state == .starting {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(state.dotColor).frame(width: 8, height: 8)
            }
            state.title
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func announce(_ state: AgentConnectionState) {
        let message: String? = switch state {
        case .waitingToPair: String.app("Ready to pair")
        case .pairingEnded: String.app("Pairing ended")
        case .waitingForMac: String.app("Mac paired. Waiting for your Mac.")
        case .connected: String.app("Mac connected")
        case .failed(let error): error
        case .off, .starting: nil
        }
        if let message { UIAccessibility.post(notification: .announcement, argument: message) }
    }

    // MARK: - Steps

    private var installDone: Bool { installConfirmed || isPaired }
    private var turnOnHint: LocalizedStringKey? { installDone && !session.isRunning ? "Turn on Mac Agent first." : nil }

    private var agentSwitch: some View {
        Toggle("Mac Agent", isOn: Binding(get: { session.isRunning }, set: { on in
            if on {
                start(false)
                // Remember the switch only when the connection actually started.
                autoConnect = session.isRunning
            } else {
                session.stopManually()
            }
        }))
        .labelsHidden()
        .tint(.accentColor)
    }

    private func stepsSection(_ state: AgentConnectionState) -> some View {
        let switchState: StepState = session.isRunning ? .done : (installDone ? .current : .upcoming)
        let pairState: StepState = isPaired ? .done : (session.isRunning ? .current : .upcoming)
        let sessionState: StepState = state == .connected ? .done : (isPaired && session.isRunning ? .current : .upcoming)
        return Section {
            step(1, "Install Walnut Agent on your Mac", state: installDone ? .done : .current) {
                Text("Run these once in Terminal on your Mac. Requires Homebrew.")
                ForEach(Self.installCommandLines, id: \.self) { line in
                    commandRow(line, name: line.contains("--cask") ? "Copy install command" : "Copy tap command")
                }
                ShareLink(item: Self.setupGuide) {
                    Label("Share Mac setup guide", systemImage: "square.and.arrow.up")
                }
                if !installDone {
                    Button("I've installed it") { installConfirmed = true }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 2)
                }
            }
            step(2, "Turn on Mac Agent", state: switchState, collapsible: false, forceOpen: true) {
                if state != .off { statusLine(state) }
                if switchState != .upcoming {
                    Text("While on, Mac Agent also starts when you open Walnut.")
                        .foregroundStyle(.secondary)
                }
            } trailing: {
                agentSwitch
            }
            step(3, "Pair with your Mac", state: pairState, hint: turnOnHint) {
                pairContent(state)
            }
            step(4, state == .connected ? "Session running" : "Start a session", state: sessionState,
                 hint: isPaired ? turnOnHint : nil, collapsible: false, forceOpen: state == .connected) {
                if state == .connected {
                    Text("Keep Walnut open while your Mac uses it.")
                } else {
                    Text("Run this in Terminal, or ask your coding agent to use Walnut.")
                    commandRow("walnut-agent session", name: "Copy session command")
                }
            }
        } header: {
            Text("How to connect")
        } footer: {
            Text("Keep your iPhone and Mac on the same Wi-Fi network. To connect by USB instead, add --usb to the pair and session commands and run brew install libusbmuxd once on your Mac. Walnut sends diagnostics and data you approve to your Mac, and your coding agent may pass them to its AI service.")
        }
    }

    @ViewBuilder
    private func pairContent(_ state: AgentConnectionState) -> some View {
        if state == .pairingEnded {
            Text("Tap Pair again, then run this on your Mac within 2 minutes.")
            Button("Pair again") { session.startPairing() }
                .buttonStyle(.borderedProminent)
                .accessibilityFocused($focusPairAgain)
            commandRow("walnut-agent pair", name: "Copy pair command")
            if let error = session.pairingError {
                Label { Text(verbatim: error) } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
        } else {
            Text("First time only. Run this in Terminal on your Mac.")
            commandRow("walnut-agent pair", name: "Copy pair command")
            Text("Terminal shows a 6-digit number. If it matches the one on iPhone, tap Pair on iPhone, then type y in Terminal.")
            if let name = session.pairingDeviceName {
                Text("If your Mac lists more than one iPhone, choose \(Text(verbatim: name).font(.subheadline.monospaced()).foregroundStyle(.primary)).")
                    .foregroundStyle(.secondary)
            }
            if let code = session.pairingCode {
                DisclosureGroup("Other ways to pair", isExpanded: $showOtherPairing) {
                    pairingFileOptions(code)
                }
            }
        }
    }

    private func step<Content: View>(
        _ number: Int,
        _ title: LocalizedStringKey,
        state: StepState,
        hint: LocalizedStringKey? = nil,
        collapsible: Bool = true,
        forceOpen: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        step(number, title, state: state, hint: hint, collapsible: collapsible, forceOpen: forceOpen, content: content) {
            EmptyView()
        }
    }

    /// A numbered connection step. Done steps can be reopened when `collapsible`; `forceOpen` always shows the content.
    private func step<Content: View, Trailing: View>(
        _ number: Int,
        _ title: LocalizedStringKey,
        state: StepState,
        hint: LocalizedStringKey? = nil,
        collapsible: Bool = true,
        forceOpen: Bool = false,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let reopened = collapsible && state == .done && reopenedSteps.contains(number)
        let showsContent = forceOpen || state == .current || reopened
        return HStack(alignment: .top, spacing: 12) {
            Group {
                switch state {
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .current: Image(systemName: "\(number).circle.fill").foregroundStyle(Color.accentColor)
                case .upcoming: Image(systemName: "\(number).circle").foregroundStyle(.secondary)
                }
            }
            .font(.title3)
            .frame(minHeight: 31)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .frame(minHeight: 31)
                        .font(state == .current ? .headline : .body)
                        .foregroundStyle(state == .upcoming ? .secondary : .primary)
                        .accessibilityLabel(stepAccessibilityLabel(number, title, state))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    trailing()
                    if collapsible, state == .done {
                        Button(reopened ? "Hide" : "Show") {
                            if reopened { reopenedSteps.remove(number) } else { reopenedSteps.insert(number) }
                        }
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                    }
                }
                if showsContent {
                    content()
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                } else if state == .upcoming, let hint {
                    Text(hint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .padding(.vertical, 4)
    }

    private func stepAccessibilityLabel(_ number: Int, _ title: LocalizedStringKey, _ state: StepState) -> Text {
        let status: Text = switch state {
        case .done: Text("Done")
        case .current: Text("Current step")
        case .upcoming: Text("Not started")
        }
        return Text("Step \(number): ") + Text(title) + Text(verbatim: ", ") + status
    }

    // MARK: - Approvals and paired Mac

    private var approvalSection: some View {
        Section {
            Picker(selection: $approvalMode) {
                ForEach(AgentApprovalMode.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                Label("Approvals", systemImage: approvalMode == .all ? "exclamationmark.shield" : "checkmark.shield")
                    .foregroundStyle(approvalMode == .all ? Color.orange : Color.primary)
            }
            .pickerStyle(.menu)
            .accessibilityHint(approvalMode.summary)
        } footer: {
            approvalMode.summary
        }
    }

    private var pairedMacSection: some View {
        Section {
            Button(role: .destructive) { confirmForgetMac = true } label: {
                Label("Forget Mac", systemImage: "trash")
            }
        } header: {
            Text("Paired Mac")
        } footer: {
            Text("To use a different Mac, forget this one and pair again.")
        }
    }

    // MARK: - Rows

    private func commandRow(_ command: String, name: LocalizedStringKey = "Copy command") -> some View {
        HStack(spacing: 8) {
            Text(verbatim: command)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .leftToRight)
            Button {
                UIPasteboard.general.string = command
                announce("Command copied")
                copyFeedback.show("Command copied")
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(name)
        }
        .padding(.leading, 12)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func pairingFileOptions(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.setItems(
                        [[UTType.plainText.identifier: code]],
                        options: [.expirationDate: Date().addingTimeInterval(120)]
                    )
                    copyFeedback.show("Pairing token copied")
                    announce("Pairing token copied")
                } label: {
                    Label("Copy pairing token", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                Button {
                    do {
                        clearPairingFile()
                        pairingFile = try AgentPairingFile(code: code)
                    } catch {
                        pairingShareFailed = true
                    }
                } label: {
                    Label("Share pairing file", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
            }
            .buttonStyle(.bordered)
            Text("Paste the token after running walnut-agent pair --token, or AirDrop the file to your Mac.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            commandRow("walnut-agent pair --file ")
            Text("The token and file grant access to this session. Share only with your Mac. Stopping the connection or leaving Walnut invalidates them. Delete the received file after pairing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func announce(_ message: String.LocalizationValue) {
        UIAccessibility.post(notification: .announcement, argument: String.app(message))
    }

    private func clearPairingFile() {
        pairingFile?.remove()
        pairingFile = nil
    }
}

private struct AgentPairingDigits: View {
    let code: String

    var body: some View {
        let grouped = "\(code.prefix(3))\u{00A0}\(code.suffix(3))"
        Text(verbatim: grouped)
            .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .accessibilityLabel(code.map(String.init).joined(separator: " "))
            .environment(\.layoutDirection, .leftToRight)
    }
}

extension EnvironmentValues {
    @Entry var agentBrowserSettings: AgentBrowserSettings?
}

private struct AgentApprovalView: View {
    @AccessibilityFocusState private var focusConfirmation: Bool
    let request: AgentApprovalGate.Request
    let resolve: (Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: request.message).textSelection(.enabled)
                    if let confirmation = request.pairingConfirmation {
                        VStack(spacing: 4) {
                            Text("Confirmation number").font(.subheadline.weight(.semibold))
                            AgentPairingDigits(code: confirmation)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                        .accessibilityFocused($focusConfirmation)
                    }
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    Button { resolve(true) } label: {
                        Text(request.pairingConfirmation == nil ? LocalizedStringKey("Allow") : LocalizedStringKey("Pair"))
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { resolve(false) } label: {
                        Text(request.pairingConfirmation == nil ? LocalizedStringKey("Deny") : LocalizedStringKey("Cancel"))
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemBackground))
            }
            .navigationTitle(request.pairingConfirmation == nil ? LocalizedStringKey("Allow Mac Agent action?") : LocalizedStringKey("Pair this Mac?"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityAction(.escape) { resolve(false) }
        .onAppear { focusConfirmation = request.pairingConfirmation != nil }
    }
}

struct BrowserSheetPresenter: UIViewControllerRepresentable {
    @Environment(\.locale) private var locale
    let request: () -> AgentApprovalGate.Request?
    let resolve: (UUID, Bool) -> Void
    let showsCallback: () -> Bool
    let dismissCallback: () -> Void
    var onSceneExit: () -> Void = {}
    var onWindowAttached: (UIWindow, Presenter) -> Void = { _, _ in }

    func makeUIViewController(context: Context) -> Presenter { Presenter() }

    func updateUIViewController(_ controller: Presenter, context: Context) {
        controller.update(self)
    }

    static func dismantleUIViewController(_ controller: Presenter, coordinator: ()) {
        controller.detachFromScene()
    }

    final class Presenter: UIViewController, UISheetPresentationControllerDelegate {
        private final class WindowAnchor: UIView {
            var didAttach: ((UIWindow) -> Void)?

            override func didMoveToWindow() {
                super.didMoveToWindow()
                if let window { didAttach?(window) }
            }
        }

        private var request: AgentApprovalGate.Request?
        private var requestProvider: (() -> AgentApprovalGate.Request?)?
        private var resolve: ((UUID, Bool) -> Void)?
        private var showsCallback = false
        private var callbackProvider: (() -> Bool)?
        private var dismissCallback: (() -> Void)?
        private var onSceneExit: (() -> Void)?
        private var onWindowAttached: ((UIWindow, Presenter) -> Void)?
        private var locale = Locale.current
        private weak var sceneWindow: UIWindow?
        private weak var observedScene: UIWindowScene?
        private var approval: (id: UUID, controller: UIViewController)?
        private var callback: UIViewController?
        private var transitioning = false

        override func loadView() {
            let anchor = WindowAnchor()
            anchor.didAttach = { [weak self] window in self?.attach(to: window) }
            view = anchor
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if let window = view.window { attach(to: window) }
            reconcile()
        }

        func update(_ input: BrowserSheetPresenter) {
            let needsObservation = requestProvider == nil
            requestProvider = input.request
            resolve = input.resolve
            callbackProvider = input.showsCallback
            dismissCallback = input.dismissCallback
            onSceneExit = input.onSceneExit
            onWindowAttached = input.onWindowAttached
            locale = input.locale
            // Safari's full-screen presentation temporarily detaches this view from its window.
            if let window = viewIfLoaded?.window { attach(to: window) }
            if needsObservation { observeRequests() } else { reconcile() }
        }

        private func attach(to window: UIWindow) {
            sceneWindow = window
            onWindowAttached?(window, self)
            guard let scene = window.windowScene, scene !== observedScene else { return }
            let notification = UIScene.didEnterBackgroundNotification
            NotificationCenter.default.removeObserver(self, name: notification, object: observedScene)
            NotificationCenter.default.addObserver(self, selector: #selector(sceneDidEnterBackground), name: notification, object: scene)
            observedScene = scene
        }

        @objc private func sceneDidEnterBackground(_: Notification) { onSceneExit?() }

        func detachFromScene() {
            NotificationCenter.default.removeObserver(self, name: UIScene.didEnterBackgroundNotification, object: observedScene)
            requestProvider = nil
            callbackProvider = nil
            let exit = onSceneExit
            onSceneExit = nil
            Task { @MainActor in exit?() }
        }

        private func observeRequests() {
            // UIKit keeps its presentation even while the SwiftUI host stops updating.
            (request, showsCallback) = withObservationTracking {
                (requestProvider?(), callbackProvider?() ?? false)
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in self?.observeRequests() }
            }
            reconcile()
        }

        private func reconcile() {
            guard !transitioning else { return }
            if let approval {
                if approval.controller.presentingViewController != nil {
                    if request?.id != approval.id {
                        dismiss(approval.controller) { [weak self] in self?.approval = nil }
                    }
                    return
                }
                self.approval = nil
                if request?.id == approval.id {
                    request = nil
                    resolve?(approval.id, false)
                }
            }
            if callback?.presentingViewController == nil { callback = nil }
            if let callback, !showsCallback {
                dismiss(callback) { [weak self] in self?.callback = nil }
                return
            }
            guard request != nil || (showsCallback && callback == nil),
                  var host = sceneWindow?.rootViewController else { return }
            while let presented = host.presentedViewController { host = presented }

            transitioning = true
            if let coordinator = host.transitionCoordinator,
               coordinator.animate(alongsideTransition: nil, completion: { [weak self] _ in
                   self?.finishTransition()
               }) { return }

            if let request {
                presentApproval(request, from: host)
            } else {
                presentCallback(from: host)
            }
        }

        private func presentApproval(_ request: AgentApprovalGate.Request, from host: UIViewController) {
            let id = request.id
            let controller = UIHostingController(rootView: AgentApprovalView(request: request) { [weak self] allow in
                self?.choose(id, allow: allow)
            }.environment(\.locale, locale))
            controller.isModalInPresentation = true
            controller.modalPresentationStyle = .formSheet
            if request.pairingConfirmation != nil {
                controller.sheetPresentationController?.detents = [.medium()]
            }
            approval = (id, controller)
            host.present(controller, animated: true) { [weak self] in self?.finishTransition() }
            if controller.presentingViewController == nil {
                approval = nil
                transitioning = false
                self.request = nil
                resolve?(id, false)
            }
        }

        private func presentCallback(from host: UIViewController) {
            let controller = UIHostingController(rootView: CallbackResultSheet { [weak self] in self?.closeCallback() }
                .environment(\.locale, locale))
            controller.modalPresentationStyle = .formSheet
            if let presentation = controller.sheetPresentationController {
                presentation.detents = [.custom { $0.maximumDetentValue * 0.35 }, .medium(), .large()]
                presentation.selectedDetentIdentifier = host.traitCollection.horizontalSizeClass == .regular ? .large : .medium
                presentation.prefersGrabberVisible = true
                presentation.delegate = self
            }
            callback = controller
            host.present(controller, animated: true) { [weak self] in self?.finishTransition() }
            if controller.presentingViewController == nil {
                callback = nil
                transitioning = false
            }
        }

        private func choose(_ id: UUID, allow: Bool) {
            guard !transitioning, let approval, approval.id == id, request?.id == id else { return }
            // Wait for UIKit to remove the approval sheet before the action captures the app window.
            dismiss(approval.controller) { [weak self] in
                guard let self else { return }
                self.approval = nil
                guard self.request?.id == id else { return }
                self.request = nil
                self.resolve?(id, allow)
            }
        }

        func dismissCallbackResult() async throws -> Bool {
            let deadline = ContinuousClock.now + .seconds(2)
            while callbackProvider != nil, callback != nil || callbackProvider?() == true {
                try Task.checkCancellation()
                if let callback = stableCallback {
                    guard approval == nil, callback.presentedViewController == nil else {
                        throw AgentError("Close the open sheet above the callback result in Walnut first.")
                    }
                    await withCheckedContinuation { continuation in
                        closeCallback(callback) { continuation.resume() }
                    }
                    return true
                }
                guard ContinuousClock.now < deadline else {
                    throw AgentError("The callback result sheet is still changing. Try again.")
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            return false
        }

        private var stableCallback: UIViewController? {
            guard !transitioning, let callback, callback.presentingViewController != nil, !callback.isBeingDismissed else { return nil }
            return callback
        }

        private func closeCallback() {
            guard approval == nil, let callback = stableCallback, callback.presentedViewController == nil else { return }
            closeCallback(callback)
        }

        private func closeCallback(_ controller: UIViewController, completion: @escaping () -> Void = {}) {
            clearCallbackRequest()
            dismiss(controller) { [weak self] in
                self?.callback = nil
                completion()
            }
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            guard callback === presentationController.presentedViewController else { return }
            callback = nil
            clearCallbackRequest()
            reconcile()
        }

        private func clearCallbackRequest() {
            showsCallback = false
            dismissCallback?()
        }

        private func dismiss(_ controller: UIViewController, completion: @escaping () -> Void) {
            transitioning = true
            let finish = { [weak self] in
                completion()
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
