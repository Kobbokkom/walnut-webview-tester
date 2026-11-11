import CryptoKit
import Foundation

@MainActor
extension AgentDevTools {
    private static let exportChunkSize = 256 * 1024
    static let exportByteOffset = ["type": "integer", "minimum": 0, "maximum": Int(Int32.max)] as [String: Any]
    private static let consoleTypes = ["type": "array", "items": options(ConsoleLog.LogType.displayableTypes.map(\.rawValue))] as [String: Any]

    static let logTools: [[String: Any]] = [
        AgentTool.definition("console_configure", "Read or set Console options for this connection. Only preserve and clear strategy can be saved.", [
            "capture": flag, "preserveOnReload": flag, "clearStrategy": options(LogClearStrategy.self),
            "regex": flag, "types": consoleTypes,
            "save": flag
        ]),
        AgentTool.definition("console_list", "Read or export retained Console records. Use either type or types to filter log levels for this query. Optional document ID limits results to that document. For a long text or JSON export, append records from each chunk and pass nextByteOffset as byteOffset with contentId and the same filters. Text searches and raw content require confirmation.", [
            "type": options(ConsoleLog.LogType.displayableTypes.map(\.rawValue)), "types": consoleTypes, "query": query, "regex": flag,
            "includeCollapsed": flag, "raw": raw, "format": options(["structured", "text", "json"]),
            "documentId": identifier, "offset": offset, "limit": limit,
            "byteOffset": exportByteOffset, "contentId": identifier
        ]),
        AgentTool.definition("console_detail", "Read full Console record details by ID. For a large record, concatenate the content chunks and parse them as JSON. Pass nextByteOffset as byteOffset with contentId and the same ID. Requires confirmation.", [
            "id": identifier, "byteOffset": exportByteOffset, "contentId": identifier
        ], required: ["id"]),
        AgentTool.definition("console_group", "Set the collapsed state of a Console group.", [
            "id": identifier, "collapsed": flag
        ], required: ["id", "collapsed"]),
        AgentTool.definition("console_clear", "Clear Console logs. Requires confirmation.", [:]),
        AgentTool.definition("console_evaluate", "Run JavaScript in the current page. Requires confirmation.", ["script": text], required: ["script"]),
        AgentTool.definition("network_configure", "Read or set Network and Resources capture, preserve on reload and navigation clear strategy.", [
            "capture": flag, "preserveOnReload": flag, "clearStrategy": options(LogClearStrategy.self), "save": flag
        ]),
        AgentTool.definition("network_list", "Read or export retained Network requests and resource timings. For a long text or JSON export, append export from each chunk and pass nextByteOffset as byteOffset with contentId and the same filters. Exports and raw URLs require confirmation.", [
            "category": options(NetworkResourceFilter.self), "query": query, "method": query, "host": query,
            "minStatus": ["type": "integer", "minimum": 100, "maximum": 599],
            "maxStatus": ["type": "integer", "minimum": 100, "maximum": 599],
            "documentId": identifier, "raw": raw, "offset": offset, "limit": limit,
            "format": options(["structured", "text", "json"]), "byteOffset": exportByteOffset, "contentId": identifier
        ]),
        AgentTool.definition("network_detail", "Read request overview, headers, request, response, or copy-as-cURL representation by ID. Full content requires confirmation.", [
            "id": identifier, "section": options(["overview", "headers", "request", "response", "curl"]), "raw": raw,
            "bodyOffset": ["type": "integer", "minimum": 0, "maximum": 16777216]
        ], required: ["id"]),
        AgentTool.definition("resources_detail", "Read timing and sizes for a captured resource by ID.", [
            "id": identifier, "raw": raw
        ], required: ["id"]),
        AgentTool.definition("network_clear", "Clear captured network requests and resource timings. Requires confirmation.", [:])
    ]

