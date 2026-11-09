import Foundation

@MainActor
extension AgentDevTools {
    static let sourceTextOffset = [
        "type": "integer", "minimum": 0, "maximum": Int(Int32.max),
        "description": "Unicode scalar offset within each source text. Follow nextTextOffset (nextRawTextOffset for raw CSS). When omitted, searches start at the matching text."
    ] as [String: Any]

    static func listSources(_ input: AgentDevInput, _ context: AgentDevContext) async throws -> [String: Any] {
        try checkSourceDocument(input, context)
        let section = try input.string("section") ?? "tree"
        let query = try input.string("query") ?? ""
        let raw = try input.bool("raw") ?? false
        let textOffset = try sourceTextStart(input)
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
            try context.checkDocument()
            let page = try paginate(input, indices).map { index -> [String: Any] in
                var row: [String: Any] = ["line": index + 1]
                addSourceText(lines[index], to: &row, key: "text", offset: textOffset, query: query)
                return row
            }
            return ["documentId": context.document.uuidString, "total": indices.count, "entries": page]
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
        try checkSourceDocument(input, context)
        let kind = try input.required("kind")
        let query = try input.string("query") ?? ""
        let script: String
        switch kind {
        case "element":
            script = try elementDetailScript(input)
        case "stylesheet", "script":
            let index = try input.int("index", default: -1, range: 0...100_000)
            guard index >= 0 else { throw AgentError("A stylesheet or script index is required.") }
            script = kind == "stylesheet" ? StylesheetDetailView.detailScript(index: index)
                : ScriptDetailView.inlineContentScript(index: index, maxLength: nil)
        default:
            throw AgentError("Invalid Sources detail kind.")
        }
        try await context.confirm("Share the selected \(kind) details from this page with the Mac?")
        let data = await context.navigator.evaluateJavaScript(script)
        try context.checkDocument()
        let result = try parseJSON(data)
        var payload = try sourceDetailResult(result, input, query: query)
        payload["documentId"] = context.document.uuidString
        return payload
    }

    private static func checkSourceDocument(_ input: AgentDevInput, _ context: AgentDevContext) throws {
        if input.values["documentId"] != nil, try input.uuid("documentId") != context.document {
            throw AgentError("The Sources entry belongs to a different document. List the current Sources first.")
        }
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
                const attributes = Object.fromEntries(Array.from(node.attributes || []).map(attr => [attr.name, attr.value]));
                return JSON.stringify({attributes});
            })();
            """
        case "computedStyles":
            return try input.bool("allComputedStyles") == true
                ? ElementDetailScripts.allComputedStyles(path: path) : ElementDetailScripts.computedStyles(path: path)
        case "matchedRules":
            return ElementDetailScripts.matchedRules(path: path)
        case "html":
            return ElementDetailScripts.htmlContent(path: path, maxLength: nil)
        default:
            throw AgentError("Invalid element detail section.")
        }
    }

    private static func sourceDetailResult(_ result: Any, _ input: AgentDevInput, query: String) throws -> [String: Any] {
        let textOffset = try sourceTextStart(input)
        if let object = result as? [String: Any] {
            if let error = object["error"] as? String { throw AgentError(error) }
            if let rules = object["rules"] as? [[String: String]] {
                let filtered = rules.filter { row in
                    query.isEmpty || row.values.contains { $0.localizedCaseInsensitiveContains(query) }
                }
                let page = try paginate(input, filtered).map { rule -> [String: Any] in
                    var row: [String: Any] = ["selector": rule["selector"].map { clipped($0, limit: 2048) } ?? ""]
                    if let text = rule["text"] {
                        addSourceText(text, to: &row, key: "text", offset: textOffset, query: query)
                    }
                    return row
                }
                var payload: [String: Any] = ["total": filtered.count, "rules": page]
                if let raw = object["raw"] as? String {
                    addSourceText(raw, to: &payload, key: "raw", offset: textOffset, query: query, limit: 32_768)
                }
                return payload
            }
            let values = object["attributes"] as? [String: String] ?? object.compactMapValues { $0 as? String }
            let keys = values.keys.sorted().filter { key in
                query.isEmpty || key.localizedCaseInsensitiveContains(query)
                    || values[key]?.localizedCaseInsensitiveContains(query) == true
            }
            let page = try paginate(input, keys).map { key -> [String: Any] in
                var row: [String: Any] = ["key": key]
                if let value = values[key] {
                    addSourceText(value, to: &row, key: "value", offset: textOffset, query: query, limit: 8192)
                }
                return row
            }
            return ["total": keys.count, "entries": page]
        }
        guard let rules = result as? [[String: Any]] else { throw AgentError("No Sources details returned.") }
        let rows = rules.filter { row in
            query.isEmpty || (row["selector"] as? String)?.localizedCaseInsensitiveContains(query) == true
        }
        let propertyOffset = try input.int("propertyOffset", default: 0, range: 0...100_000)
        let page = try paginate(input, rows).map { row -> [String: Any] in
            var entry = row
            if let properties = row["properties"] as? [[String: Any]] {
                let page = properties.dropFirst(propertyOffset).prefix(50)
                entry["properties"] = page.map { property in
                    var property = property
                    if let value = property["v"] as? String {
                        addSourceText(value, to: &property, key: "v", offset: textOffset, query: query, limit: 256)
                    }
                    return property
                }
                let end = propertyOffset + page.count
                if end < properties.count { entry["nextPropertyOffset"] = end }
            }
            return entry
        }
        return ["total": rows.count, "rules": page]
    }

    private static func sourceTextStart(_ input: AgentDevInput) throws -> Int? {
        guard input.values["textOffset"] != nil else { return nil }
        return try input.int("textOffset", default: 0, range: 0...Int(Int32.max))
    }

    private static func addSourceText(
        _ value: String, to row: inout [String: Any], key: String, offset: Int?, query: String, limit: Int = 2048
    ) {
        let scalars = value.unicodeScalars
        let start = if let offset {
            scalars.index(scalars.startIndex, offsetBy: offset, limitedBy: scalars.endIndex) ?? scalars.endIndex
        } else {
            (query.isEmpty ? nil : value.range(of: query, options: .caseInsensitive)?.lowerBound) ?? scalars.startIndex
        }
        let end = scalars.index(start, offsetBy: limit, limitedBy: scalars.endIndex) ?? scalars.endIndex
        let startOffset = scalars.distance(from: scalars.startIndex, to: start)
        let offsetKey = key == "raw" ? "rawTextOffset" : "textOffset"
        let nextKey = key == "raw" ? "nextRawTextOffset" : "nextTextOffset"
        row[key] = String(scalars[start..<end])
        row[offsetKey] = startOffset
        if end < scalars.endIndex { row[nextKey] = startOffset + limit }
    }
}
