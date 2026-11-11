import Foundation
import WebKit

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
        guard ["tree", "html", "stylesheets", "scripts"].contains(section) else { throw AgentError("Invalid Sources section.") }
        if raw || section == "tree" || section == "html" || !query.isEmpty {
            try await context.confirm("Inspect \(section) from the current page on the Mac?")
        }
        if section == "tree" {
            let sources = SourcesManager()
            sources.setNavigator(context.navigator)
            await sources.fetchDOMTree()
            try context.checkDocument()
            guard let tree = sources.domTree else { throw AgentError(sources.errorMessage ?? "No DOM tree returned.") }
            let rows = sourceNodes(tree, query: query)
            return ["documentId": context.document.uuidString, "total": rows.count, "entries": Array(try paginate(input, rows))]
        }
        let script = switch section {
        case "html": SourcesManager.rawHTMLScript(result: "pageHTML(html)")
        case "stylesheets":
            SourcesManager.stylesheetsScript(result: "pageMetadata(sheets, true, \(raw))", includeContent: !query.isEmpty)
        default:
            SourcesManager.scriptsScript(result: "pageMetadata(scripts, false, \(raw))", includeContent: !query.isEmpty)
        }
        return try await evaluateSourcePage(script, input, query: query, context: context)
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
        switch kind {
        case "element":
            let script = try elementDetailScript(input)
            try await context.confirm("Share the selected element details from this page with the Mac?")
            return try await evaluateSourcePage(script, input, query: query, context: context)
        case "stylesheet", "script":
            let index = try input.int("index", default: -1, range: 0...100_000)
            guard index >= 0 else { throw AgentError("A stylesheet or script index is required.") }
            let resource: SourceResourceScript.Kind = kind == "stylesheet" ? .stylesheet : .script
            let expected = try await approveSource(resource, index: index, context: context)
            let script = switch resource {
            case .stylesheet:
                StylesheetDetailView.contentScript(index: index, expected: expected, result: "pageSheet(rules, rawCSS, retrieval)")
            case .script:
                ScriptDetailView.contentScript(index: index, expected: expected, result: "pageSource(content, retrieval)")
            }
            return try await evaluateSourcePage(script, input, query: query, context: context, asynchronous: true)
        default:
            throw AgentError("Invalid Sources detail kind.")
        }
    }

    private static func approveSource(_ kind: SourceResourceScript.Kind, index: Int, context: AgentDevContext) async throws -> String {
        let value = try await context.navigator.evaluateJavaScriptReportingErrors(
            SourceResourceScript.capture(kind, index: index), contentWorld: .defaultClient
        )
        try context.checkDocument()
        guard let selection = try parseJSON(value) as? [String: String],
              let expected = selection["identity"], let label = selection["label"] else {
            throw AgentError("Source not found. Refresh Sources and select it again.")
        }
        var prompt = "Share the selected \(kind.rawValue) details from this page with the Mac?"
        if !label.isEmpty {
            prompt += "\n\n\(label)\n\nWalnut may request this resource under the page's network policy."
            if selection["credentials"] == "include" {
                prompt += " The request may include credentials for the resource's origin."
            }
        }
        try await context.confirm(prompt)
        return expected
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
        switch try input.string("section") ?? "attributes" {
        case "attributes":
            return """
            (function() {
                const node = \(SourcesManager.nodeLookupScript(path: path));
                if (!node) return JSON.stringify({error: 'Element not found'});
                return pageEntries(Object.fromEntries(Array.from(node.attributes || [], attr => [attr.name, attr.value])));
            })();
            """
        case "computedStyles":
            return try input.bool("allComputedStyles") == true
                ? ElementDetailScripts.allComputedStyles(path: path, result: "pageEntries(result)")
                : ElementDetailScripts.computedStyles(path: path, result: "pageEntries(result)")
        case "matchedRules":
            return ElementDetailScripts.matchedRules(path: path, result: "pageMatchedRules(rules)")
        case "html":
            return ElementDetailScripts.htmlContent(path: path, result: "pageEntries({outer: el.outerHTML, inner: el.innerHTML})")
        default:
            throw AgentError("Invalid element detail section.")
        }
    }

    private static func evaluateSourcePage(
        _ script: String, _ input: AgentDevInput, query: String, context: AgentDevContext, asynchronous: Bool = false
    ) async throws -> [String: Any] {
        let offset = try input.int("offset", default: 0, range: 0...100_000)
        let limit = try input.int("limit", default: 30, range: 1...100)
        let propertyOffset = try input.int("propertyOffset", default: 0, range: 0...100_000)
        let textOffset = try input.values["textOffset"].map { _ in
            try input.int("textOffset", default: 0, range: 0...Int(Int32.max))
        }
        guard let literal = try String(bytes: JSONEncoder().encode(query), encoding: .utf8) else {
            throw AgentError("Could not encode the Sources query.")
        }
        let wrapped = """
        (() => {
            const query = \(literal), offset = \(offset), end = offset + \(limit);
            const textOffset = \(textOffset.map(String.init) ?? "null"), propertyOffset = \(propertyOffset);
            \(sourcePageFunctions)
            return \(script)
        })();
        """
        let data = if asynchronous {
            try await context.navigator.callAsyncJavaScriptReportingErrors("return \(wrapped)", contentWorld: .defaultClient)
        } else {
            try await context.navigator.evaluateJavaScriptReportingErrors(wrapped, contentWorld: .defaultClient)
        }
        try context.checkDocument()
        guard var payload = try parseJSON(data) as? [String: Any] else { throw AgentError("No Sources details returned.") }
        if let error = payload["error"] as? String { throw AgentError(error) }
        payload["documentId"] = context.document.uuidString
        return payload
    }

    private static let sourcePageFunctions = #"""
    const nonASCII = /[^\x00-\x7f]/;
    const foldedQuery = fold(query);
    function fold(value) {
        // The upper/lower round trip expands case-folded letters such as ß and ligatures.
        return value.normalize('NFC').replace(/[^\x00-\x7f]/gu, scalar =>
            scalar === 'ı' ? scalar : scalar.toUpperCase().toLowerCase().replace(/ß/g, 'ss')
        ).toLowerCase().normalize('NFC');
    }
    function* foldedRanges(value) {
        const graphemes = new Intl.Segmenter('und', {granularity: 'grapheme'});
        let offset = 0;
        // Keep the final ASCII character with a following Unicode run so combining marks stay attached.
        for (const part of value.matchAll(/[\x00-\x7f]+(?=[\x00-\x7f]|$)|[\x00-\x7f]?[^\x00-\x7f]+/g)) {
            const text = part[0];
            if (!nonASCII.test(text)) {
                yield [offset, offset + text.length, part.index, text.length, true];
                offset += text.length;
                continue;
            }
            for (const {segment, index} of graphemes.segment(text)) {
                const folded = fold(segment);
                const preservesIndices = folded.length === segment.length && folded === segment.toLowerCase();
                yield [offset, offset + folded.length, part.index + index, segment.length, preservesIndices];
                offset += folded.length;
            }
        }
    }
    function originalIndex(value) {
        const ranges = foldedRanges(value);
        let range = ranges.next().value;
        return index => {
            while (range && index > range[1]) range = ranges.next().value;
            if (!range) return -1;
            if (index === range[1]) return range[2] + range[3];
            return range[4] || index === range[0] ? range[2] + index - range[0] : -1;
        };
    }
    function matchIndex(value) {
        if (!query) return 0;
        if (typeof value !== 'string') return -1;
        if (!nonASCII.test(value)) return value.toLowerCase().indexOf(foldedQuery);
        const folded = fold(value);
        let match = folded.indexOf(foldedQuery);
        if (match < 0) return -1;
        const findStart = originalIndex(value), findEnd = originalIndex(value);
        while (match >= 0) {
            const start = findStart(match);
            if (start >= 0 && findEnd(match + foldedQuery.length) >= 0) return start;
            match = folded.indexOf(foldedQuery, match + 1);
        }
        return -1;
    }
    const matches = value => matchIndex(value) >= 0;
    function scalarEnd(value, start, count) {
        let end = start;
        while (count-- > 0 && end < value.length) end += value.codePointAt(end) > 0xffff ? 2 : 1;
        return end;
    }
    function boundedText(value, limit = 4096) {
        return typeof value === 'string' ? value.slice(0, scalarEnd(value, 0, limit)).toWellFormed() : value;
    }
    function metadataURL(value, raw) {
        if (raw) return boundedText(value);
        try {
            const url = new URL(value);
            if (['http:', 'https:', 'ws:', 'wss:'].includes(url.protocol) && url.hostname && url.origin.length <= 4096) {
                return url.origin;
            }
        } catch (_) {}
        return '';
    }
    function sourceSlice(value, row, key, limit) {
        const raw = key === 'raw';
        let start = 0, offset = 0;
        const found = textOffset === null ? Math.max(0, matchIndex(value)) : 0;
        while (start < value.length && (textOffset === null ? start < found : offset < textOffset)) {
            start += value.codePointAt(start) > 0xffff ? 2 : 1;
            offset++;
        }
        const end = scalarEnd(value, start, limit);
        row[key] = value.slice(start, end).toWellFormed();
        row[raw ? 'rawTextOffset' : 'textOffset'] = offset;
        if (end < value.length) row[raw ? 'nextRawTextOffset' : 'nextTextOffset'] = offset + limit;
        return row;
    }
    function pageEntries(values) {
        const keys = Object.keys(values).sort().filter(key => matches(key) || matches(values[key]));
        const entries = keys.slice(offset, end).map(key => sourceSlice(values[key], {key: boundedText(key, 1024)}, 'value', 8192));
        return JSON.stringify({total: keys.length, entries});
    }
    function pageSource(content, retrieval) {
        return JSON.stringify({...JSON.parse(pageEntries({content})), retrieval});
    }
    function pageHTML(html) {
        const entries = [];
        let total = 0;
        const lines = html.split(/[\n\r\v\f\u0085\u2028\u2029]/);
        for (let i = 0; i < lines.length; i++) {
            if (matches(lines[i]) && total++ >= offset && total <= end) {
                entries.push(sourceSlice(lines[i], {line: i + 1}, 'text', 2048));
            }
        }
        return JSON.stringify({total, entries, retrieval: 'live-dom'});
    }
    function pageMetadata(items, stylesheets, raw) {
        const entries = [];
        let total = 0;
        items.forEach((item, index) => {
            if (stylesheets ? ![item.href, item.cssContent, item.media].some(matches) : ![item.src, item.content].some(matches)) return;
            if (total++ < offset || total > end) return;
            const row = {index, external: item.isExternal};
            if (stylesheets) {
                row.ruleCount = item.rulesCount;
                if (item.href) row.url = metadataURL(item.href, raw);
                if (raw && item.media != null) row.media = boundedText(item.media);
            } else {
                if (item.src) row.url = metadataURL(item.src, raw);
                row.module = item.isModule;
                row.async = item.isAsync;
                row.defer = item.isDefer;
            }
            entries.push(row);
        });
        return JSON.stringify({total, entries});
    }
    function pageSheet(rules, raw, retrieval) {
        const filtered = rules.filter(row => matches(row.selector) || matches(row.text));
        const page = filtered.slice(offset, end).map(rule => {
            const selector = boundedText(rule.selector, 2048);
            return sourceSlice(rule.text, {selector}, 'text', 2048);
        });
        return JSON.stringify(sourceSlice(raw, {total: filtered.length, rules: page, retrieval}, 'raw', 32768));
    }
    function pageMatchedRules(rules) {
        const filtered = rules.filter(row => matches(row.selector));
        const page = filtered.slice(offset, end).map(row => {
            row.selector = boundedText(row.selector, 2048);
            if (row.layer != null) row.layer = boundedText(row.layer, 1024);
            if (row.source?.href != null) row.source.href = boundedText(row.source.href);
            const total = row.properties.length;
            const properties = row.properties.slice(propertyOffset, propertyOffset + 50);
            row.properties = properties.map(property => {
                property.p = boundedText(property.p, 128);
                return sourceSlice(property.v, property, 'v', 256);
            });
            const next = propertyOffset + properties.length;
            if (next < total) row.nextPropertyOffset = next;
            return row;
        });
        return JSON.stringify({total: filtered.length, rules: page});
    }
    """#
}
