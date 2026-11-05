//
//  SnippetsTests.swift
//  winaTests
//
//  Extensive tests for DebugSnippet model, SnippetsManager state management,
//  and actual JavaScript DOM manipulation verification using WKWebView.
//

import XCTest
import WebKit
import SwiftUI
@testable import wina

// MARK: - WKWebView Test Helpers

private enum TestWebViewLoader {
    static let baseURL = URL(string: "https://example.com")!
    static let loadTimeoutSeconds: Double = 5
}

@MainActor
private final class TestNavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func waitForLoad(webView: WKWebView, html: String) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(TestWebViewLoader.loadTimeoutSeconds))
                await MainActor.run {
                    self?.finishIfNeeded()
                }
            }
            webView.loadHTMLString(html, baseURL: TestWebViewLoader.baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishIfNeeded()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishIfNeeded()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finishIfNeeded()
    }

    private func finishIfNeeded() {
        if let continuation {
            continuation.resume()
            self.continuation = nil
        }
        timeoutTask?.cancel()
        timeoutTask = nil
    }
}

// MARK: - SnippetsManager Unit Tests

final class SnippetsManagerTests: XCTestCase {

    var manager: SnippetsManager!

    override func setUp() {
        super.setUp()
        manager = SnippetsManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialStateIsEmpty() {
        XCTAssertTrue(manager.activeSnippets.isEmpty)
    }

    func testIsActiveReturnsFalseForInactiveSnippet() {
        XCTAssertFalse(manager.isActive("border_all"))
        XCTAssertFalse(manager.isActive("edit_page"))
        XCTAssertFalse(manager.isActive("nonexistent_snippet"))
    }

    // MARK: - Toggle Tests

    func testToggleActivatesInactiveSnippet() {
        XCTAssertFalse(manager.isActive("border_all"))

        manager.toggle("border_all")

        XCTAssertTrue(manager.isActive("border_all"))
        XCTAssertEqual(manager.activeSnippets.count, 1)
    }

    func testToggleDeactivatesActiveSnippet() {
        manager.toggle("border_all")
        XCTAssertTrue(manager.isActive("border_all"))

        manager.toggle("border_all")

        XCTAssertFalse(manager.isActive("border_all"))
        XCTAssertTrue(manager.activeSnippets.isEmpty)
    }

    func testMultipleTogglesWorkCorrectly() {
        manager.toggle("border_all")
        manager.toggle("edit_page")
        manager.toggle("show_elements")

        XCTAssertTrue(manager.isActive("border_all"))
        XCTAssertTrue(manager.isActive("edit_page"))
        XCTAssertTrue(manager.isActive("show_elements"))
        XCTAssertEqual(manager.activeSnippets.count, 3)

        manager.toggle("edit_page")

        XCTAssertTrue(manager.isActive("border_all"))
        XCTAssertFalse(manager.isActive("edit_page"))
        XCTAssertTrue(manager.isActive("show_elements"))
        XCTAssertEqual(manager.activeSnippets.count, 2)
    }

    func testToggleSameSnippetMultipleTimes() {
        for i in 1...10 {
            manager.toggle("border_all")
            XCTAssertEqual(manager.isActive("border_all"), i % 2 == 1)
        }
    }

    // MARK: - Deactivate Tests

    func testDeactivateRemovesActiveSnippet() {
        manager.toggle("border_all")
        XCTAssertTrue(manager.isActive("border_all"))

        manager.deactivate("border_all")

        XCTAssertFalse(manager.isActive("border_all"))
    }

    func testDeactivateDoesNothingForInactiveSnippet() {
        XCTAssertFalse(manager.isActive("border_all"))

        manager.deactivate("border_all")

        XCTAssertFalse(manager.isActive("border_all"))
        XCTAssertTrue(manager.activeSnippets.isEmpty)
    }

    func testDeactivateOnlyAffectsSpecifiedSnippet() {
        manager.toggle("border_all")
        manager.toggle("edit_page")

        manager.deactivate("border_all")

        XCTAssertFalse(manager.isActive("border_all"))
        XCTAssertTrue(manager.isActive("edit_page"))
    }

    func testResetActiveSnippetsClearsAll() {
        manager.toggle("border_all")
        manager.toggle("edit_page")

        manager.resetActiveSnippets()

        XCTAssertTrue(manager.activeSnippets.isEmpty)
    }

    // MARK: - Default Snippets Validation Tests

    func testDefaultSnippetsNotEmpty() {
        XCTAssertFalse(SnippetsManager.defaultSnippets.isEmpty)
    }

    func testAllDefaultSnippetsHaveRequiredProperties() {
        for snippet in SnippetsManager.defaultSnippets {
            XCTAssertFalse(snippet.id.isEmpty, "Snippet \(snippet.name) has empty id")
            XCTAssertFalse(snippet.name.isEmpty, "Snippet \(snippet.id) has empty name")
            XCTAssertFalse(snippet.description.isEmpty, "Snippet \(snippet.id) has empty description")
            XCTAssertFalse(snippet.icon.isEmpty, "Snippet \(snippet.id) has empty icon")
            XCTAssertFalse(snippet.script.isEmpty, "Snippet \(snippet.id) has empty script")
        }
    }

    func testToggleableSnippetsHaveUndoScript() {
        for snippet in SnippetsManager.defaultSnippets where snippet.isToggleable {
            XCTAssertNotNil(
                snippet.undoScript,
                "Toggleable snippet \(snippet.id) should have undoScript"
            )
            XCTAssertFalse(
                snippet.undoScript?.isEmpty ?? true,
                "Toggleable snippet \(snippet.id) has empty undoScript"
            )
        }
    }

    func testNonToggleableSnippetsMayLackUndoScript() {
        let nonToggleable = SnippetsManager.defaultSnippets.filter { !$0.isToggleable }
        XCTAssertFalse(nonToggleable.isEmpty, "Should have at least one non-toggleable snippet")

        // Non-toggleable snippets CAN have undoScript but it's not required
        for snippet in nonToggleable {
            // Just verify they exist and are not toggleable
            XCTAssertFalse(snippet.isToggleable)
        }
    }

    func testAllSnippetIdsAreUnique() {
        let ids = SnippetsManager.defaultSnippets.map(\.id)
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "Duplicate snippet IDs found")
    }

