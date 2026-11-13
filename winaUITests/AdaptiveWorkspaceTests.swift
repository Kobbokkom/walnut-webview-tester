import UIKit
import XCTest

@MainActor
final class AdaptiveWorkspaceTests: XCTestCase {
    func testWebPageAndDevToolsRemainUsableAfterRotation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-debugAdRemovalOverride", "YES", "-appLanguage", "en", "-cleanStart", "NO", "-erudaModeEnabled", "NO",
            "-hasInitializedWebViewSize", "YES", "-webViewWidthRatio", "1", "-webViewHeightRatio", "0.75",
            "-hasSeenMacAgentAnnouncement", "YES",
        ]
        addUIInterruptionMonitor(withDescription: "System permission") { alert in
            for title in ["Ask App Not to Track", "Allow", "OK"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let input = app.textFields["Enter URL"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        let testURL = ProcessInfo.processInfo.environment["WALNUT_QA_URL"] ?? "https://example.com"
        let pageTitle = ProcessInfo.processInfo.environment["WALNUT_QA_TITLE"] ?? "Example Domain"
        input.typeText(testURL + "\n")
        let pageHeading = app.webViews.firstMatch.staticTexts[pageTitle]
        XCTAssertTrue(pageHeading.waitForExistence(timeout: 30))
        let console = app.buttons["devTools.console"]
        let foundConsole = console.waitForExistence(timeout: 30)
        capture("URL-submitted")
        XCTAssertTrue(foundConsole)
        console.tap()
        XCTAssertTrue(app.buttons["closeDevTools"].firstMatch.waitForExistence(timeout: 10))
        let textView = app.textViews["JavaScript to execute..."].firstMatch
        let prompt = textView.exists ? textView : app.textFields["JavaScript to execute..."].firstMatch
        XCTAssertTrue(prompt.exists)
        prompt.tap()
        prompt.typeText("window.innerWidth")
        let draft = app.descendants(matching: .any).matching(NSPredicate(format: "value == %@", "window.innerWidth")).firstMatch
        XCTAssertTrue(draft.exists)
        app.staticTexts["Console"].firstMatch.tap()
        capture("DevTools-initial")

        let panel = app.otherElements["devToolsPanel"]
        let expectsSheet = UIDevice.current.userInterfaceIdiom == .pad
            || ProcessInfo.processInfo.environment["WALNUT_QA_EXPECT_PHONE_SHEET"] == "YES"
        if expectsSheet {
            XCTAssertFalse(panel.exists)
        } else if app.frame.width >= 600 {
            XCTAssertTrue(panel.exists)
        }
        if panel.exists {
            let network = app.buttons["devToolsTab.network"]
            XCTAssertTrue(network.exists)
            network.tap()
            XCTAssertTrue(app.buttons["closeDevTools"].firstMatch.exists)
            app.buttons["devToolsTab.console"].tap()
            XCTAssertTrue(draft.exists, "Switching docked tabs discarded unexecuted Console input")
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        // Let the system rotation animation settle before capturing the rendered layout.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(app.buttons["closeDevTools"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(draft.exists, "A layout change discarded unexecuted Console input")
        if expectsSheet {
            XCTAssertFalse(panel.exists)
        }
        capture("DevTools-landscape")
        app.buttons["closeDevTools"].firstMatch.tap()
        XCTAssertTrue(pageHeading.waitForExistence(timeout: 15))
        XCTAssertFalse(app.otherElements["devToolsPanel"].exists)
        XCTAssertTrue(console.exists)
        XCUIDevice.shared.orientation = .portrait
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
