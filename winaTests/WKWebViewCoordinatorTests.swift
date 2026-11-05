import SwiftUI
import WebKit
import XCTest
@testable import wina

final class WKWebViewCoordinatorTests: XCTestCase {
    private static var retainedNavigators: [WebViewNavigator] = []

    private final class CoordinatorSpyNavigator: WebViewNavigator {
        var syncCallCount: Int = 0
        var syncForceInitValues: [Bool] = []
        var onSync: (() -> Void)?

        override func syncErudaWithSettings(forceInit: Bool = false) async {
            syncCallCount += 1
            syncForceInitValues.append(forceInit)
            onSync?()
        }
    }

    private final class ErudaSyncSpyNavigator: WebViewNavigator {
        var injectCallCount: Int = 0
        var destroyCallCount: Int = 0

        override func injectEruda(forceInit: Bool = false) async {
            injectCallCount += 1
        }

        override func destroyEruda() async {
            destroyCallCount += 1
        }
    }

    @MainActor
    func testDidFinishTriggersErudaSync() {
        // didFinish 이후 Eruda 동기화가 항상 한 번 호출되는지 확인합니다.
        var isLoading = false
        let binding = Binding(
            get: { isLoading },
            set: { isLoading = $0 }
        )
        let navigator = CoordinatorSpyNavigator()
        Self.retainedNavigators.append(navigator)
        let expectation = expectation(description: "sync called")
        navigator.onSync = {
            expectation.fulfill()
        }

        let coordinator = WKWebViewCoordinator(isLoading: binding, navigator: navigator)
        let webView = WKWebView(frame: .zero)

        coordinator.webView(webView, didFinish: nil)

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(navigator.syncCallCount, 1)
        XCTAssertEqual(navigator.syncForceInitValues, [false])
    }

    @MainActor
    func testDidFinishUsesForceInitWhenScheduled() {
        // reload 예약 플래그가 있으면 forceInit=true로 동기화되는지 확인합니다.
        var isLoading = false
        let binding = Binding(
            get: { isLoading },
            set: { isLoading = $0 }
        )
        let navigator = CoordinatorSpyNavigator()
        Self.retainedNavigators.append(navigator)
        let expectation = expectation(description: "sync called")
        navigator.onSync = {
            expectation.fulfill()
        }

        let coordinator = WKWebViewCoordinator(isLoading: binding, navigator: navigator)
        let webView = WKWebView(frame: .zero)

        coordinator.scheduleForceErudaInitOnNextFinish()
        coordinator.webView(webView, didFinish: nil)

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(navigator.syncForceInitValues.last, true)
    }

    @MainActor
    func testDidFinishUsesForceInitAfterManualReloadPreparation() {
        // header refresh 경로처럼 수동 reload 준비를 하면 forceInit=true가 전달되어야 합니다.
        var isLoading = false
        let binding = Binding(
            get: { isLoading },
            set: { isLoading = $0 }
        )
        let navigator = CoordinatorSpyNavigator()
        Self.retainedNavigators.append(navigator)
        let expectation = expectation(description: "sync called")
        navigator.onSync = {
            expectation.fulfill()
        }

        let coordinator = WKWebViewCoordinator(isLoading: binding, navigator: navigator)
        let webView = WKWebView(frame: .zero)

        coordinator.prepareForManualReloadRequest()
        coordinator.webView(webView, didFinish: nil)

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(navigator.syncForceInitValues.last, true)
    }