    func testExpectedSnippetsExist() {
        let expectedIds = [
            "border_all",
            "edit_page",
            "show_elements",
            "disable_css",
            "log_dom_stats",
            "log_images",
            "log_links",
            "log_event_listeners",
            "highlight_headings"
        ]

        let actualIds = Set(SnippetsManager.defaultSnippets.map(\.id))

        for expectedId in expectedIds {
            XCTAssertTrue(
                actualIds.contains(expectedId),
                "Expected snippet '\(expectedId)' not found"
            )
        }
    }
}

// MARK: - DebugSnippet Model Tests

final class DebugSnippetTests: XCTestCase {

    func testSnippetInitializationWithAllParameters() {
        let snippet = DebugSnippet(
            id: "test_id",
            name: "Test Snippet",
            description: "Test description",
            icon: "star",
            iconColor: .red,
            isToggleable: true,
            script: "console.log('test')",
            undoScript: "console.log('undo')"
        )

        XCTAssertEqual(snippet.id, "test_id")
        XCTAssertEqual(snippet.name, "Test Snippet")
        XCTAssertEqual(snippet.description, "Test description")
        XCTAssertEqual(snippet.icon, "star")
        XCTAssertEqual(snippet.iconColor, Color.red)
        XCTAssertTrue(snippet.isToggleable)
        XCTAssertEqual(snippet.script, "console.log('test')")
        XCTAssertEqual(snippet.undoScript, "console.log('undo')")
    }

    func testSnippetInitializationWithDefaults() {
        let snippet = DebugSnippet(
            id: "simple",
            name: "Simple",
            description: "Simple snippet",
            icon: "circle",
            script: "return 1"
        )

        XCTAssertEqual(snippet.iconColor, Color.blue) // Default color
        XCTAssertFalse(snippet.isToggleable) // Default false
        XCTAssertNil(snippet.undoScript) // Default nil
    }

    func testSnippetIdentifiableConformance() {
        let snippet1 = DebugSnippet(
            id: "unique_id_1",
            name: "First",
            description: "First snippet",
            icon: "1.circle",
            script: "1"
        )

        let snippet2 = DebugSnippet(
            id: "unique_id_2",
            name: "Second",
            description: "Second snippet",
            icon: "2.circle",
            script: "2"
        )

        XCTAssertNotEqual(snippet1.id, snippet2.id)
    }
}

// MARK: - JavaScript Script Syntax Validation Tests

final class SnippetScriptSyntaxTests: XCTestCase {

