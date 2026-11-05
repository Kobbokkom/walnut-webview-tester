import XCTest

@MainActor
final class AdaptiveWorkspaceTests: XCTestCase {
    func testWebPageAndDevToolsRemainUsableAfterRotation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-debugAdRemovalOverride", "YES", "-appLanguage", "en", "-cleanStart", "NO", "-erudaModeEnabled", "NO",
            "-hasInitializedWebViewSize", "YES", "-webViewWidthRatio", "1", "-webViewHeightRatio", "0.75"
        ]
        addUIInterruptionMonitor(withDescription: "System permission") { alert in
            for title in ["Ask App Not to Track", "Allow", "OK"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        app.launch()
        let input = app.textFields["Enter URL"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText("https://example.com\n")
        let console = app.buttons["devTools.console"]
        let foundConsole = console.waitForExistence(timeout: 30)
        capture("URL-submitted", app: app)
        XCTAssertTrue(foundConsole)
        console.tap()
        XCTAssertTrue(app.buttons["closeDevTools"].firstMatch.waitForExistence(timeout: 10))
        capture("DevTools-initial", app: app)

        let panel = app.otherElements["devToolsPanel"]
        if app.frame.width >= 600 { XCTAssertTrue(panel.exists) }
        if panel.exists {
            let network = app.buttons["devToolsTab.network"]
            XCTAssertTrue(network.exists)
            network.tap()
            XCTAssertTrue(app.buttons["closeDevTools"].firstMatch.exists)
            app.buttons["devToolsTab.console"].tap()
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        // Let the system rotation animation settle before capturing the rendered layout.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(app.buttons["closeDevTools"].firstMatch.waitForExistence(timeout: 10))
        capture("DevTools-landscape", app: app)
        app.buttons["closeDevTools"].firstMatch.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["devToolsPanel"].exists)
        XCTAssertTrue(console.exists)
        XCUIDevice.shared.orientation = .portrait
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
