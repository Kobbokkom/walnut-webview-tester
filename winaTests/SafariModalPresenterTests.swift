import SafariServices
import SwiftUI
import XCTest
@testable import wina

@MainActor
final class SafariModalPresenterTests: XCTestCase {
    @MainActor
    @Observable
    fileprivate final class State {
        var url: URL?
        var revision = UUID()
        var dismissals = 0
        let navigation = AgentNavigation()
    }

    private struct Harness: View {
        let state: State

        var body: some View {
            Color.clear.background {
                SafariModalPresenter(
                    url: state.url, revision: state.revision, navigation: state.navigation, usesBrowserSettings: false,
                    observeRequest: { (state.url, state.revision) },
                    onDismiss: { _ in state.dismissals += 1 }
                )
                .frame(width: 0, height: 0)
            }
        }
    }

    func testReplacementAndCloseWhileHostIsOffscreen() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let state = State()
        let host = UIHostingController(rootView: Harness(state: state))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }

        state.url = try XCTUnwrap(URL(string: "https://example.invalid/first"))
        try await wait { host.presentedViewController is SFSafariViewController && host.view.window == nil }
        let first = try XCTUnwrap(host.presentedViewController as? SFSafariViewController)
        let firstDelegate = try XCTUnwrap(first.delegate)
        let firstRun = state.navigation.runID
        XCTAssertNil(first.parent)
        XCTAssertTrue(first.presentingViewController === host)
        XCTAssertTrue(state.navigation.captureView === first.view)

        state.url = try XCTUnwrap(URL(string: "https://example.invalid/second"))
        state.revision = UUID()
        try await wait {
            host.presentedViewController !== first && host.presentedViewController is SFSafariViewController
                && state.navigation.captureView?.window != nil
        }
        let second = try XCTUnwrap(host.presentedViewController as? SFSafariViewController)
        XCTAssertNil(first.presentingViewController)
        XCTAssertNotEqual(state.navigation.runID, firstRun)
        XCTAssertTrue(state.navigation.captureView === second.view)

        firstDelegate.safariViewControllerDidFinish?(first)
        XCTAssertEqual(state.dismissals, 0)
        XCTAssertTrue(state.navigation.captureView === second.view)

        state.url = nil
        try await wait {
            host.presentedViewController == nil && state.navigation.captureView == nil && state.navigation.phase == "dismissed"
        }
        XCTAssertEqual(state.dismissals, 0)
    }

    private func wait(for condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "SafariVC presentation did not reach the expected state")
    }
}