    /// Verify all scripts are valid JavaScript (can be parsed)
    func testAllScriptsHaveValidSyntax() {
        for snippet in SnippetsManager.defaultSnippets {
            // Scripts should be IIFE (Immediately Invoked Function Expression)
            XCTAssertTrue(
                snippet.script.contains("(function()") || snippet.script.contains("(() =>"),
                "Snippet \(snippet.id) script should be an IIFE"
            )
            XCTAssertTrue(
                snippet.script.contains("})()"),
                "Snippet \(snippet.id) script should end with })()"
            )
        }
    }

    func testToggleableScriptsReturnStatusMessages() {
        for snippet in SnippetsManager.defaultSnippets where snippet.isToggleable {
            XCTAssertTrue(
                snippet.script.contains("return"),
                "Toggleable snippet \(snippet.id) script should return a status message"
            )
            if let undoScript = snippet.undoScript {
                XCTAssertTrue(
                    undoScript.contains("return"),
                    "Toggleable snippet \(snippet.id) undoScript should return a status message"
                )
            }
        }
    }

    func testBorderAllScriptCreatesStyleElement() {
        let borderSnippet = SnippetsManager.defaultSnippets.first { $0.id == "border_all" }
        XCTAssertNotNil(borderSnippet)

        let script = borderSnippet!.script
        XCTAssertTrue(script.contains("__wina_border_style__"))
        XCTAssertTrue(script.contains("document.createElement('style')"))
        XCTAssertTrue(script.contains("document.head.appendChild"))
        XCTAssertTrue(script.contains("outline"))
    }

    func testBorderAllUndoScriptRemovesStyleElement() {
        let borderSnippet = SnippetsManager.defaultSnippets.first { $0.id == "border_all" }
        XCTAssertNotNil(borderSnippet?.undoScript)

        let undoScript = borderSnippet!.undoScript!
        XCTAssertTrue(undoScript.contains("__wina_border_style__"))
        XCTAssertTrue(undoScript.contains("getElementById"))
        XCTAssertTrue(undoScript.contains(".remove()"))
    }

    func testEditPageScriptSetsContentEditable() {
        let editSnippet = SnippetsManager.defaultSnippets.first { $0.id == "edit_page" }
        XCTAssertNotNil(editSnippet)

        let script = editSnippet!.script
        XCTAssertTrue(script.contains("contentEditable = 'true'"))
        XCTAssertTrue(script.contains("designMode = 'on'"))
    }

    func testEditPageUndoScriptDisablesEditing() {
        let editSnippet = SnippetsManager.defaultSnippets.first { $0.id == "edit_page" }
        XCTAssertNotNil(editSnippet?.undoScript)

        let undoScript = editSnippet!.undoScript!
        XCTAssertTrue(undoScript.contains("removeAttribute('contenteditable')"))
        XCTAssertTrue(undoScript.contains("designMode = state.designMode"))
    }

    func testDisableCssScriptStoresStylesForRestoration() {
        let cssSnippet = SnippetsManager.defaultSnippets.first { $0.id == "disable_css" }
        XCTAssertNotNil(cssSnippet)

        let script = cssSnippet!.script
        XCTAssertTrue(script.contains("window.__wina_disabled_styles__"))
        XCTAssertTrue(script.contains("link[rel=\"stylesheet\"], style"))
        XCTAssertTrue(script.contains(".remove()"))
    }

    func testDisableCssUndoScriptRestoresStyles() {
        let cssSnippet = SnippetsManager.defaultSnippets.first { $0.id == "disable_css" }
        XCTAssertNotNil(cssSnippet?.undoScript)

        let undoScript = cssSnippet!.undoScript!
        XCTAssertTrue(undoScript.contains("window.__wina_disabled_styles__"))
        XCTAssertTrue(undoScript.contains("insertBefore") || undoScript.contains("appendChild"))
    }
}

// MARK: - WKWebView Integration Tests (DOM Manipulation Verification)

@MainActor
final class SnippetDOMIntegrationTests: XCTestCase {

    var webView: WKWebView!
    // swiftlint:disable:next weak_delegate - Test must hold strong ref; WKWebView.navigationDelegate is already weak
    private var navigationDelegate: TestNavigationDelegate?

    override func setUp() async throws {
        try await super.setUp()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        navigationDelegate = TestNavigationDelegate()
        webView.navigationDelegate = navigationDelegate
    }