    static func callLogs(
        _ tool: String,
        _ input: AgentDevInput,
        _ context: AgentDevContext,
        _ console: ConsoleSession
    ) async throws -> Any {
        let navigator = context.navigator
        switch tool {
        case "console_configure":
            return try await configureLogs(input, context, console)
        case "network_configure":
            return try await configureLogs(input, context, nil)
        case "console_list":
            return try await listConsole(input, context, console)
        case "console_detail":
            let id = try input.uuid("id")
            let cursor = try exportCursor(input, source: "Console")
            try await context.confirm("Share the selected Console entry with the Mac?")
            guard let log = navigator.consoleManager.logs.first(where: { $0.id == id }) else {
                throw AgentError("Console record not found.")
            }
            return try exportRecord(consoleRecord(log, includeContent: true, fullContent: true), cursor: cursor, source: "Console")
        case "console_group":
            let id = try input.uuid("id")
            guard let collapsed = try input.bool("collapsed"),
                  navigator.consoleManager.logs.contains(where: { $0.groupId == id && [.group, .groupCollapsed].contains($0.type) }) else {
                throw AgentError("A group ID and collapsed state are required.")
            }
            if navigator.consoleManager.collapsedGroups.contains(id) != collapsed {
                navigator.consoleManager.toggleGroup(id)
            }
            return ["collapsed": collapsed]
        case "console_clear":
            try await context.confirm("Clear Walnut's Console logs?")
            navigator.consoleManager.clear()
            return ["cleared": true]
        case "console_evaluate":
            let script = try input.required("script", maxLength: 16_384)
            try await context.confirm("Run JavaScript on the current page and share the result with the Mac?\n\n\(script)")
            if console.commandHistory.last != script {
                console.commandHistory = Array((console.commandHistory + [script]).suffix(100))
            }
            console.historyIndex = -1
            navigator.consoleManager.addLog(type: "command", message: script, source: "Mac agent")
            let result: Any?
            do {
                result = try await navigator.evaluateJavaScriptReportingErrors(script)
            } catch {
                try context.checkDocument()
                let exception = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
                let message = clipped(exception ?? error.localizedDescription)
                navigator.consoleManager.addLog(type: "error", message: message, source: "Mac agent")
                throw AgentError("JavaScript evaluation failed: \(message)")
            }
            try context.checkDocument()
            let output = clipped(result.map { String(describing: $0) } ?? "undefined")
            navigator.consoleManager.addLog(type: "result", message: output, source: "Mac agent")
            return ["result": output]
        case "network_list":
            return try await listNetwork(input, context)
        case "network_detail":
            return try await networkDetail(input, context)
        case "resources_detail":
            let id = try input.uuid("id")
            let includeContent = try input.bool("raw") ?? false
            if includeContent { try await context.confirm("Share the selected resource URL with the Mac?") }
            guard let entry = navigator.resourceManager.resources.first(where: { $0.id == id }) else {
                throw AgentError("Resource record not found.")
            }
            return resourceRecord(entry, includeContent: includeContent)
        case "network_clear":
            try await context.confirm("Clear Walnut's Network logs and Resource timings?")
            navigator.networkManager.clear()
            navigator.resourceManager.clear()
            return ["cleared": true]
        default:
            throw AgentError("Unknown log tool.")
        }
    }

