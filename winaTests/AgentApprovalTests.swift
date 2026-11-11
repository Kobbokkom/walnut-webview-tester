import SafariServices
import SwiftUI
import XCTest
@testable import wina

@MainActor
final class AgentApprovalTests: XCTestCase {
    @MainActor
    @Observable
    fileprivate final class SheetState {
        let gate = AgentApprovalGate()
        var showsCallback = false
        var backgrounds = 0
    }

    private struct SheetHarness: View {
        let state: SheetState

        var body: some View {
            Color.clear.background {
                BrowserSheetPresenter(
                    request: { state.gate.pending },
                    resolve: { state.gate.resolve($0, allow: $1) },
                    showsCallback: { state.showsCallback },
                    dismissCallback: { state.showsCallback = false },
                    onSceneExit: { state.backgrounds += 1 }
                )
                .frame(width: 0, height: 0)
            }
        }
    }

    private final class SheetHost: UIHostingController<SheetHarness> {
        private(set) var didAppear = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            didAppear = true
        }
    }

    func testCancelledPromptCannotResolveNextRequestWithIdenticalMessage() async throws {
        let gate = AgentApprovalGate()
        let first = Task { await gate.authorize("Allow action?") }
        let old = try await pending(in: gate)
        first.cancel()
        let firstAllowed = await first.value
        XCTAssertFalse(firstAllowed)

        let second = Task { await gate.authorize("Allow action?") }
        let current = try await pending(in: gate)
        XCTAssertNotEqual(current.id, old.id)
        gate.resolve(old.id, allow: true)
        XCTAssertEqual(gate.pending?.id, current.id)

        gate.resolve(current.id, allow: false)
        let secondAllowed = await second.value
        XCTAssertFalse(secondAllowed)
        XCTAssertNil(gate.pending)
    }

    func testApprovalAndCallbackUseVisibleSafariPresenter() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let state = SheetState()
        let host = SheetHost(rootView: SheetHarness(state: state))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        try await waitForSheet { host.didAppear }
        let safari = SFSafariViewController(url: try XCTUnwrap(URL(string: "https://example.invalid/")))
        host.present(safari, animated: true)
        try await waitForSheet { safari.viewIfLoaded?.window === window && host.view.window == nil }

        let approval = Task { await state.gate.authorize("Inspect this test page?") }
        defer { approval.cancel() }
        let request = try await pending(in: state.gate)
        try await waitForSheet { safari.presentedViewController != nil }
        let approvalSheet = try XCTUnwrap(safari.presentedViewController)
        XCTAssertTrue(approvalSheet.isModalInPresentation)

        state.showsCallback = true
        state.gate.resolve(request.id, allow: false)
        let allowed = await approval.value
        XCTAssertFalse(allowed)
        try await waitForSheet {
            safari.presentedViewController != nil && safari.presentedViewController !== approvalSheet
        }
        let callback = try XCTUnwrap(safari.presentedViewController)
        XCTAssertFalse(callback.isModalInPresentation)

        let nested = Task { await state.gate.authorize("Read this callback?") }
        defer { nested.cancel() }
        let nestedRequest = try await pending(in: state.gate)
        try await waitForSheet { callback.presentedViewController?.isModalInPresentation == true }
        state.gate.resolve(nestedRequest.id, allow: false)
        let nestedAllowed = await nested.value
        XCTAssertFalse(nestedAllowed)
        try await waitForSheet { callback.presentedViewController == nil }
        XCTAssertTrue(safari.presentedViewController === callback)
        state.showsCallback = false
        try await waitForSheet { safari.presentedViewController == nil }
        XCTAssertTrue(host.presentedViewController === safari)
        XCTAssertEqual(state.backgrounds, 0)
        NotificationCenter.default.post(name: UIScene.didEnterBackgroundNotification, object: scene)
        XCTAssertEqual(state.backgrounds, 1)
    }

    private func waitForSheet(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Safari sheet did not reach the expected presentation state")
    }

    private func pending(in gate: AgentApprovalGate) async throws -> AgentApprovalGate.Request {
        for _ in 0..<50 {
            if let request = gate.pending { return request }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try XCTUnwrap(gate.pending)
    }
}
