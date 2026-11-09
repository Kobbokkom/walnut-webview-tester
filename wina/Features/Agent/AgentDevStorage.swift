import Foundation

@MainActor
extension AgentDevTools {
    static let storageTools: [[String: Any]] = [
        AgentTool.definition("storage_list", "Read Local Storage, Session Storage and cookies. An all-types read returns per-type errors for unavailable storage. Values, key search, and all-domain access require confirmation.", [
            "type": options(["all", "localStorage", "sessionStorage", "cookies"]), "query": query,
            "cookieScope": options(["current", "all"]), "raw": raw,
            "decode": flag, "offset": offset, "limit": limit
        ]),
        AgentTool.definition("storage_write", "Add, edit, or remove a storage entry. Requires confirmation.", [
            "action": options(["add", "edit", "remove"]), "type": options(StorageItem.StorageType.self),
            "key": query, "value": text, "newKey": query, "domain": query, "path": query, "encode": flag
        ], required: ["action", "type", "key"]),
        AgentTool.definition("storage_clear", "Clear the current document's Local Storage or Session Storage, or current-domain/all cookies. Requires confirmation.", [
            "type": options(StorageItem.StorageType.self), "cookieScope": options(["current", "all"])
        ], required: ["type"])
    ]

    static func callStorage(
        _ tool: String,
        _ input: AgentDevInput,
        _ context: AgentDevContext,
        _ storage: StorageManager
    ) async throws -> Any {
        guard let pageURL = context.navigator.attachedPageURL, let host = pageURL.host else {
            throw AgentError("Load a page with a host before using Storage.")
        }
        let scope = try input.string("cookieScope") ?? "current"
        guard ["current", "all"].contains(scope) else { throw AgentError("Invalid cookie scope.") }
        switch tool {
        case "storage_list":
            return try await listStorage(input, context, pageURL, allCookies: scope == "all")
        case "storage_write":
            return try await writeStorage(input, context, storage, pageURL)
        case "storage_clear":
            guard let type = try input.option("type", as: StorageItem.StorageType.self) else {
                throw AgentError("A storage type is required.")
            }
            let target = type == .cookies && scope == "all" ? "all cookies in this WebView's data store" : "\(type.rawValue) for \(host)"
            try await context.confirm("Clear \(target)?")
            storage.setNavigator(context.navigator)
            let success = if type == .cookies && scope == "current" {
                await storage.clearCookies(forDomain: host)
            } else {
                await storage.clearStorage(type: type, pageURL: pageURL)
            }
            guard success else {
                try context.checkDocument()
                throw AgentError("Walnut could not clear the selected storage.")
            }
            refreshStorageIfCurrent(storage, pageURL: pageURL, context: context)
            return ["cleared": true]
        default:
            throw AgentError("Unknown storage tool.")
        }
    }

    private static func listStorage(
        _ input: AgentDevInput,
        _ context: AgentDevContext,
        _ pageURL: URL,
        allCookies: Bool
    ) async throws -> [String: Any] {
        let typeName = try input.string("type") ?? "all"
        let type = StorageItem.StorageType(rawValue: typeName)
        guard type != nil || typeName == "all" else { throw AgentError("Invalid storage type.") }
        let query = try input.string("query") ?? ""
        let decode = try input.bool("decode") ?? false
        let includeContent = try input.bool("raw") ?? false
        if includeContent || allCookies || !query.isEmpty {
            try await context.confirm("Inspect \(allCookies ? "all domains' cookies and" : "the active page's") WebView storage on the Mac?")
        }
        var candidates: [StorageItem] = []
        var errors: [String: String] = [:]
        for storageType in type.map({ [$0] }) ?? StorageItem.StorageType.allCases {
            do {
                candidates += try await StorageManager.readItems(
                    type: storageType, pageURL: pageURL, allCookies: allCookies, navigator: context.navigator
                )
            } catch {
                try context.checkDocument()
                guard type == nil else { throw error }
                errors[storageType.rawValue] = error.localizedDescription
            }
            try context.checkDocument()
        }
        let items = candidates.filter { item in
            return query.isEmpty || item.key.localizedCaseInsensitiveContains(query) || item.value.localizedCaseInsensitiveContains(query)
                || item.cookieMetadata?.domain.localizedCaseInsensitiveContains(query) == true
                || item.cookieMetadata?.path.localizedCaseInsensitiveContains(query) == true
        }
        let entries = try paginate(input, items).map { item -> [String: Any] in
            var row: [String: Any] = ["type": item.storageType.rawValue, "valueBytes": item.value.utf8.count]
            if includeContent {
                row["key"] = clipped(item.key)
                row["value"] = clipped(decode ? (item.value.removingPercentEncoding ?? item.value) : item.value, limit: 16_384)
                if let cookie = item.cookieMetadata {
                    row["domain"] = cookie.domain
                    row["path"] = cookie.path
                    row["secure"] = cookie.isSecure
                    row["httpOnly"] = cookie.isHTTPOnly
                    row["sameSite"] = cookie.sameSitePolicy
                    row["expires"] = cookie.expiresDate?.timeIntervalSince1970
                }
            }
            return row
        }
        var result: [String: Any] = ["total": items.count, "entries": entries]
        if !errors.isEmpty { result["errors"] = errors }
        return result
    }