    private static func configureLogs(
        _ input: AgentDevInput,
        _ context: AgentDevContext,
        _ console: ConsoleSession?
    ) async throws -> [String: Any] {
        let navigator = context.navigator
        let capture = try input.bool("capture")
        let preserve = try input.bool("preserveOnReload")
        let strategy = try input.option("clearStrategy", as: LogClearStrategy.self)
        let save = try input.bool("save") ?? false
        let regex = try input.bool("regex")
        let types = try consoleLogTypes(input)
        let defaults = UserDefaults.standard
        let policies = LogClearStrategyResolver(defaults: defaults).resolveStrategies()
        let isConsole = console != nil
        let prefix = isConsole ? "console" : "network"
        let overrides = navigator.agentLogSettings
        let currentPreserve = isConsole
            ? (overrides.consolePreserveLog ?? navigator.consoleManager.preserveLog)
            : (overrides.networkPreserveLog ?? navigator.networkManager.preserveLog)
        let currentStrategy = isConsole
            ? (overrides.consoleClearStrategy ?? policies.console)
            : (overrides.networkClearStrategy ?? policies.network)
        let tighterStrategy = strategy.map { $0 != currentStrategy && $0 != .keep && (currentStrategy == .keep || $0 == .page) } ?? false
        let canClearHistory = tighterStrategy || (currentPreserve && preserve == false)
        let savesSettings = save && (preserve != nil || strategy != nil)
        try await confirmLogSettings(context, prefix: prefix, saves: savesSettings, canClearHistory: canClearHistory)
        if savesSettings {
            if let preserve { defaults.set(preserve, forKey: "\(prefix)PreserveLog") }
            if let strategy {
                let key = isConsole ? LogClearStrategy.consoleDefaultsKey : LogClearStrategy.networkDefaultsKey
                defaults.set(strategy.rawValue, forKey: key)
            }
        }
        if let console {
            if let capture { navigator.consoleManager.isCapturing = capture }
            if let regex { navigator.agentLogSettings.consoleRegex = regex }
            if let types { navigator.agentLogSettings.consoleTypes = types }
            if preserve != nil { navigator.agentLogSettings.consolePreserveLog = save ? nil : preserve }
            if strategy != nil { navigator.agentLogSettings.consoleClearStrategy = save ? nil : strategy }
            return [
                "capture": navigator.consoleManager.isCapturing,
                "regex": navigator.agentLogSettings.consoleRegex ?? console.useRegex,
                "types": (navigator.agentLogSettings.consoleTypes ?? console.enabledLogTypes).map(\.rawValue).sorted(),
                "preserveOnReload": navigator.agentLogSettings.consolePreserveLog ?? navigator.consoleManager.preserveLog,
                "clearStrategy": (navigator.agentLogSettings.consoleClearStrategy ?? (save ? strategy : nil) ?? policies.console).rawValue
            ]
        }
        if let capture {
            navigator.networkManager.isCapturing = capture
            navigator.resourceManager.isCapturing = capture
        }
        if preserve != nil { navigator.agentLogSettings.networkPreserveLog = save ? nil : preserve }
        if strategy != nil { navigator.agentLogSettings.networkClearStrategy = save ? nil : strategy }
        return [
            "capture": navigator.networkManager.isCapturing && navigator.resourceManager.isCapturing,
            "preserveOnReload": navigator.agentLogSettings.networkPreserveLog ?? navigator.networkManager.preserveLog,
            "clearStrategy": (navigator.agentLogSettings.networkClearStrategy ?? (save ? strategy : nil) ?? policies.network).rawValue
        ]
    }

    private static func consoleLogTypes(_ input: AgentDevInput) throws -> Set<ConsoleLog.LogType>? {
        guard let requested = input.values["types"] else { return nil }
        let displayable = ConsoleLog.LogType.displayableTypes
        guard let names = requested as? [String], names.count <= displayable.count else {
            throw AgentError("types must be an array of Console log levels.")
        }
        let valid = displayable.filter { names.contains($0.rawValue) }
        guard Set(names).count == valid.count else { throw AgentError("Invalid Console log level.") }
        return Set(valid)
    }

    private static func confirmLogSettings(
        _ context: AgentDevContext,
        prefix: String,
        saves: Bool,
        canClearHistory: Bool
    ) async throws {
        if canClearHistory {
            let action = saves ? "Save and apply" : "Apply"
            try await context.confirm("\(action) the \(prefix) log settings? The next reload or navigation may delete retained entries.")
        } else if saves {
            try await context.confirm("Save the \(prefix) log settings on the iPhone?")
        }
    }