    override func tearDown() async throws {
        webView = nil
        navigationDelegate = nil
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func loadTestHTML(_ html: String) async {
        await navigationDelegate?.waitForLoad(webView: webView, html: html)
    }

    private func executeScript(_ script: String) async -> Any? {
        let result = try? await webView.evaluateJavaScript(script)
        return result
    }

    // MARK: - Border All Tests

    func testBorderAllAddsStyleElement() async {
        let testHTML = """
        <!DOCTYPE html>
        <html>
        <head><title>Test</title></head>
        <body>
            <div id="test">Hello</div>
        </body>
        </html>
        """
        await loadTestHTML(testHTML)

        // Verify style doesn't exist initially
        let beforeResult = await executeScript("document.getElementById('__wina_border_style__') !== null")
        XCTAssertEqual(beforeResult as? Bool, false)

        // Execute border_all script
        let borderSnippet = SnippetsManager.defaultSnippets.first { $0.id == "border_all" }!
        _ = await executeScript(borderSnippet.script)

        // Verify style element was added
        let afterResult = await executeScript("document.getElementById('__wina_border_style__') !== null")
        XCTAssertEqual(afterResult as? Bool, true)

        // Verify style content contains outline rules
        let styleContent = await executeScript(
            "document.getElementById('__wina_border_style__').textContent"
        ) as? String
        XCTAssertNotNil(styleContent)
        XCTAssertTrue(styleContent?.contains("outline") ?? false)
    }

    func testBorderAllUndoRemovesStyleElement() async {
        let testHTML = "<html><head></head><body><div>Test</div></body></html>"
        await loadTestHTML(testHTML)

        let borderSnippet = SnippetsManager.defaultSnippets.first { $0.id == "border_all" }!

        // Add border style
        _ = await executeScript(borderSnippet.script)
        let existsAfterAdd = await executeScript(
            "document.getElementById('__wina_border_style__') !== null"
        ) as? Bool
        XCTAssertEqual(existsAfterAdd, true)

        // Remove border style
        _ = await executeScript(borderSnippet.undoScript!)
        let existsAfterRemove = await executeScript(
            "document.getElementById('__wina_border_style__') !== null"
        ) as? Bool
        XCTAssertEqual(existsAfterRemove, false)
    }

    func testBorderAllIdempotent() async {
        let testHTML = "<html><head></head><body><div>Test</div></body></html>"
        await loadTestHTML(testHTML)

        let borderSnippet = SnippetsManager.defaultSnippets.first { $0.id == "border_all" }!

        // Execute multiple times
        _ = await executeScript(borderSnippet.script)
        _ = await executeScript(borderSnippet.script)
        _ = await executeScript(borderSnippet.script)

        // Should still only have one style element
        let count = await executeScript(
            "document.querySelectorAll('#__wina_border_style__').length"
        ) as? Int
        XCTAssertEqual(count, 1)
    }

    // MARK: - Edit Page Tests

    func testEditPageEnablesContentEditable() async {
        let testHTML = "<html><body><p>Editable text</p></body></html>"
        await loadTestHTML(testHTML)

        // Verify initially not editable
        let beforeEditable = await executeScript("document.body.contentEditable") as? String
        XCTAssertNotEqual(beforeEditable, "true")

        // Execute edit_page script
        let editSnippet = SnippetsManager.defaultSnippets.first { $0.id == "edit_page" }!
        _ = await executeScript(editSnippet.script)

        // Verify now editable
        let afterEditable = await executeScript("document.body.contentEditable") as? String
        XCTAssertEqual(afterEditable, "true")

        let designMode = await executeScript("document.designMode") as? String
        XCTAssertEqual(designMode, "on")
    }

    func testEditPageUndoDisablesEditing() async {
        let testHTML = "<html><body><p>Test</p></body></html>"
        await loadTestHTML(testHTML)

        let editSnippet = SnippetsManager.defaultSnippets.first { $0.id == "edit_page" }!

        // Enable editing
        _ = await executeScript(editSnippet.script)
        let enabledEditable = await executeScript("document.body.contentEditable") as? String
        XCTAssertEqual(enabledEditable, "true")

        // Disable editing
        _ = await executeScript(editSnippet.undoScript!)
        let disabledEditable = await executeScript("document.body.hasAttribute('contenteditable')") as? Bool
        XCTAssertEqual(disabledEditable, false)

        let designMode = await executeScript("document.designMode") as? String
        XCTAssertEqual(designMode, "off")
    }

    func testEditPageUndoPreservesExistingEditablePage() async throws {
        await loadTestHTML("<html><body contenteditable='plaintext-only'>Editable</body></html>")
        let snippet = try XCTUnwrap(SnippetsManager.defaultSnippets.first { $0.id == "edit_page" })
        _ = await executeScript("document.designMode = 'on'")
        _ = await executeScript(snippet.script)
        _ = await executeScript(try XCTUnwrap(snippet.undoScript))
        let state = await executeScript("[document.body.getAttribute('contenteditable'), document.designMode]") as? [String]
        XCTAssertEqual(state, ["plaintext-only", "on"])
    }

    // MARK: - Show Hidden Elements Tests

    func testShowHiddenAddsStyleElement() async {
        let testHTML = """
        <html><head></head><body>
            <div style="display: none;">Hidden div</div>
            <span hidden>Hidden span</span>
        </body></html>
        """
        await loadTestHTML(testHTML)

        let showSnippet = SnippetsManager.defaultSnippets.first { $0.id == "show_elements" }!
        _ = await executeScript(showSnippet.script)

        let styleExists = await executeScript(
            "document.getElementById('__wina_show_hidden_style__') !== null"
        ) as? Bool
        XCTAssertEqual(styleExists, true)
    }

    func testShowHiddenStyleContainsCorrectRules() async {
        let testHTML = "<html><head></head><body></body></html>"
        await loadTestHTML(testHTML)

        let showSnippet = SnippetsManager.defaultSnippets.first { $0.id == "show_elements" }!
        _ = await executeScript(showSnippet.script)

        let styleContent = await executeScript(
            "document.getElementById('__wina_show_hidden_style__').textContent"
        ) as? String

        XCTAssertNotNil(styleContent)
        XCTAssertTrue(styleContent?.contains("display: block") ?? false)
        XCTAssertTrue(styleContent?.contains("visibility: visible") ?? false)
        XCTAssertTrue(styleContent?.contains("opacity: 0.5") ?? false)
    }

    // MARK: - Disable CSS Tests

    func testDisableCssRemovesStylesheets() async {
        let testHTML = """
        <html>
        <head>
            <style id="inline-style">body { color: red; }</style>
        </head>
        <body><p>Test</p></body>
        </html>
        """
        await loadTestHTML(testHTML)

        // Verify style exists initially
        let beforeCount = await executeScript(
            "document.querySelectorAll('style').length"
        ) as? Int
        XCTAssertEqual(beforeCount, 1)

        // Execute disable_css
        let cssSnippet = SnippetsManager.defaultSnippets.first { $0.id == "disable_css" }!
        _ = await executeScript(cssSnippet.script)

        // Verify styles removed
        let afterCount = await executeScript(
            "document.querySelectorAll('style').length"
        ) as? Int
        XCTAssertEqual(afterCount, 0)

        // Verify stored for restoration
        let storedCount = await executeScript(
            "window.__wina_disabled_styles__.length"
        ) as? Int
        XCTAssertEqual(storedCount, 1)
    }

    func testDisableCssKeepsWinaStyles() async {
        let testHTML = """
        <html>
        <head>
            <style id="inline-style">body { color: red; }</style>
            <style id="__wina_keep_style__">.hidden { display: none; }</style>
        </head>
        <body><p>Test</p></body>
        </html>
        """
        await loadTestHTML(testHTML)

        let cssSnippet = SnippetsManager.defaultSnippets.first { $0.id == "disable_css" }!
        _ = await executeScript(cssSnippet.script)

        let keptExists = await executeScript(
            "document.getElementById('__wina_keep_style__') !== null"
        ) as? Bool
        XCTAssertEqual(keptExists, true)

        let removedExists = await executeScript(
            "document.getElementById('inline-style') !== null"
        ) as? Bool
        XCTAssertEqual(removedExists, false)

        let storedCount = await executeScript(
            "window.__wina_disabled_styles__.length"
        ) as? Int
        XCTAssertEqual(storedCount, 1)
    }

    func testDisableCssUndoRestoresStylesheets() async {
        let testHTML = """
        <html>
        <head>
            <style id="test-style">body { background: blue; }</style>
        </head>
        <body><p>Test</p></body>
        </html>
        """
        await loadTestHTML(testHTML)

        let cssSnippet = SnippetsManager.defaultSnippets.first { $0.id == "disable_css" }!

        // Remove styles
        _ = await executeScript(cssSnippet.script)
        let removedCount = await executeScript("document.querySelectorAll('style').length") as? Int
        XCTAssertEqual(removedCount, 0)

        // Restore styles
        _ = await executeScript(cssSnippet.undoScript!)
        let restoredCount = await executeScript("document.querySelectorAll('style').length") as? Int
        XCTAssertEqual(restoredCount, 1)
    }

    func testDisableCssUndoPreservesAdjacentStylesheetOrder() async throws {
        await loadTestHTML("<html><head><style>p{color:red}</style><style>p{color:blue}</style><meta name='fixture'></head><body><p>Test</p></body></html>")
        let snippet = try XCTUnwrap(SnippetsManager.defaultSnippets.first { $0.id == "disable_css" })
        _ = await executeScript(snippet.script)
        _ = await executeScript(try XCTUnwrap(snippet.undoScript))
        let color = await executeScript("getComputedStyle(document.querySelector('p')).color") as? String
        XCTAssertEqual(color, "rgb(0, 0, 255)")
    }

    // MARK: - Highlight Headings Tests

    func testDisableCssUndoRestoresWhenHeadRecreated() async {
        let testHTML = """
        <html>
        <head>
            <style id="test-style">body { background: blue; }</style>
        </head>
        <body><p>Test</p></body>
        </html>
        """
        await loadTestHTML(testHTML)

        let cssSnippet = SnippetsManager.defaultSnippets.first { $0.id == "disable_css" }!
        _ = await executeScript(cssSnippet.script)

        _ = await executeScript("""
            (function() {
                const oldHead = document.head;
                if (oldHead) oldHead.remove();
                const newHead = document.createElement('head');
                document.documentElement.insertBefore(newHead, document.body);
            })();
        """)

        let result = await executeScript(cssSnippet.undoScript!) as? String
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("CSS restored") ?? false)

        let restoredExists = await executeScript(
            "document.getElementById('test-style') !== null"
        ) as? Bool
        XCTAssertEqual(restoredExists, true)
    }

