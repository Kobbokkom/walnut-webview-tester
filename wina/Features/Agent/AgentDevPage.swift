import CryptoKit
import Foundation

@MainActor
extension AgentDevTools {
    static let pageTools: [[String: Any]] = [
        AgentTool.definition("sources_list", "Inspect DOM tree, serialized live DOM HTML, stylesheets, or scripts. DOM and source data require confirmation.", [
            "section": options(["tree", "html", "stylesheets", "scripts"]), "query": query,
            "raw": raw, "documentId": identifier, "offset": offset, "limit": limit, "textOffset": sourceTextOffset
        ]),
        AgentTool.definition("sources_detail", "Read an element path, stylesheet index, or script index from sources_list. External source requests obey the page's network policy. Requires confirmation.", [
            "kind": options(["element", "stylesheet", "script"]), "path": query,
            "index": offset, "section": options(["attributes", "computedStyles", "matchedRules", "html"]),
            "allComputedStyles": flag, "query": query, "documentId": identifier,
            "offset": offset, "limit": limit, "textOffset": sourceTextOffset,
            "propertyOffset": offset.merging(["description": "Offset in each matched rule's properties. Follow nextPropertyOffset."]) { _, description in description }
        ], required: ["kind"]),
        AgentTool.definition("performance_read", "Collect metrics, resource timings, or navigation timings. Reload and capture a fresh run with reload=true. Use collect=false to read an existing measurement.", [
            "section": options(["all", "metrics", "resources", "timing"]), "reload": flag,
            "collect": flag, "query": query, "resourceType": options(ResourceType.self),
            "raw": raw, "offset": offset, "limit": limit
        ]),
        AgentTool.definition("performance_clear", "Clear collected Performance data. Requires confirmation.", [:]),
        AgentTool.definition("accessibility_audit", "Run the main-frame axe-core audit or read retained results. Markdown report export and page content require confirmation.", [
            "run": flag, "severity": options(AccessibilityIssue.Severity.self),
            "category": options(AccessibilityIssue.Category.self), "query": query, "raw": raw,
            "offset": offset, "limit": limit, "format": options(["entries", "markdown"]),
            "exportId": identifier,
            "exportOffset": [
                "type": "integer", "minimum": 0, "maximum": Int(Int32.max),
                "description": "Follow nextExportOffset with exportId and the same filters to read the retained Markdown report."
            ]
        ]),
        AgentTool.definition("accessibility_detail", "Read the selected axe issue's full details. For a large record, concatenate the content chunks and parse them as JSON. Pass nextByteOffset as byteOffset with contentId and the same ID. Requires confirmation.", [
            "id": identifier, "byteOffset": exportByteOffset, "contentId": identifier
        ], required: ["id"]),
        AgentTool.definition("accessibility_clear", "Clear retained accessibility results. Requires confirmation.", [:]),
        AgentTool.definition("snippets_list", "List Walnut's preset JavaScript snippets and their current states.", [
            "category": options(SnippetCategory.self), "query": query
        ]),
        AgentTool.definition("snippets_run", "Run or toggle a built-in snippet by ID. Set enabled to choose the state instead of toggling. Requires confirmation.", [
            "id": identifier, "enabled": flag
        ], required: ["id"]),
        AgentTool.definition("snippets_reset", "Undo all active built-in snippets. Requires confirmation.", [:]),
        AgentTool.definition("page_search", "Find and highlight text, move to the next or previous result, or clear highlights.", [
            "action": options(["find", "next", "previous", "clear"]), "query": query
        ], required: ["action"]),
        pageInteractionTool
    ]