    private static func listConsole(
        _ input: AgentDevInput,
        _ context: AgentDevContext,
        _ console: ConsoleSession
    ) async throws -> [String: Any] {
        let document = try input.values["documentId"].map { _ in try input.uuid("documentId") }
        let type = try input.option("type", as: ConsoleLog.LogType.self)
        let types = try consoleLogTypes(input)
        guard type == nil || types == nil else { throw AgentError("Choose either type or types.") }
        let overrides = context.navigator.agentLogSettings
        let levels = type.map { Set([$0]) } ?? types ?? overrides.consoleTypes ?? console.enabledLogTypes
        let query = try input.string("query") ?? ""
        let regex = try input.bool("regex") ?? overrides.consoleRegex ?? console.useRegex
        let includeCollapsed = try input.bool("includeCollapsed") ?? true
        let format = try input.string("format") ?? "structured"
        guard ["structured", "text", "json"].contains(format) else { throw AgentError("Invalid Console format.") }
        let cursor = try exportCursor(input, source: "Console")
        guard format != "structured" || cursor.offset == 0 else { throw AgentError("A byte offset requires Console text or JSON export.") }
        let includeContent = (try input.bool("raw") ?? false) || format != "structured"
        let compiled: NSRegularExpression?
        if regex && !query.isEmpty {
            guard case .success(let matcher) = RegexFilter.compile(query) else {
                throw AgentError("Invalid Console search pattern.")
            }
            compiled = matcher
        } else {
            compiled = nil
        }
        let runID = context.navigator.agentNavigation.runID
        if includeContent || !query.isEmpty {
            try await context.confirm("Read the contents of Walnut's Console logs on the Mac?")
        }
        let manager = context.navigator.consoleManager
        let deadline = ContinuousClock.now + .milliseconds(150)
        let candidates = manager.logs.reversed().filter { log in
            guard log.type != .groupEnd, document == nil || log.agentDocumentID == document,
                  levels.contains(log.type) else { return false }
            return includeCollapsed || [.group, .groupCollapsed].contains(log.type)
                || (log.groupId.map { !manager.collapsedGroups.contains($0) } ?? true)
        }
        let filtered = try candidates.filter { log in
            guard !query.isEmpty else { return true }
            if let compiled {
                return try regexMatch(compiled, log.message, deadline: deadline)
                    || regexMatch(compiled, log.source ?? "", deadline: deadline)
            }
            return log.message.localizedCaseInsensitiveContains(query)
                || log.source?.localizedCaseInsensitiveContains(query) == true
        }
        let page = try paginate(input, filtered)
        var result: [String: Any] = ["capture": manager.isCapturing, "total": filtered.count, "retained": document == nil]
        var export = TextExport(offset: cursor.offset)
        switch format {
        case "text":
            try await export.appendLines(ConsoleExporter.textLines(page, includeObjects: true), separator: "\n\n")
        case "json":
            try await export.appendJSONRows(page) { consoleRecord($0, includeContent: true, fullContent: true) }
        default:
            result["records"] = page.map { consoleRecord($0, includeContent: includeContent) }
            return result
        }
        try checkLogExportTarget(context, runID: runID)
        result.merge(try export.result(key: "records", contentId: cursor.id, source: "Console")) { _, new in new }
        return result
    }

    private static func checkLogExportTarget(_ context: AgentDevContext, runID: UUID) throws {
        try context.checkDocument()
        guard context.navigator.agentNavigation.runID == runID else {
            throw AgentError("The active WKWebView navigation changed. Try again.")
        }
    }

    static func exportCursor(_ input: AgentDevInput, source: String) throws -> (offset: Int, id: String?) {
        let offset = try input.int("byteOffset", default: 0, range: 0...Int(Int32.max))
        let id = try input.string("contentId", maxLength: 64)
        guard (offset > 0) == (id != nil) else {
            throw AgentError("A \(source) continuation requires its byte offset and content ID.")
        }
        return (offset, id)
    }

