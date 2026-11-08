import Foundation

@MainActor
extension AgentDevTools {
    static let pageTools: [[String: Any]] = [
        AgentTool.definition("sources_list", "Inspect DOM tree, raw HTML, stylesheets, or scripts. DOM and source data require confirmation.", [
            "section": options(["tree", "html", "stylesheets", "scripts"]), "query": query,
            "raw": raw, "offset": offset, "limit": limit
        ]),
        AgentTool.definition("sources_detail", "Read an element path, stylesheet index, or inline script index from sources_list. Requires confirmation.", [
            "kind": options(["element", "stylesheet", "script"]), "path": query,
            "index": offset, "section": options(["attributes", "computedStyles", "matchedRules", "html"]),
            "allComputedStyles": flag, "query": query, "documentId": identifier, "offset": offset, "limit": limit
        ], required: ["kind"]),
        AgentTool.definition("performance_read", "Collect metrics, resource timings, or navigation timings. Reload and capture a fresh run with reload=true.", [
            "section": options(["all", "metrics", "resources", "timing"]), "reload": flag,
            "collect": flag, "query": query, "resourceType": options(ResourceType.self),
            "raw": raw, "offset": offset, "limit": limit
        ]),
        AgentTool.definition("performance_clear", "Clear collected Performance data. Requires confirmation.", [:]),
        AgentTool.definition("accessibility_audit", "Run the axe-core audit or read retained results. Page text and markup require confirmation.", [
            "run": flag, "severity": options(AccessibilityIssue.Severity.self),
            "category": options(AccessibilityIssue.Category.self), "query": query, "raw": raw,
            "offset": offset, "limit": limit
        ]),
        AgentTool.definition("accessibility_detail", "Read the selected axe issue's full details. Requires confirmation.", [
            "id": identifier
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
        ], required: ["action"])
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
            try await context.confirm("Share the selected accessibility issue and its markup with the Mac?")
            guard let issue = navigator.accessibilityManager.issues.first(where: { $0.id == id }) else {
                throw AgentError("Accessibility issue not found.")
            }
            var row = issueRecord(issue, includeContent: true)
            row["documentId"] = navigator.accessibilityManager.auditedDocumentID?.uuidString
            return row
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
            _ = await navigator.evaluateJavaScript(SearchTextOverlay.clearScript)
            try context.checkDocument()
            return ["cleared": true]
        default:
            throw AgentError("Unknown search action.")
        }
        let result = await navigator.evaluateJavaScript(script)
        try context.checkDocument()
        return try parseJSON(result)
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
        if reload || collect {
            guard !manager.isLoading else { throw AgentError("A Performance collection is already running.") }
            await manager.collect(using: navigator, reload: reload)
            if let error = manager.lastError { throw AgentError(error) }
        }
        if !reload { try context.checkDocument() }
        try Task.checkCancellation()
        guard navigator.isAttached else { throw AgentError("The WKWebView was disconnected.") }
        if raw {
            let sharing = AgentDevContext(navigator: navigator, authorize: context.authorize)
            try await sharing.confirm("Share captured resource URLs from Performance with the Mac?")
        }
        let data = manager.data
        var result: [String: Any] = ["documentId": navigator.documentID.uuidString]
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
        if includeContent || !query.isEmpty {
            try await context.confirm("Share or search details from Walnut's accessibility results on the Mac?")
        }
        if try input.bool("run") ?? true {
            guard !manager.isScanning else { throw AgentError("An accessibility audit is already running.") }
            await manager.runAudit(navigator: context.navigator)
            try context.checkDocument()
            if let error = manager.errorMessage { throw AgentError(error) }
        }
        let issues = manager.issues.filter { issue in
            (severity == nil || issue.severity == severity) && (category == nil || issue.category == category) &&
                (query.isEmpty || [issue.help, issue.failureSummary, issue.element, issue.selector ?? ""]
                    .contains { $0.localizedCaseInsensitiveContains(query) })
        }
        var result: [String: Any] = [
            "total": issues.count, "hasScanned": manager.hasScanned,
            "issues": try paginate(input, issues).map { issueRecord($0, includeContent: includeContent) }
        ]
        result["documentId"] = manager.auditedDocumentID?.uuidString
        result["timestamp"] = manager.auditedAt?.timeIntervalSince1970
        return result
    }

    private static func issueRecord(_ issue: AccessibilityIssue, includeContent: Bool) -> [String: Any] {
        var row: [String: Any] = [
            "id": issue.id.uuidString, "severity": issue.severity.rawValue, "category": issue.category.rawValue
        ]
        row["ruleId"] = issue.ruleId
        if includeContent {
            row["help"] = clipped(issue.help)
            row["failure"] = clipped(issue.failureSummary)
            row["html"] = clipped(issue.fullHtml)
            row["selector"] = issue.selector.map { clipped($0) }
            row["helpUrl"] = issue.helpUrl
        }
        return row
    }
}