    static func callPage(_ tool: String, _ input: AgentDevInput, _ context: AgentDevContext) async throws -> Any {
        let navigator = context.navigator
        switch tool {
        case "sources_list":
            return try await listSources(input, context)
        case "sources_detail":
            return try await sourceDetail(input, context)
        case "performance_read":
            return try await readPerformance(input, context)
        case "performance_clear":
            try await context.confirm("Clear Walnut's Performance results?")
            guard !navigator.performanceManager.isLoading else { throw AgentError("A Performance collection is running.") }
            navigator.performanceManager.clear()
            return ["cleared": true]
        case "accessibility_audit":
            return try await accessibilityAudit(input, context)
        case "accessibility_detail":
            let id = try input.uuid("id")
            let cursor = try exportCursor(input, source: "Accessibility issue")
            try await context.confirm("Share the selected accessibility issue and its markup with the Mac?")
            guard let issue = navigator.accessibilityManager.issues.first(where: { $0.id == id }) else {
                throw AgentError("Accessibility issue not found.")
            }
            var row = issueRecord(issue, includeContent: true, fullContent: true)
            row["documentId"] = navigator.accessibilityManager.auditedDocumentID?.uuidString
            var result = try exportRecord(row, cursor: cursor, source: "Accessibility issue")
            result["documentId"] = row["documentId"]
            return result
        case "accessibility_clear":
            try await context.confirm("Clear Walnut's accessibility audit results?")
            guard !navigator.accessibilityManager.isScanning else { throw AgentError("An accessibility scan is running.") }
            navigator.accessibilityManager.clear()
            return ["cleared": true]
        case "snippets_list":
            let category = try input.option("category", as: SnippetCategory.self) ?? .all
            let query = try input.string("query") ?? ""
            return SnippetsManager.defaultSnippets.filter { snippet in
                (category == .all || snippet.category == category) &&
                    (query.isEmpty || snippet.name.localizedCaseInsensitiveContains(query)
                        || snippet.description.localizedCaseInsensitiveContains(query))
            }
            .map { snippet -> [String: Any] in
                [
                    "id": snippet.id, "name": snippet.name, "description": snippet.description,
                    "category": snippet.category.rawValue, "toggleable": snippet.isToggleable,
                    "active": navigator.snippetsManager.isActive(snippet.id)
                ]
            }
        case "snippets_run":
            let id = try input.required("id")
            let enabled = try input.bool("enabled")
            guard let snippet = SnippetsManager.defaultSnippets.first(where: { $0.id == id }) else {
                throw AgentError("Unknown Walnut snippet.")
            }
            guard enabled == nil || snippet.isToggleable else {
                throw AgentError("This snippet does not have an enabled state.")
            }
            try await context.confirm("Run Walnut's \(snippet.name) snippet on this page?")
            let enable = enabled ?? !navigator.snippetsManager.isActive(id)
            let result = try await navigator.snippetsManager.execute(snippet, using: navigator, enabled: enable)
            try context.checkDocument()
            return ["result": result, "active": navigator.snippetsManager.isActive(id)] as [String: Any]
        case "snippets_reset":
            try await context.confirm("Undo Walnut's active snippets on this page?")
            try await navigator.snippetsManager.undoAll(using: navigator)
            try context.checkDocument()
            return ["reset": true]
        case "page_search":
            return try await searchPage(input, context)
        case "page_interact":
            return try await interactWithPage(input, context)
        default:
            throw AgentError("Unknown DevTools tool.")
        }
    }

    private static func searchPage(_ input: AgentDevInput, _ context: AgentDevContext) async throws -> Any {
        let navigator = context.navigator
        let action = try input.required("action")
        let script: String
        switch action {
        case "find":
            let query = try input.required("query")
            guard let search = SearchTextOverlay.searchScript(for: query) else {
                throw AgentError("Could not encode the search query.")
            }
            try await context.confirm("Find and highlight text on the current page and share the match count with the Mac?")
            script = search
        case "next":
            script = SearchTextOverlay.nextScript
        case "previous":
            script = SearchTextOverlay.previousScript
        case "clear":
            do {
                _ = try await navigator.evaluateJavaScriptReportingErrors(SearchTextOverlay.clearScript)
            } catch {
                try context.checkDocument()
                throw AgentError("Could not clear page search highlights.")
            }
            try context.checkDocument()
            return ["cleared": true]
        default:
            throw AgentError("Unknown search action.")
        }
        let result = await navigator.evaluateJavaScript(script)
        try context.checkDocument()
        guard let values = (try? parseJSON(result)) as? [String: Any],
              let index = try? AgentDevInput(values: values).int("index", default: -1, range: 0...Int.max),
              index >= 0 else {
            throw AgentError("Invalid page search result.")
        }
        guard action == "find" else { return ["index": index] }
        guard let count = try? AgentDevInput(values: values).int("count", default: -1, range: 0...Int.max),
              count >= 0, index < max(1, count) else {
            throw AgentError("Invalid page search result.")
        }
        return ["count": count, "index": index]
    }