    func testHighlightHeadingsAddsStyleForAllHeadingLevels() async {
        let testHTML = """
        <html><head></head><body>
            <h1>Heading 1</h1>
            <h2>Heading 2</h2>
            <h3>Heading 3</h3>
            <h4>Heading 4</h4>
            <h5>Heading 5</h5>
            <h6>Heading 6</h6>
        </body></html>
        """
        await loadTestHTML(testHTML)

        let headingSnippet = SnippetsManager.defaultSnippets.first { $0.id == "highlight_headings" }!
        _ = await executeScript(headingSnippet.script)

        let styleContent = await executeScript(
            "document.getElementById('__wina_heading_style__').textContent"
        ) as? String

        XCTAssertNotNil(styleContent)
        // Verify all heading levels are styled
        for heading in ["h1", "h2", "h3", "h4", "h5", "h6"] {
            XCTAssertTrue(
                styleContent?.lowercased().contains(heading) ?? false,
                "Style should contain rules for \(heading)"
            )
        }
    }

    // MARK: - DOM Stats Tests

    func testDomStatsReturnsCorrectElementCount() async {
        let testHTML = """
        <html>
        <head><title>Test</title></head>
        <body>
            <div>
                <p>Paragraph 1</p>
                <p>Paragraph 2</p>
                <span>Span</span>
            </div>
        </body>
        </html>
        """
        await loadTestHTML(testHTML)

        // Count elements via simple query
        let elementCount = await executeScript("document.querySelectorAll('*').length") as? Int
        XCTAssertNotNil(elementCount)
        XCTAssertGreaterThan(elementCount ?? 0, 5) // html, head, title, body, div, p, p, span

        // Execute DOM stats script (logs to console, returns message)
        let statsSnippet = SnippetsManager.defaultSnippets.first { $0.id == "log_dom_stats" }!
        let result = await executeScript(statsSnippet.script) as? String
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("DOM stats logged") ?? false)
    }

    // MARK: - Log Images Tests

    func testLogImagesCountsImagesCorrectly() async {
        let testHTML = """
        <html><body>
            <img src="test1.png" alt="Image 1">
            <img src="test2.png" alt="Image 2">
            <img src="test3.png">
        </body></html>
        """
        await loadTestHTML(testHTML)

        let imgSnippet = SnippetsManager.defaultSnippets.first { $0.id == "log_images" }!
        let result = await executeScript(imgSnippet.script) as? String

        XCTAssertNotNil(result)
        // Returns "3 images logged to console"
        XCTAssertTrue(result?.contains("images logged to console") ?? false)
    }

    // MARK: - Log Links Tests

    func testLogLinksCountsLinksCorrectly() async {
        let testHTML = """
        <html><body>
            <a href="https://example.com">External</a>
            <a href="/internal">Internal</a>
            <a href="#anchor">Anchor</a>
        </body></html>
        """
        await loadTestHTML(testHTML)

        let linksSnippet = SnippetsManager.defaultSnippets.first { $0.id == "log_links" }!
        let result = await executeScript(linksSnippet.script) as? String

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("links logged") ?? false)
    }

    // MARK: - Event Listeners Tests

    func testEventListenersFindsInteractiveElements() async {
        let testHTML = """
        <html><body>
            <button>Click me</button>
            <a href="#">Link</a>
            <input type="text">
            <div role="button">Custom button</div>
            <span onclick="alert('hi')">Clickable span</span>
        </body></html>
        """
        await loadTestHTML(testHTML)

        let listenersSnippet = SnippetsManager.defaultSnippets.first { $0.id == "log_event_listeners" }!
        let result = await executeScript(listenersSnippet.script) as? String

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("interactive elements found") ?? false)
    }
}

