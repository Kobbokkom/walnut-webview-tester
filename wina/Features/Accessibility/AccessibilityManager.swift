//
//  AccessibilityManager.swift
//  wina
//
//  Accessibility audit manager that persists results across sheet dismissals.
//

import Foundation
import Observation
import WebKit

// MARK: - Accessibility Manager

/// sheet 닫혀도 audit 결과 유지하는 매니저
@Observable
class AccessibilityManager {
    @MainActor static let auditWorld = WKContentWorld.world(name: "WalnutAccessibility")
    var issues: [AccessibilityIssue] = []
    var isScanning: Bool = false
    var hasScanned: Bool = false
    private(set) var hasUntestedFrames = false
    private(set) var auditedURL: String?
    private(set) var auditedDocumentID: UUID?
    private(set) var auditedAt: Date?
    var errorMessage: String?
    var filterSeverity: AccessibilityIssue.Severity?
    var searchText: String = ""

    // 결과 초기화
    func clear() {
        issues = []
        hasScanned = false
        hasUntestedFrames = false
        auditedURL = nil
        auditedDocumentID = nil
        auditedAt = nil
        errorMessage = nil
        filterSeverity = nil
        searchText = ""
    }

    @MainActor
    func runAudit(navigator: WebViewNavigator) async {
        guard !isScanning else { return }
        let document = navigator.documentID
        isScanning = true
        issues = []
        hasScanned = false
        hasUntestedFrames = false
        auditedURL = nil
        auditedDocumentID = nil
        auditedAt = nil
        errorMessage = nil
        defer { isScanning = false }

        do {
            let axeLoaded = try await navigator.evaluateJavaScriptReportingErrors(
                "typeof axe !== 'undefined'", contentWorld: Self.auditWorld
            ) as? Bool ?? false
            guard navigator.documentID == document, !Task.isCancelled else { return }
            if !axeLoaded {
                guard let url = Bundle.main.url(forResource: "axe.min", withExtension: "js"),
                      let script = try? String(contentsOf: url, encoding: .utf8) else {
                    errorMessage = "Could not load the accessibility checker. Try again."
                    return
                }
                // Axe's frame messages cross WKContentWorld boundaries. Do not accept page-world replies.
                let localScript = script + "\n;axe.configure({allowedOrigins: []}); void 0;"
                _ = try await navigator.evaluateJavaScriptReportingErrors(localScript, contentWorld: Self.auditWorld)
            }

            guard navigator.documentID == document, !Task.isCancelled else { return }
            let script = """
            const results = await axe.run(document, {iframes: false});
            return JSON.stringify({violations: results.violations, hasUntestedFrames: window.length > 0});
            """
            let result = try await navigator.callAsyncJavaScriptReportingErrors(script, contentWorld: Self.auditWorld)
            guard navigator.documentID == document, !Task.isCancelled else { return }
            guard let json = result as? String,
                  let report = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                  let violations = report["violations"] as? [[String: Any]],
                  let hasUntestedFrames = report["hasUntestedFrames"] as? Bool else {
                throw AgentError("No accessibility results were returned.")
            }
            issues = parseAxeViolations(violations)
            self.hasUntestedFrames = hasUntestedFrames
            auditedDocumentID = document
            auditedURL = navigator.attachedPageURL?.absoluteString
            auditedAt = Date()
            hasScanned = true
        } catch {
            guard navigator.documentID == document, !Task.isCancelled else { return }
            errorMessage = "Could not scan this page. Check that JavaScript is enabled and the page is loaded, then try again."
        }
    }

    func report(for issues: [AccessibilityIssue]) -> String {
        var lines: [String] = []

        // Header
        lines.append("# Accessibility Audit Report")
        lines.append("")
        if let url = auditedURL {
            lines.append("URL: \(url)")
        }
        if let date = auditedAt {
            lines.append("Date: \(date.formatted(date: .abbreviated, time: .shortened))")
        }
        if hasScanned {
            lines.append("Scope: Main frame only")
            if hasUntestedFrames { lines.append("Embedded frames were skipped.") }
        }
        lines.append("")

        // Summary
        let issueCountBySeverity = Dictionary(grouping: issues, by: \.severity).mapValues(\.count)
        let errorCount = issueCountBySeverity[.error] ?? 0
        let warningCount = issueCountBySeverity[.warning] ?? 0
        let infoCount = issueCountBySeverity[.info] ?? 0
        lines.append("## Summary")
        lines.append("- Errors: \(errorCount)")
        lines.append("- Warnings: \(warningCount)")
        lines.append("- Info: \(infoCount)")
        lines.append("- Total: \(issues.count)")
        lines.append("")

        // Issues by severity
        for severity in AccessibilityIssue.Severity.allCases {
            let severityIssues = issues.filter { $0.severity == severity }
            if severityIssues.isEmpty { continue }

            lines.append("## \(severity.label) (\(severityIssues.count))")
            lines.append("")

            for (index, issue) in severityIssues.enumerated() {
                lines.append("### \(index + 1). \(issue.help)")
                if let ruleId = issue.ruleId {
                    lines.append("- Rule: \(ruleId)")
                }
                lines.append("- Category: \(issue.category.label)")
                if !issue.failureSummary.isEmpty {
                    lines.append("- Details: \(issue.failureSummary)")
                }
                if let selector = issue.selector {
                    lines.append("- Selector: \(selector)")
                }
                lines.append("- HTML: \(issue.fullHtml)")
                if let helpUrl = issue.helpUrl {
                    lines.append("- Help: \(helpUrl)")
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
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