    static func exportRecord(
        _ record: [String: Any], cursor: (offset: Int, id: String?), source: String
    ) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        if cursor.offset == 0, data.count <= exportChunkSize { return record }
        var export = TextExport(offset: cursor.offset)
        export.append(data)
        var result = try export.result(key: "content", contentId: cursor.id, source: source)
        result["id"] = record["id"]
        return result
    }

    @MainActor
    private struct TextExport {
        let offset: Int
        private var hash = SHA256()
        private var chunk = Data()
        private var byteCount = 0

        init(offset: Int) {
            self.offset = offset
        }

        mutating func append(_ data: Data) {
            hash.update(data: data)
            let start = max(offset - byteCount, 0)
            // Keep one extra byte to locate the last complete UTF-8 scalar in the response.
            let end = min(offset + exportChunkSize + 1 - byteCount, data.count)
            if start < end {
                chunk.append(contentsOf: data[(data.startIndex + start)..<(data.startIndex + end)])
            }
            byteCount += data.count
        }

        mutating func append(_ text: String) {
            append(Data(text.utf8))
        }

        mutating func appendLines(_ lines: some Collection<String>, separator: String) async throws {
            for (index, position) in lines.indices.enumerated() {
                await Task.yield()
                try Task.checkCancellation()
                if index > 0 { append(separator) }
                append(lines[position])
            }
        }

        mutating func appendJSONRows<Row>(_ rows: some Sequence<Row>, encode: (Row) -> [String: Any]) async throws {
            append("[")
            for (index, row) in rows.enumerated() {
                await Task.yield()
                try Task.checkCancellation()
                if index > 0 { append(",") }
                let data = try autoreleasepool {
                    try JSONSerialization.data(withJSONObject: encode(row), options: [.sortedKeys])
                }
                append(data)
            }
            append("]")
        }

        func result(key: String, contentId: String?, source: String) throws -> [String: Any] {
            let id = offset > 0 || chunk.count > exportChunkSize
                ? hash.finalize().map { String(format: "%02x", $0) }.joined()
                : nil
            guard contentId == nil || contentId == id else {
                throw AgentError("The \(source) content changed. Start reading it again.")
            }
            guard offset == 0 || chunk.first.map({ $0 & 0xc0 != 0x80 }) == true else {
                throw AgentError("Invalid \(source) byte offset. Use nextByteOffset from the previous chunk.")
            }
            var end = min(chunk.count, exportChunkSize)
            while end < chunk.count && chunk[end] & 0xc0 == 0x80 { end -= 1 }
            guard let content = String(bytes: chunk.prefix(end), encoding: .utf8) else {
                throw AgentError("Could not encode \(source) content.")
            }
            var result: [String: Any] = [key: content]
            if end < chunk.count {
                result["contentId"] = id
                result["nextByteOffset"] = offset + end
            }
            return result
        }
    }

    private static func regexMatch(_ regex: NSRegularExpression, _ text: String, deadline: ContinuousClock.Instant) throws -> Bool {
        let timeout = AgentError("The Console search pattern exceeded its time limit.")
        guard ContinuousClock.now < deadline else { throw timeout }
        var matched = false
        var failed = false
        regex.enumerateMatches(in: text, options: [.reportProgress, .reportCompletion], range: NSRange(text.startIndex..., in: text)) { result, flags, stop in
            matched = matched || result != nil
            failed = flags.contains(.internalError)
            stop.pointee = ObjCBool(matched || failed || ContinuousClock.now >= deadline)
        }
        guard ContinuousClock.now < deadline else { throw timeout }
        guard !failed else { throw AgentError("The Console search pattern could not complete.") }
        return matched
    }

    private static func consoleRecord(_ log: ConsoleLog, includeContent: Bool, fullContent: Bool = false) -> [String: Any] {
        func content(_ value: String, limit: Int = 4096) -> String {
            fullContent ? value : clipped(value, limit: limit)
        }
        var row: [String: Any] = [
            "id": log.id.uuidString, "type": log.type.rawValue,
            "timestamp": log.timestamp.timeIntervalSince1970, "repeatCount": log.repeatCount,
            "groupLevel": log.groupLevel
        ]
        row["groupId"] = log.groupId?.uuidString
        row["documentId"] = log.agentDocumentID?.uuidString
        if includeContent {
            row["message"] = content(log.message)
            row["object"] = log.objectValue.map { content($0.copyableString, limit: 32_768) }
            if case .array(let array) = log.objectValue {
                row["arrayCount"] = array.totalCount
                row["arrayTruncated"] = array.isTruncated
            }
            if let segments = log.styledSegments, JSONSerialization.isValidJSONObject(segments) {
                row["styledSegments"] = segments
            }
            row["inlineSegments"] = log.inlineSegments?.prefix(fullContent ? .max : 100).map { segment -> [String: String] in
                var item = ["text": content(segment.text, limit: 1024)]
                item["kind"] = segment.kind?.rawValue
                return item
            }
            row["source"] = log.source.map { content($0) }
            row["stack"] = log.stackTrace.map { content($0) }
            row["timerLabel"] = log.timerLabel
            row["timerElapsed"] = log.timerElapsed
            row["countLabel"] = log.countLabel
            row["count"] = log.countValue
            row["table"] = log.tableData?.prefix(fullContent ? .max : 20).map { $0.mapValues { content($0, limit: 256) } }
        }
        return row
    }
}