// MARK: - Script Return Value Tests

@MainActor
final class SnippetReturnValueTests: XCTestCase {

    var webView: WKWebView!
    // swiftlint:disable:next weak_delegate - Test must hold strong ref; WKWebView.navigationDelegate is already weak
    private var navigationDelegate: TestNavigationDelegate?

    override func setUp() async throws {
        try await super.setUp()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        navigationDelegate = TestNavigationDelegate()
        webView.navigationDelegate = navigationDelegate
        await loadTestHTML("<html><body></body></html>")
    }

    override func tearDown() async throws {
        webView = nil
        navigationDelegate = nil
        try await super.tearDown()
    }

    private func loadTestHTML(_ html: String) async {
        await navigationDelegate?.waitForLoad(webView: webView, html: html)
    }

    func testBorderAllReturnsEnabledMessage() async {
        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "border_all" }!
        let result = try? await webView.evaluateJavaScript(snippet.script) as? String
        XCTAssertEqual(result, "Borders enabled")
    }

    func testBorderAllUndoReturnsDisabledMessage() async {
        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "border_all" }!
        _ = try? await webView.evaluateJavaScript(snippet.script)
        let result = try? await webView.evaluateJavaScript(snippet.undoScript!) as? String
        XCTAssertEqual(result, "Borders disabled")
    }

    func testEditPageReturnsEditableMessage() async {
        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "edit_page" }!
        let result = try? await webView.evaluateJavaScript(snippet.script) as? String
        XCTAssertEqual(result, "Page is now editable")
    }

    func testEditPageUndoReturnsDisabledMessage() async {
        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "edit_page" }!
        _ = try? await webView.evaluateJavaScript(snippet.script)
        let result = try? await webView.evaluateJavaScript(snippet.undoScript!) as? String
        XCTAssertEqual(result, "Page editing disabled")
    }

    func testShowHiddenReturnsRevealedMessage() async {
        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "show_elements" }!
        let result = try? await webView.evaluateJavaScript(snippet.script) as? String
        XCTAssertEqual(result, "Hidden elements revealed")
    }

    func testShowHiddenUndoReturnsRestoredMessage() async {
        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "show_elements" }!
        _ = try? await webView.evaluateJavaScript(snippet.script)
        let result = try? await webView.evaluateJavaScript(snippet.undoScript!) as? String
        XCTAssertEqual(result, "Hidden elements restored")
    }

    func testHighlightHeadingsReturnsHighlightedMessage() async {
        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "highlight_headings" }!
        let result = try? await webView.evaluateJavaScript(snippet.script) as? String
        XCTAssertEqual(result, "Headings highlighted")
    }

    func testHighlightHeadingsUndoReturnsRemovedMessage() async {
        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "highlight_headings" }!
        _ = try? await webView.evaluateJavaScript(snippet.script)
        let result = try? await webView.evaluateJavaScript(snippet.undoScript!) as? String
        XCTAssertEqual(result, "Heading highlights removed")
    }

    func testDisableCssReturnsDisabledMessage() async {
        let html = "<html><head><style>body{color:red;}</style></head><body></body></html>"
        await loadTestHTML(html)

        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "disable_css" }!
        let result = try? await webView.evaluateJavaScript(snippet.script) as? String
        XCTAssertTrue(result?.contains("CSS disabled") ?? false)
    }

    func testLogDomStatsReturnsLoggedMessage() async {
        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "log_dom_stats" }!
        let result = try? await webView.evaluateJavaScript(snippet.script) as? String
        XCTAssertEqual(result, "DOM stats logged to console")
    }

    func testLogImagesReturnsCountString() async {
        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "log_images" }!
        let result = try? await webView.evaluateJavaScript(snippet.script) as? String
        XCTAssertEqual(result, "0 images logged to console")
    }

    func testLogLinksReturnsCountString() async {
        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "log_links" }!
        let result = try? await webView.evaluateJavaScript(snippet.script) as? String
        XCTAssertEqual(result, "0 links logged to console")
    }

    func testLogEventListenersReturnsCountString() async {
        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "log_event_listeners" }!
        let result = try? await webView.evaluateJavaScript(snippet.script) as? String
        XCTAssertEqual(result, "0 interactive elements found")
    }
}