    @MainActor
    func testForceInitFlagResetsAfterFirstDidFinish() {
        // force-init 플래그는 첫 didFinish에서만 true이고 이후에는 false로 돌아와야 합니다.
        var isLoading = false
        let binding = Binding(
            get: { isLoading },
            set: { isLoading = $0 }
        )
        let navigator = CoordinatorSpyNavigator()
        Self.retainedNavigators.append(navigator)

        let firstSyncExpectation = expectation(description: "first sync called")
        let secondSyncExpectation = expectation(description: "second sync called")
        var syncCount = 0
        navigator.onSync = {
            syncCount += 1
            if syncCount == 1 {
                firstSyncExpectation.fulfill()
            } else if syncCount == 2 {
                secondSyncExpectation.fulfill()
            }
        }

        let coordinator = WKWebViewCoordinator(isLoading: binding, navigator: navigator)
        let webView = WKWebView(frame: .zero)

        coordinator.scheduleForceErudaInitOnNextFinish()
        coordinator.webView(webView, didFinish: nil)

        wait(for: [firstSyncExpectation], timeout: 1.0)
        // 첫 sync Task 완료 후 플래그 해제가 반영되도록 한 번 양보합니다.
        let settleExpectation = expectation(description: "force-init flag settle")
        Task { @MainActor in
            await Task.yield()
            settleExpectation.fulfill()
        }
        wait(for: [settleExpectation], timeout: 1.0)

        coordinator.webView(webView, didFinish: nil)
        wait(for: [secondSyncExpectation], timeout: 1.0)

        XCTAssertEqual(navigator.syncForceInitValues, [true, false])
    }

    @MainActor
    func testDidFailClearsPendingForceInitFlag() {
        // reload 실패 후에는 다음 didFinish에 forceInit이 남지 않아야 합니다.
        var isLoading = false
        let binding = Binding(
            get: { isLoading },
            set: { isLoading = $0 }
        )
        let navigator = CoordinatorSpyNavigator()
        Self.retainedNavigators.append(navigator)
        let expectation = expectation(description: "sync called")
        navigator.onSync = {
            expectation.fulfill()
        }

        let coordinator = WKWebViewCoordinator(isLoading: binding, navigator: navigator)
        let webView = WKWebView(frame: .zero)

        coordinator.scheduleForceErudaInitOnNextFinish()
        coordinator.webView(webView, didFail: nil, withError: URLError(.timedOut))
        coordinator.webView(webView, didFinish: nil)

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(navigator.syncForceInitValues.last, false)
    }

    @MainActor
    func testDidFailProvisionalNavigationClearsPendingForceInitFlag() {
        // provisional 실패 후에도 forceInit 잔존 없이 동기화되어야 합니다.
        var isLoading = false
        let binding = Binding(
            get: { isLoading },
            set: { isLoading = $0 }
        )
        let navigator = CoordinatorSpyNavigator()
        Self.retainedNavigators.append(navigator)
        let expectation = expectation(description: "sync called")
        navigator.onSync = {
            expectation.fulfill()
        }

        let coordinator = WKWebViewCoordinator(isLoading: binding, navigator: navigator)
        let webView = WKWebView(frame: .zero)

        coordinator.scheduleForceErudaInitOnNextFinish()
        coordinator.webView(webView, didFailProvisionalNavigation: nil, withError: URLError(.cannotFindHost))
        coordinator.webView(webView, didFinish: nil)

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(navigator.syncForceInitValues.last, false)
    }

    @MainActor
    func testDelayedBridgeResponseWorkItemIsRemovedAfterExecution() {
        var isLoading = false
        let binding = Binding(
            get: { isLoading },
            set: { isLoading = $0 }
        )
        let navigator = WebViewNavigator()
        Self.retainedNavigators.append(navigator)
        let coordinator = WKWebViewCoordinator(isLoading: binding, navigator: navigator)

        coordinator.schedulePreloadBridgeResponse(
            "window.__walnutResponse = true;",
            channel: "request",
            delayMilliseconds: 10
        )
        XCTAssertEqual(coordinator.pendingBridgeResponseWorkItemCount, 1)

        let expectation = expectation(description: "delayed bridge response fires")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(coordinator.pendingBridgeResponseWorkItemCount, 0)
        XCTAssertEqual(navigator.preloadBridgeLogManager.entries.filter { $0.direction == .responded }.count, 1)
    }

    @MainActor
    func testDelayedBridgeResponseIsCancelledOnCommit() async {
        var isLoading = false
        let binding = Binding(
            get: { isLoading },
            set: { isLoading = $0 }
        )
        let navigator = WebViewNavigator()
        Self.retainedNavigators.append(navigator)
        let coordinator = WKWebViewCoordinator(isLoading: binding, navigator: navigator)

        let webView = WKWebView(frame: .zero)
        coordinator.schedulePreloadBridgeResponse(
            "window.__walnutResponse = true;",
            channel: "request",
            delayMilliseconds: 50
        )
        XCTAssertEqual(coordinator.pendingBridgeResponseWorkItemCount, 1)

        coordinator.webView(webView, didCommit: nil)
        XCTAssertEqual(coordinator.pendingBridgeResponseWorkItemCount, 0)

        let expectation = expectation(description: "cancelled bridge response would have fired")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertFalse(navigator.preloadBridgeLogManager.entries.contains { $0.direction == .responded })
    }