@MainActor
extension AgentDevTools {
    fileprivate static func listNetwork(_ input: AgentDevInput, _ context: AgentDevContext) async throws -> [String: Any] {
        let filter = try input.option("category", as: NetworkResourceFilter.self) ?? .all
        let document = try input.values["documentId"].map { _ in try input.uuid("documentId") }
        let method = try input.string("method")
        let host = try input.string("host")
        let query = try input.string("query") ?? ""
        let minStatus = try input.int("minStatus", default: 100, range: 100...599)
        let maxStatus = try input.int("maxStatus", default: 599, range: 100...599)
        let filterStatus = input.values["minStatus"] != nil || input.values["maxStatus"] != nil
        guard minStatus <= maxStatus else { throw AgentError("minStatus must not exceed maxStatus.") }
        let format = try input.string("format") ?? "structured"
        guard ["structured", "text", "json"].contains(format) else { throw AgentError("Invalid Network format.") }
        let cursor = try exportCursor(input, source: "Network")
        guard format != "structured" || cursor.offset == 0 else { throw AgentError("A byte offset requires Network text or JSON export.") }
        let includeContent = (try input.bool("raw") ?? false) || format != "structured"
        let navigator = context.navigator
        let runID = navigator.agentNavigation.runID
        if includeContent {
            try await context.confirm("Share captured Network and Resource details with the Mac, including full URLs and request errors?")
        }
        let requests = navigator.networkManager.requests.reversed().filter { request in
            guard filter.matchesNetworkRequest(request), document == nil || document == request.agentDocumentID else { return false }
            if let method, request.method.caseInsensitiveCompare(method) != .orderedSame { return false }
            if let host, URLComponents(string: request.url)?.host?.caseInsensitiveCompare(host) != .orderedSame { return false }
            if filterStatus, !(minStatus...maxStatus).contains(request.status ?? 0) { return false }
            return query.isEmpty || request.method.localizedCaseInsensitiveContains(query)
                || (includeContent ? request.url : safeURL(request.url)).localizedCaseInsensitiveContains(query)
                || (includeContent && request.statusText?.localizedCaseInsensitiveContains(query) == true)
        }
        let resources = navigator.resourceManager.resources.reversed().filter { entry in
            guard method == nil, !filterStatus, filter.matchesResource(entry), document == nil || document == entry.agentDocumentID else { return false }
            if filter == .all, [.fetch, .xmlhttprequest].contains(entry.initiatorType) { return false }
            if let host, entry.host?.caseInsensitiveCompare(host) != .orderedSame { return false }
            return query.isEmpty || (includeContent ? entry.name : safeURL(entry.name)).localizedCaseInsensitiveContains(query)
                || (includeContent && entry.displayName.localizedCaseInsensitiveContains(query))
        }
        let pageRequests = try paginate(input, requests)
        let pageResources = try paginate(input, resources)
        var result: [String: Any] = [
            "retained": document == nil, "capture": navigator.networkManager.isCapturing,
            "resourceCapture": navigator.resourceManager.isCapturing, "requestCount": requests.count, "resourceCount": resources.count
        ]
        var export = TextExport(offset: cursor.offset)
        switch format {
        case "text":
            try await export.appendLines(NetworkExporter.requestTextLines(pageRequests), separator: "\n\n")
            if !pageRequests.isEmpty && !pageResources.isEmpty { export.append("\n\n") }
            try await export.appendLines(NetworkExporter.resourceTextLines(pageResources), separator: "\n\n")
        case "json":
            export.append("{\"requests\":")
            try await export.appendJSONRows(pageRequests) { networkRecord($0, includeContent: true, fullContent: true) }
            export.append(",\"resources\":")
            try await export.appendJSONRows(pageResources) { resourceRecord($0, includeContent: true, fullContent: true) }
            export.append("}")
        default:
            result["requests"] = pageRequests.map { networkRecord($0, includeContent: includeContent) }
            result["resources"] = pageResources.map { resourceRecord($0, includeContent: includeContent) }
            return result
        }
        try checkLogExportTarget(context, runID: runID)
        result.merge(try export.result(key: "export", contentId: cursor.id, source: "Network")) { _, new in new }
        return result
    }

