//
//  AccessibilityManager.swift
//  wina
//
//  Accessibility audit manager that persists results across sheet dismissals.
//

import Foundation
import Observation

// MARK: - Accessibility Manager

/// sheet 닫혀도 audit 결과 유지하는 매니저
@Observable
class AccessibilityManager {
    var issues: [AccessibilityIssue] = []
    var isScanning: Bool = false
    var hasScanned: Bool = false
    var errorMessage: String?
    var filterSeverity: AccessibilityIssue.Severity?
    var searchText: String = ""

    // 결과 초기화
    func clear() {
        issues = []
        hasScanned = false
        errorMessage = nil
        filterSeverity = nil
        searchText = ""
    }

    @MainActor
    func runAudit(navigator: WebViewNavigator) async {
        guard !isScanning else { return }
        isScanning = true
        issues = []
        hasScanned = false
        errorMessage = nil
        defer { isScanning = false }

        let axeLoaded = await navigator.evaluateJavaScript("typeof axe !== 'undefined'") as? Bool ?? false
        if !axeLoaded {
            guard let url = Bundle.main.url(forResource: "axe.min", withExtension: "js"),
                  let script = try? String(contentsOf: url, encoding: .utf8) else {
                errorMessage = "Could not load the accessibility checker. Try again."
                return
            }
            _ = await navigator.evaluateJavaScript(script)
        }

        let script = """
        const results = await axe.run();
        return JSON.stringify(results.violations);
        """
        guard let result = await navigator.callAsyncJavaScript(script) as? String,
              let data = result.data(using: .utf8),
              let violations = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            errorMessage = "Could not scan this page. Check that JavaScript is enabled and the page is loaded, then try again."
            return
        }
        issues = parseAxeViolations(violations)
        hasScanned = true
    }

    // axe-core violations 파싱
    func parseAxeViolations(_ violations: [[String: Any]]) -> [AccessibilityIssue] {
        var result: [AccessibilityIssue] = []

        for violation in violations {
            guard let ruleId = violation["id"] as? String,
                  let impact = violation["impact"] as? String,
                  let help = violation["help"] as? String,
                  let nodes = violation["nodes"] as? [[String: Any]] else {
                continue
            }

            let tags = violation["tags"] as? [String] ?? []
            let helpUrl = violation["helpUrl"] as? String
            let severity = AccessibilityIssue.Severity.from(impact: impact)
            let category = AccessibilityIssue.Category.from(tags: tags, ruleId: ruleId)

            for node in nodes {
                let fullHtml = node["html"] as? String ?? ""
                let targets = node["target"] as? [String] ?? []
                let selector = targets.first
                let failureSummary = node["failureSummary"] as? String ?? ""

                // 축약된 element (collapsed 상태용)
                let element = fullHtml.count > 60 ? String(fullHtml.prefix(60)) + "..." : fullHtml

                result.append(AccessibilityIssue(
                    severity: severity,
                    category: category,
                    help: help,
                    failureSummary: failureSummary,
                    element: element,
                    fullHtml: fullHtml,
                    selector: selector,
                    helpUrl: helpUrl,
                    ruleId: ruleId
                ))
            }
        }

        return result
    }
}
