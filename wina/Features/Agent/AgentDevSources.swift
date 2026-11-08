import Foundation

@MainActor
extension AgentDevTools {
    static func listSources(_ input: AgentDevInput, _ context: AgentDevContext) async throws -> [String: Any] {
        let section = try input.string("section") ?? "tree"
        let query = try input.string("query") ?? ""
        let raw = try input.bool("raw") ?? false
        guard ["tree", "html", "stylesheets", "scripts"].contains(section) else { throw AgentError("Invalid Sources section.") }
        if raw || section == "tree" || section == "html" || !query.isEmpty {
            try await context.confirm("Inspect \(section) from the current page on the Mac?")
        }
        let sources = SourcesManager()
        sources.setNavigator(context.navigator)
        let rows: [[String: Any]]
        switch section {
        case "tree":
            await sources.fetchDOMTree()
            guard let tree = sources.domTree else { throw AgentError(sources.errorMessage ?? "No DOM tree returned.") }
            rows = sourceNodes(tree, query: query)
        case "html":
            await sources.fetchRawHTML()
            guard let html = sources.rawHTML else { throw AgentError(sources.errorMessage ?? "No HTML returned.") }
            let lines = html.components(separatedBy: .newlines)
            let indices = query.isEmpty ? Array(lines.indices) : SourcesSearchHelper.findMatchingLineIndices(lines: lines, query: query)
            rows = indices.map { ["line": $0 + 1, "text": clipped(lines[$0], limit: 2048)] }
        case "stylesheets":
            await sources.fetchStylesheets()
            rows = sources.stylesheets.filter { sheet in
                query.isEmpty || [sheet.href, sheet.cssContent, sheet.mediaText].compactMap { $0 }
                    .contains { $0.localizedCaseInsensitiveContains(query) }
            }
            .map { sheet in
                var row: [String: Any] = ["index": sheet.index, "ruleCount": sheet.rulesCount, "external": sheet.isExternal]
                row["url"] = sheet.href.map { raw ? clipped($0) : safeURL($0) }
                row["media"] = raw ? sheet.mediaText : nil
                return row
            }
        default:
            await sources.fetchScripts()
            rows = sources.scripts.filter { script in
                query.isEmpty || [script.src, script.content].compactMap { $0 }
                    .contains { $0.localizedCaseInsensitiveContains(query) }
            }
            .map { script in
                var row: [String: Any] = [
                    "index": script.index, "external": script.isExternal,
                    "module": script.isModule, "async": script.isAsync, "defer": script.isDefer
                ]
                row["url"] = script.src.map { raw ? clipped($0) : safeURL($0) }
                return row
            }
        }
        try context.checkDocument()
        if let error = sources.errorMessage { throw AgentError(error) }
        return ["documentId": context.document.uuidString, "total": rows.count, "entries": Array(try paginate(input, rows))]
    }

    private static func sourceNodes(_ node: DOMNode, query: String) -> [[String: Any]] {
        var rows: [[String: Any]] = []
        func add(_ item: DOMNode) {
            if query.isEmpty || SourcesSearchHelper.nodeMatches(item, query: query) {
                var row: [String: Any] = [
                    "path": item.id, "type": item.nodeType, "name": item.nodeName, "children": item.children.count
                ]
                row["text"] = item.textContent
                rows.append(row)
            }
            for child in item.children { add(child) }
        }
        add(node)
        return rows
    }

    static func sourceDetail(_ input: AgentDevInput, _ context: AgentDevContext) async throws -> [String: Any] {
        if input.values["documentId"] != nil, try input.uuid("documentId") != context.document {
            throw AgentError("The Sources entry belongs to a different document. List the current Sources first.")
        }
        let kind = try input.required("kind")
        let query = try input.string("query") ?? ""
        let script: String
        switch kind {
        case "element":
            script = try elementDetailScript(input)
        case "stylesheet", "script":
            let index = try input.int("index", default: -1, range: 0...100_000)
            guard index >= 0 else { throw AgentError("A stylesheet or script index is required.") }
            script = kind == "stylesheet" ? StylesheetDetailView.detailScript(index: index) : ScriptDetailView.inlineContentScript(index: index)
        default:
            throw AgentError("Invalid Sources detail kind.")
        }
        try await context.confirm("Share the selected \(kind) details from this page with the Mac?")
        let data = await context.navigator.evaluateJavaScript(script)
        try context.checkDocument()
        let result = try parseJSON(data)
        return try sourceDetailResult(result, input, query: query)
    }

    private static func elementDetailScript(_ input: AgentDevInput) throws -> String {
        let pieces = try input.required("path").split(separator: ".", omittingEmptySubsequences: false)
        let path = pieces.compactMap { Int($0) }
        guard path.count == pieces.count, path.count <= 51, path.first == 0, path.allSatisfy({ $0 >= 0 }) else {
            throw AgentError("Use the element path returned by sources_list.")
        }
        let section = try input.string("section") ?? "attributes"
        switch section {
        case "attributes":
            return """
            (function() {
                const node = \(SourcesManager.nodeLookupScript(path: path));
                if (!node) return JSON.stringify({error: 'Element not found'});
                return JSON.stringify(Object.fromEntries(Array.from(node.attributes || []).map(attr => [attr.name, attr.value])));
            })();
            """
        case "computedStyles":
            return try input.bool("allComputedStyles") == true
                ? ElementDetailScripts.allComputedStyles(path: path) : ElementDetailScripts.computedStyles(path: path)
        case "matchedRules":
            return ElementDetailScripts.matchedRules(path: path)
        case "html":
            return ElementDetailScripts.htmlContent(path: path)
        default:
            throw AgentError("Invalid element detail section.")
        }
    }

    private static func sourceDetailResult(_ result: Any, _ input: AgentDevInput, query: String) throws -> [String: Any] {
        if let object = result as? [String: Any] {
            if let error = object["error"] as? String { throw AgentError(error) }
            if let rules = object["rules"] as? [[String: String]] {
                let filtered = rules.filter { row in
                    query.isEmpty || row.values.contains { $0.localizedCaseInsensitiveContains(query) }
                }
                let page = try paginate(input, filtered).map { $0.mapValues { clipped($0, limit: 2048) } }
                var payload: [String: Any] = ["total": filtered.count, "rules": page]
                if let raw = object["raw"] as? String { payload["raw"] = clipped(raw, limit: 32_768) }
                return payload
            }
            let rows = object.keys.sorted().compactMap { key -> [String: String]? in
                guard let value = object[key] as? String,
                      query.isEmpty || key.localizedCaseInsensitiveContains(query)
                        || value.localizedCaseInsensitiveContains(query) else { return nil }
                return ["key": key, "value": clipped(value, limit: 8192)]
            }
            return ["total": rows.count, "entries": Array(try paginate(input, rows))]
        }
        guard let rules = result as? [[String: Any]] else { throw AgentError("No Sources details returned.") }
        let rows = rules.filter { row in
            query.isEmpty || (row["selector"] as? String)?.localizedCaseInsensitiveContains(query) == true
        }
        let page = try paginate(input, rows).map { row -> [String: Any] in
            var entry = row
            entry["properties"] = (row["properties"] as? [[String: Any]])?.prefix(50).map { property in
                var clippedProperty = property
                clippedProperty["v"] = (property["v"] as? String).map { clipped($0, limit: 256) }
                return clippedProperty
            }
            return entry
        }
        return ["total": rows.count, "rules": page]
    }
}