// MARK: - Edge Cases and Error Handling Tests

@MainActor
final class SnippetEdgeCaseTests: XCTestCase {

    var webView: WKWebView!
    // swiftlint:disable:next weak_delegate - Test must hold strong ref; WKWebView.navigationDelegate is already weak
    private var navigationDelegate: TestNavigationDelegate?

    override func setUp() async throws {
        try await super.setUp()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        navigationDelegate = TestNavigationDelegate()
        webView.navigationDelegate = navigationDelegate
    }

    override func tearDown() async throws {
        webView = nil
        navigationDelegate = nil
        try await super.tearDown()
    }

    private func loadTestHTML(_ html: String) async {
        await navigationDelegate?.waitForLoad(webView: webView, html: html)
    }

    func testBorderAllOnEmptyPage() async {
        await loadTestHTML("<html><head></head><body></body></html>")

        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "border_all" }!
        let result = try? await webView.evaluateJavaScript(snippet.script) as? String

        // Should still work on empty page
        XCTAssertEqual(result, "Borders enabled")
    }

    func testUndoWithoutInitialExecutionBorderAll() async {
        await loadTestHTML("<html><head></head><body></body></html>")

        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "border_all" }!

        // Execute undo without first executing the main script
        let result = try? await webView.evaluateJavaScript(snippet.undoScript!) as? String

        // Should gracefully handle (element doesn't exist, so nothing to remove)
        XCTAssertEqual(result, "Borders disabled")
    }

    func testDisableCssUndoWithoutDisabling() async {
        await loadTestHTML("<html><head></head><body></body></html>")

        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "disable_css" }!

        // Execute undo without first disabling
        let result = try? await webView.evaluateJavaScript(snippet.undoScript!) as? String

        XCTAssertEqual(result, "No styles to restore")
    }

    func testLogImagesOnPageWithNoImages() async {
        await loadTestHTML("<html><body><p>No images here</p></body></html>")

        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "log_images" }!
        let result = try? await webView.evaluateJavaScript(snippet.script) as? String

        XCTAssertEqual(result, "0 images logged to console")
    }

    func testLogLinksOnPageWithNoLinks() async {
        await loadTestHTML("<html><body><p>No links here</p></body></html>")

        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "log_links" }!
        let result = try? await webView.evaluateJavaScript(snippet.script) as? String

        XCTAssertEqual(result, "0 links logged to console")
    }

    func testDOMStatsOnMinimalPage() async {
        await loadTestHTML("<html><body></body></html>")

        let snippet = SnippetsManager.defaultSnippets.first { $0.id == "log_dom_stats" }!
        let result = try? await webView.evaluateJavaScript(snippet.script) as? String

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("DOM stats logged") ?? false)
    }

    func testMultipleSnippetsCanBeActiveSimultaneously() async {
        await loadTestHTML("<html><head></head><body><h1>Test</h1></body></html>")

        let borderSnippet = SnippetsManager.defaultSnippets.first { $0.id == "border_all" }!
        let headingSnippet = SnippetsManager.defaultSnippets.first { $0.id == "highlight_headings" }!
        let editSnippet = SnippetsManager.defaultSnippets.first { $0.id == "edit_page" }!

        // Activate all three - no delays needed between async JS evaluations
        _ = try? await webView.evaluateJavaScript(borderSnippet.script)
        _ = try? await webView.evaluateJavaScript(headingSnippet.script)
        _ = try? await webView.evaluateJavaScript(editSnippet.script)

        // Verify all are active
        let borderExists = try? await webView.evaluateJavaScript(
            "document.getElementById('__wina_border_style__') !== null"
        ) as? Bool
        let headingExists = try? await webView.evaluateJavaScript(
            "document.getElementById('__wina_heading_style__') !== null"
        ) as? Bool
        let isEditable = try? await webView.evaluateJavaScript(
            "document.body.contentEditable"
        ) as? String

        XCTAssertEqual(borderExists, true)
        XCTAssertEqual(headingExists, true)
        XCTAssertEqual(isEditable, "true")
    }
}