    fileprivate static func networkDetail(_ input: AgentDevInput, _ context: AgentDevContext) async throws -> [String: Any] {
        let id = try input.uuid("id")
        let section = try input.string("section") ?? "overview"
        guard ["overview", "headers", "request", "response", "curl"].contains(section) else {
            throw AgentError("Invalid request section.")
        }
        let includeContent = (try input.bool("raw") ?? false) || section != "overview"
        let bodyOffset = try input.int("bodyOffset", default: 0, range: 0...16_777_216)
        if includeContent { try await context.confirm("Share the selected request's \(section) details with the Mac?") }
        guard let request = context.navigator.networkManager.requests.first(where: { $0.id == id }) else {
            throw AgentError("Network request not found.")
        }
        var row = networkRecord(request, includeContent: includeContent)
        switch section {
        case "headers":
            row["requestHeaders"] = request.requestHeaders
            row["responseHeaders"] = request.responseHeaders
        case "request", "response":
            if let body = section == "request" ? request.requestBody : request.responseBody {
                let page = body.dropFirst(bodyOffset).prefix(32_768)
                row["body"] = String(page)
                row["nextBodyOffset"] = bodyOffset + page.count < body.count ? bodyOffset + page.count : nil
            }
            if section == "response" { row["contentType"] = request.responseContentType }
        case "curl":
            let command = request.curlCommand
            guard command.utf8.count < 1_000_000 else {
                throw AgentError("The captured request is too large for copy-as-cURL. Read the request body separately.")
            }
            row["command"] = command
        default:
            if includeContent { row["stack"] = try request.stackFrames.map { try AgentTool.json($0) } }
        }
        return row
    }

    private static func networkRecord(_ request: NetworkRequest, includeContent: Bool, fullContent: Bool = false) -> [String: Any] {
        func content(_ value: String, limit: Int = 4096) -> String {
            fullContent ? value : clipped(value, limit: limit)
        }
        var row: [String: Any] = [
            "id": request.id.uuidString, "type": request.requestType.rawValue,
            "timestamp": request.startTime.timeIntervalSince1970,
            "method": content(request.method, limit: 32),
            "url": includeContent ? content(request.url) : safeURL(request.url),
            "pending": request.isPending, "failed": request.error != nil || (request.status ?? 0) >= 400,
            "mixedContent": request.isMixedContent
        ]
        row["documentId"] = request.agentDocumentID?.uuidString
        row["status"] = request.status
        row["durationMs"] = request.duration.map { $0 * 1000 }
        if includeContent {
            row["error"] = request.error.map { content($0) }
            row["statusText"] = request.statusText.map { content($0) }
        }
        return row
    }

    private static func resourceRecord(_ entry: ResourceEntry, includeContent: Bool, fullContent: Bool = false) -> [String: Any] {
        let url = if includeContent { fullContent ? entry.name : clipped(entry.name) } else { safeURL(entry.name) }
        var row: [String: Any] = [
            "id": entry.id.uuidString, "type": entry.initiatorType.rawValue,
            "timestamp": entry.timestamp.timeIntervalSince1970,
            "url": url,
            "startMs": entry.startTime, "durationMs": entry.duration,
            "transferBytes": entry.transferSize, "encodedBytes": entry.encodedBodySize, "decodedBytes": entry.decodedBodySize,
            "dnsMs": entry.dnsTime, "tcpMs": entry.tcpTime, "tlsMs": entry.tlsTime,
            "requestMs": entry.requestTime, "responseMs": entry.responseTime, "crossOriginRestricted": entry.isCrossOriginRestricted
        ]
        row["documentId"] = entry.agentDocumentID?.uuidString
        return row
    }
}