    private static func readPerformance(_ input: AgentDevInput, _ context: AgentDevContext) async throws -> [String: Any] {
        let section = try input.string("section") ?? "all"
        guard ["all", "metrics", "resources", "timing"].contains(section) else {
            throw AgentError("Invalid Performance section.")
        }
        let navigator = context.navigator
        let manager = navigator.performanceManager
        let raw = try input.bool("raw") ?? false
        let reload = try input.bool("reload") ?? false
        let collect = try input.bool("collect") ?? true
        let type = try input.option("resourceType", as: ResourceType.self)
        let query = try input.string("query") ?? ""
        guard !manager.isLoading else { throw AgentError("A Performance collection is already running.") }
        let measuredDocument: UUID? = if reload || collect {
            await manager.collect(using: navigator, reload: reload)
        } else {
            context.document
        }
        try Task.checkCancellation()
        if !reload { try context.checkDocument() }
        guard !manager.isLoading else { throw AgentError("A Performance collection is already running.") }
        if let error = manager.lastError { throw AgentError(error) }
        let data = manager.data
        guard let measuredDocument, data.navigation != nil || !data.paints.isEmpty else {
            throw AgentError("No Performance measurement is available. Collect performance data first.")
        }
        let sharing = AgentDevContext(navigator: navigator, authorize: context.authorize)
        guard navigator.isAttached, sharing.document == measuredDocument else {
            throw AgentError("The active WKWebView document changed. Try again.")
        }
        if raw {
            try await sharing.confirm("Share captured resource URLs from Performance with the Mac?")
        }
        if reload, navigator.agentNavigation.documentID != measuredDocument {
            throw AgentError("A different navigation interrupted the Performance refresh.")
        }
        var result: [String: Any] = ["documentId": measuredDocument.uuidString]
        if section == "all" || section == "metrics" {
            result["score"] = data.totalScore
            result["rating"] = data.scoreRating.rawValue
            result["coreWebVitalsPass"] = data.coreWebVitalsPass
            result["lcpMs"] = data.largestContentfulPaint
            result["firstPaintMs"] = data.firstPaint
            result["firstContentfulPaintMs"] = data.firstContentfulPaint
            result["cls"] = data.cls >= 0 ? data.cls : nil
            result["tbtMs"] = data.tbt >= 0 ? data.tbt : nil
            result["ttfbMs"] = data.navigation?.ttfb
        }
        if section == "all" || section == "timing" {
            result["navigation"] = try data.navigation.map(AgentTool.json)
            result["paints"] = try AgentTool.json(data.paints)
        }
        if section == "all" || section == "resources" {
            let resources = data.resources.filter { entry in
                let url = raw ? entry.name : safeURL(entry.name)
                return (type == nil || type == entry.resourceType) &&
                    (query.isEmpty || url.localizedCaseInsensitiveContains(query))
            }
            result["resourceCount"] = resources.count
            result["resources"] = try paginate(input, resources).map { entry -> [String: Any] in
                [
                    "id": entry.id.uuidString, "url": raw ? clipped(entry.name) : safeURL(entry.name),
                    "type": entry.resourceType.rawValue, "startMs": entry.startTime, "durationMs": entry.duration,
                    "transferBytes": entry.transferSize, "encodedBytes": entry.encodedBodySize, "decodedBytes": entry.decodedBodySize
                ]
            }
        }
        return result
    }

