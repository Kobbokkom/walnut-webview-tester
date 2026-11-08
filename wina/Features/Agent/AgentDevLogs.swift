import Foundation

@MainActor
extension AgentDevTools {
    static let logTools: [[String: Any]] = [
        AgentTool.definition("console_configure", "Read or set Console options. Preserve and clear strategy are session-only unless saved.", [
            "capture": flag, "preserveOnReload": flag, "clearStrategy": options(LogClearStrategy.self),
            "regex": flag, "types": ["type": "array", "items": options(ConsoleLog.LogType.displayableTypes.map(\.rawValue))],
            "save": flag
        ]),
        AgentTool.definition("console_list", "Read or export retained Console records. Optional document ID limits results to that document. Text searches and raw content require confirmation.", [
            "type": options(ConsoleLog.LogType.displayableTypes.map(\.rawValue)), "query": query, "regex": flag,
            "includeCollapsed": flag, "raw": raw, "format": options(["structured", "text", "json"]),
            "documentId": identifier, "offset": offset, "limit": limit
        ]),
        AgentTool.definition("console_detail", "Read full Console record details by ID. Requires confirmation.", ["id": identifier], required: ["id"]),
        AgentTool.definition("console_group", "Set the collapsed state of a Console group.", [
            "id": identifier, "collapsed": flag
        ], required: ["id", "collapsed"]),
        AgentTool.definition("console_clear", "Clear Console logs. Requires confirmation.", [:]),
        AgentTool.definition("console_evaluate", "Run JavaScript in the current page. Requires confirmation.", ["script": text], required: ["script"]),
        AgentTool.definition("network_configure", "Read or set Network and Resources capture, preserve on reload and navigation clear strategy.", [
            "capture": flag, "preserveOnReload": flag, "clearStrategy": options(LogClearStrategy.self), "save": flag
        ]),
        AgentTool.definition("network_list", "Read retained Network requests and resource timings. Raw URLs require confirmation.", [
            "category": options(NetworkResourceFilter.self), "query": query, "method": query, "host": query,
            "minStatus": ["type": "integer", "minimum": 100, "maximum": 599],
            "maxStatus": ["type": "integer", "minimum": 100, "maximum": 599],
            "documentId": identifier, "raw": raw, "offset": offset, "limit": limit,
            "format": options(["structured", "text", "json"])
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
            try await context.confirm("Share the selected Console entry with the Mac?")
            guard let log = navigator.consoleManager.logs.first(where: { $0.id == id }) else {
                throw AgentError("Console record not found.")
            }
            return consoleRecord(log, includeContent: true)
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
            let result = await navigator.evaluateJavaScript(script)
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
        let types: Set<ConsoleLog.LogType>?
        if let requested = input.values["types"] {
            guard let names = requested as? [String], names.count <= ConsoleLog.LogType.displayableTypes.count else {
                throw AgentError("types must be an array of Console log levels.")
            }
            let valid = ConsoleLog.LogType.displayableTypes.filter { names.contains($0.rawValue) }
            guard Set(names).count == valid.count else { throw AgentError("Invalid Console log level.") }
            types = Set(valid)
        } else {
            types = nil
        }
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
        let hasHistory = isConsole
            ? !navigator.consoleManager.logs.isEmpty
            : !navigator.networkManager.requests.isEmpty || !navigator.resourceManager.resources.isEmpty
        let tighterStrategy = strategy.map { $0 != currentStrategy && $0 != .keep && (currentStrategy == .keep || $0 == .page) } ?? false
        let canClearHistory = hasHistory && (tighterStrategy || (currentPreserve && preserve == false))
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
            if let regex { console.useRegex = regex }
            if let types { console.enabledLogTypes = types }
            if preserve != nil { navigator.agentLogSettings.consolePreserveLog = save ? nil : preserve }
            if strategy != nil { navigator.agentLogSettings.consoleClearStrategy = save ? nil : strategy }
            return [
                "capture": navigator.consoleManager.isCapturing, "regex": console.useRegex,
                "types": console.enabledLogTypes.map(\.rawValue).sorted(),
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
        let query = try input.string("query") ?? ""
        let regex = try input.bool("regex") ?? console.useRegex
        let includeCollapsed = try input.bool("includeCollapsed") ?? true
        let format = try input.string("format") ?? "structured"
        guard ["structured", "text", "json"].contains(format) else { throw AgentError("Invalid Console format.") }
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
        if includeContent || !query.isEmpty {
            try await context.confirm("Read the contents of Walnut's Console logs on the Mac?")
        }
        let manager = context.navigator.consoleManager
        let deadline = ContinuousClock.now + .milliseconds(150)
        let candidates = manager.logs.reversed().filter { log in
            guard log.type != .groupEnd, document == nil || log.agentDocumentID == document,
                  type.map({ $0 == log.type }) ?? console.enabledLogTypes.contains(log.type) else { return false }
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
        let payload: Any
        switch format {
        case "text": payload = clipped(ConsoleExporter.exportAsText(Array(page), includeObjects: true), limit: 32_768)
        case "json":
            let data = try JSONSerialization.data(withJSONObject: page.map { consoleRecord($0, includeContent: true) })
            guard let output = String(data: data, encoding: .utf8) else { throw AgentError("Could not encode logs.") }
            payload = output
        default: payload = page.map { consoleRecord($0, includeContent: includeContent) }
        }
        return ["capture": manager.isCapturing, "total": filtered.count, "retained": document == nil, "records": payload]
    }

    private static func regexMatch(_ regex: NSRegularExpression, _ value: String, deadline: ContinuousClock.Instant) throws -> Bool {
        let text = clipped(value, limit: 2048)
        var matched = false
        regex.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(text.startIndex..., in: text)) { result, _, stop in
            matched = result != nil
            stop.pointee = ObjCBool(matched || ContinuousClock.now >= deadline)
        }
        guard ContinuousClock.now < deadline else { throw AgentError("The Console search pattern exceeded its time limit.") }
        return matched
    }

    private static func consoleRecord(_ log: ConsoleLog, includeContent: Bool) -> [String: Any] {
        var row: [String: Any] = [
            "id": log.id.uuidString, "type": log.type.rawValue,
            "timestamp": log.timestamp.timeIntervalSince1970, "repeatCount": log.repeatCount,
            "groupLevel": log.groupLevel
        ]
        row["groupId"] = log.groupId?.uuidString
        row["documentId"] = log.agentDocumentID?.uuidString
        if includeContent {
            row["message"] = clipped(log.message)
            row["object"] = log.objectValue.map { clipped($0.copyableString, limit: 32_768) }
            if case .array(let array) = log.objectValue {
                row["arrayCount"] = array.totalCount
                row["arrayTruncated"] = array.isTruncated
            }
            if let segments = log.styledSegments, JSONSerialization.isValidJSONObject(segments) {
                row["styledSegments"] = segments
            }
            row["inlineSegments"] = log.inlineSegments?.prefix(100).map { segment -> [String: String] in
                var item = ["text": clipped(segment.text, limit: 1024)]
                item["kind"] = segment.kind?.rawValue
                return item
            }
            row["source"] = log.source.map { clipped($0) }
            row["stack"] = log.stackTrace.map { clipped($0) }
            row["timerLabel"] = log.timerLabel
            row["timerElapsed"] = log.timerElapsed
            row["countLabel"] = log.countLabel
            row["count"] = log.countValue
            row["table"] = log.tableData?.prefix(20).map { $0.mapValues { clipped($0, limit: 256) } }
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
        let includeContent = (try input.bool("raw") ?? false) || format != "structured"
        if includeContent { try await context.confirm("Share captured request and resource URLs with the Mac?") }
        let navigator = context.navigator
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
        }
        let pageRequests = try paginate(input, requests)
        let pageResources = try paginate(input, resources)
        var result: [String: Any] = [
            "retained": document == nil, "capture": navigator.networkManager.isCapturing,
            "resourceCapture": navigator.resourceManager.isCapturing, "requestCount": requests.count, "resourceCount": resources.count
        ]
        let rows = pageRequests.map { networkRecord($0, includeContent: includeContent) }
        let timings = pageResources.map { resourceRecord($0, includeContent: includeContent) }
        switch format {
        case "json":
            let data = try JSONSerialization.data(withJSONObject: ["requests": rows, "resources": timings])
            result["export"] = String(bytes: data, encoding: .utf8)
        case "text":
            let lines = pageRequests.map { "\($0.method) \($0.url) \($0.status.map(String.init) ?? "–")" }
                + pageResources.map { "\($0.initiatorType.rawValue) \($0.name) \($0.displayDuration)" }
            result["export"] = clipped(lines.joined(separator: "\n"), limit: 32_768)
        default:
            result["requests"] = rows
            result["resources"] = timings
        }
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
            if includeContent { row["stack"] = try request.stackFrames.map { try AgentTool.json(Array($0.prefix(50))) } }
        }
        return row
    }

    private static func networkRecord(_ request: NetworkRequest, includeContent: Bool) -> [String: Any] {
        var row: [String: Any] = [
            "id": request.id.uuidString, "type": request.requestType.rawValue,
            "timestamp": request.startTime.timeIntervalSince1970,
            "method": clipped(request.method, limit: 32),
            "url": includeContent ? clipped(request.url) : safeURL(request.url),
            "pending": request.isPending, "failed": request.error != nil || (request.status ?? 0) >= 400,
            "mixedContent": request.isMixedContent
        ]
        row["documentId"] = request.agentDocumentID?.uuidString
        row["status"] = request.status
        row["durationMs"] = request.duration.map { $0 * 1000 }
        if includeContent {
            row["error"] = request.error.map { clipped($0) }
            row["statusText"] = request.statusText.map { clipped($0) }
        }
        return row
    }

    private static func resourceRecord(_ entry: ResourceEntry, includeContent: Bool) -> [String: Any] {
        var row: [String: Any] = [
            "id": entry.id.uuidString, "type": entry.initiatorType.rawValue,
            "timestamp": entry.timestamp.timeIntervalSince1970,
            "url": includeContent ? clipped(entry.name) : safeURL(entry.name),
            "startMs": entry.startTime, "durationMs": entry.duration,
            "transferBytes": entry.transferSize, "encodedBytes": entry.encodedBodySize, "decodedBytes": entry.decodedBodySize,
            "dnsMs": entry.dnsTime, "tcpMs": entry.tcpTime, "tlsMs": entry.tlsTime,
            "requestMs": entry.requestTime, "responseMs": entry.responseTime, "crossOriginRestricted": entry.isCrossOriginRestricted
        ]
        row["documentId"] = entry.agentDocumentID?.uuidString
        return row
    }
}