    private static func writeStorage(
        _ input: AgentDevInput,
        _ context: AgentDevContext,
        _ storage: StorageManager,
        _ pageURL: URL
    ) async throws -> [String: Any] {
        let action = try input.required("action")
        guard ["add", "edit", "remove"].contains(action),
              let type = try input.option("type", as: StorageItem.StorageType.self) else {
            throw AgentError("A supported storage action and type are required.")
        }
        let key = try input.required("key")
        let newKey = try input.string("newKey") ?? key
        let domain = try input.string("domain")
        let path = try input.string("path")
        let encode = try input.bool("encode") ?? false
        var value = action == "remove" ? "" : try input.required("value", maxLength: 16_384, allowEmpty: true)
        if encode {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
                throw AgentError("Could not URL-encode the storage value.")
            }
            value = encoded
        }
        if let domain {
            let validCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-:[]"))
            guard !domain.isEmpty, domain.unicodeScalars.allSatisfy(validCharacters.contains) else {
                throw AgentError("Invalid cookie domain.")
            }
        }
        if action == "add", type == .cookies,
           domain.map({ $0.caseInsensitiveCompare(pageURL.host ?? "") != .orderedSame }) == true || (path != nil && path != "/") {
            throw AgentError("Add creates a cookie for the current host at /. Use the startup profile for a custom cookie scope.")
        }
        let target = type == .cookies && action != "add" ? (domain ?? pageURL.host) : pageURL.host
        try await context.confirm("Allow the Mac to \(action) a \(type.rawValue) entry for \(target ?? "the active page")?")
        let success: Bool
        if action == "add" {
            storage.setNavigator(context.navigator)
            success = await storage.addItem(key: key, value: value, type: type, pageURL: pageURL, cookieAtRoot: true) {
                (try? context.checkDocument()) != nil
            }
        } else {
            let candidates = try await StorageManager.readItems(
                type: type, pageURL: pageURL, allCookies: domain != nil, navigator: context.navigator
            )
            try context.checkDocument()
            let matches = candidates.filter { item in
                guard item.key == key else { return false }
                guard let cookie = item.cookieMetadata else { return true }
                let matchingDomain = domain.map { cookie.domain.caseInsensitiveCompare($0) == .orderedSame }
                    ?? true
                return matchingDomain && (path == nil || cookie.path == path)
            }
            guard matches.count == 1, let item = matches.first else {
                throw AgentError("Storage entry not found or ambiguous. Supply the exact cookie domain and path if needed.")
            }
            storage.setNavigator(context.navigator)
            success = if action == "edit" {
                await storage.updateItem(item, key: newKey, value: value)
            } else {
                await storage.removeItem(item)
            }
        }
        guard success else {
            try context.checkDocument()
            throw AgentError(storage.errorMessage ?? "Walnut could not change the storage entry.")
        }
        refreshStorageIfCurrent(storage, pageURL: pageURL, context: context)
        return ["action": action, "applied": true]
    }

    private static func refreshStorageIfCurrent(_ storage: StorageManager, pageURL: URL, context: AgentDevContext) {
        // Refresh the inspector independently of a mutation already committed to the authorized storage.
        Task {
            await storage.refresh(pageURL: pageURL) {
                context.navigator.attachedPageURL == pageURL && (try? context.checkDocument()) != nil
            }
        }
    }
}