    private static func accessibilityAudit(_ input: AgentDevInput, _ context: AgentDevContext) async throws -> [String: Any] {
        let manager = context.navigator.accessibilityManager
        let severity = try input.option("severity", as: AccessibilityIssue.Severity.self)
        let category = try input.option("category", as: AccessibilityIssue.Category.self)
        let query = try input.string("query") ?? ""
        let includeContent = try input.bool("raw") ?? false
        let export = try input.string("format") == "markdown"
        let exportOffset = try input.int("exportOffset", default: 0, range: 0...Int(Int32.max))
        let exportID = try input.string("exportId", maxLength: 64)
        let shouldRun = try input.bool("run") ?? (exportOffset == 0)
        guard exportOffset == 0 ? exportID == nil : (export && !shouldRun && exportID != nil) else {
            throw AgentError("Continue the retained Markdown report with its exportId, without rerunning the audit.")
        }
        if export {
            try await context.confirm("Export Walnut's accessibility report, including its page URL and markup, to the Mac?")
        } else if includeContent || !query.isEmpty {
            try await context.confirm("Share or search details from Walnut's accessibility results on the Mac?")
        }
        if shouldRun {
            guard !manager.isScanning else { throw AgentError("An accessibility audit is already running.") }
            await manager.runAudit(navigator: context.navigator)
            try context.checkDocument()
            if let error = manager.errorMessage { throw AgentError(error) }
        }
        let issues = manager.issues.filter { issue in
            (severity == nil || issue.severity == severity) && (category == nil || issue.category == category) &&
                (issue.matchesSearch(query) || issue.failureSummary.localizedCaseInsensitiveContains(query)
                    || issue.selector?.localizedCaseInsensitiveContains(query) == true)
        }
        var result: [String: Any] = [
            "total": issues.count, "hasScanned": manager.hasScanned,
            "issues": try paginate(input, issues).map { issueRecord($0, includeContent: includeContent) }
        ]
        result["documentId"] = manager.auditedDocumentID?.uuidString
        result["timestamp"] = manager.auditedAt?.timeIntervalSince1970
        if manager.hasScanned {
            result["scope"] = "main-frame"
            result["hasUntestedFrames"] = manager.hasUntestedFrames
        }
        if export {
            let report = Data(manager.report(for: issues).utf8)
            let id = SHA256.hash(data: report).map { String(format: "%02x", $0) }.joined()
            guard exportID == nil || exportID == id else {
                throw AgentError("The Markdown report changed. Start exporting it again.")
            }
            let remaining = report.dropFirst(exportOffset)
            guard exportOffset <= report.count, remaining.first.map({ $0 & 0xc0 != 0x80 }) ?? true else {
                throw AgentError("Invalid Markdown report offset. Use nextExportOffset from the same audit.")
            }
            let bytes = remaining.prefix(256 * 1024)
            let part = (0...3).lazy.compactMap { String(bytes: bytes.dropLast($0), encoding: .utf8) }.first ?? ""
            let next = exportOffset + part.utf8.count
            result["export"] = part
            result["exportId"] = id
            result["exportTruncated"] = next < report.count
            if next < report.count { result["nextExportOffset"] = next }
        }
        return result
    }

    private static func issueRecord(_ issue: AccessibilityIssue, includeContent: Bool, fullContent: Bool = false) -> [String: Any] {
        func content(_ value: String) -> String { fullContent ? value : clipped(value) }
        var row: [String: Any] = [
            "id": issue.id.uuidString, "severity": issue.severity.rawValue, "category": issue.category.rawValue
        ]
        row["ruleId"] = issue.ruleId
        if includeContent {
            row["help"] = content(issue.help)
            row["failure"] = content(issue.failureSummary)
            row["html"] = content(issue.fullHtml)
            row["selector"] = issue.selector.map(content)
            row["helpUrl"] = issue.helpUrl
        }
        return row
    }
}