    @MainActor
    func testDelayedBridgeResponseIsCancelledWhenMainFrameNavigationStartsBeforeCommit() {
        var isLoading = false
        let binding = Binding(
            get: { isLoading },
            set: { isLoading = $0 }
        )
        let navigator = WebViewNavigator()
        Self.retainedNavigators.append(navigator)
        let coordinator = WKWebViewCoordinator(isLoading: binding, navigator: navigator)

        coordinator.schedulePreloadBridgeResponse(
            "window.__walnutResponse = true;",
            channel: "request",
            delayMilliseconds: 50
        )
        XCTAssertEqual(coordinator.pendingBridgeResponseWorkItemCount, 1)

        coordinator.handleMainFrameNavigationStarted(
            from: URL(string: "https://example.com/old"),
            to: URL(string: "https://example.com/new")
        )
        XCTAssertEqual(coordinator.pendingBridgeResponseWorkItemCount, 0)

        let delayedResponseExpectation = expectation(description: "cancelled bridge response would have fired")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            delayedResponseExpectation.fulfill()
        }
        wait(for: [delayedResponseExpectation], timeout: 1.0)

        XCTAssertFalse(navigator.preloadBridgeLogManager.entries.contains { $0.direction == .responded })
    }

    @MainActor
    func testDelayedBridgeResponseIsNotCancelledForSameDocumentNavigation() {
        var isLoading = false
        let binding = Binding(
            get: { isLoading },
            set: { isLoading = $0 }
        )
        let navigator = WebViewNavigator()
        Self.retainedNavigators.append(navigator)
        let coordinator = WKWebViewCoordinator(isLoading: binding, navigator: navigator)

        coordinator.schedulePreloadBridgeResponse(
            "window.__walnutResponse = true;",
            channel: "request",
            delayMilliseconds: 50
        )
        XCTAssertEqual(coordinator.pendingBridgeResponseWorkItemCount, 1)

        coordinator.handleMainFrameNavigationStarted(
            from: URL(string: "https://example.com/page#old"),
            to: URL(string: "https://example.com/page#new")
        )
        XCTAssertEqual(coordinator.pendingBridgeResponseWorkItemCount, 1)

        let delayedResponseExpectation = expectation(description: "bridge response fired")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            delayedResponseExpectation.fulfill()
        }
        wait(for: [delayedResponseExpectation], timeout: 1.0)

        XCTAssertTrue(navigator.preloadBridgeLogManager.entries.contains { $0.direction == .responded })
    }

    @MainActor
    func testSyncErudaWithSettingsCallsInjectWhenEnabled() async {
        // 설정값이 true면 inject 경로를 타는지 검증합니다.
        let defaults = UserDefaults.standard
        let key = "erudaModeEnabled"
        let previousValue = defaults.object(forKey: key)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(true, forKey: key)

        let navigator = ErudaSyncSpyNavigator()
        Self.retainedNavigators.append(navigator)
        navigator.attach(to: WKWebView(frame: .zero))

        await navigator.syncErudaWithSettings()

        XCTAssertEqual(navigator.injectCallCount, 1)
        XCTAssertEqual(navigator.destroyCallCount, 0)
    }

    @MainActor
    func testSyncErudaWithSettingsCallsDestroyWhenDisabled() async {
        // 설정값이 false면 destroy 경로를 타는지 검증합니다.
        let defaults = UserDefaults.standard
        let key = "erudaModeEnabled"
        let previousValue = defaults.object(forKey: key)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(false, forKey: key)

        let navigator = ErudaSyncSpyNavigator()
        Self.retainedNavigators.append(navigator)
        navigator.attach(to: WKWebView(frame: .zero))

        await navigator.syncErudaWithSettings()

        XCTAssertEqual(navigator.injectCallCount, 0)
        XCTAssertEqual(navigator.destroyCallCount, 1)
    }
}
