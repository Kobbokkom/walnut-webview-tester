import CryptoKit
import Foundation

@MainActor
extension AgentDevTools {
    static let storageTools: [[String: Any]] = [
        AgentTool.definition("storage_list", "Read or export Local Storage, Session Storage and cookies. Domain and path filter exact cookie scopes. For text export, resume with nextOffset and pass nextByteOffset and nextRowId as byteOffset and rowId when present. Use the same filters. Append a byte continuation directly to its prior export. Values, filters, exports, and all-domain access require confirmation.", [
            "type": options(["all", "localStorage", "sessionStorage", "cookies"]), "query": query,
            "cookieScope": options(["current", "all"]), "domain": query, "path": query, "raw": raw,
            "format": options(["structured", "text"]), "byteOffset": [
                "type": "integer", "minimum": 0, "maximum": 16 * 1024 * 1024
            ],
            "rowId": ["type": "string", "minLength": 64, "maxLength": 64],
            "decode": flag, "offset": offset, "limit": limit
        ]),
        AgentTool.definition("storage_write", "Add, edit, or remove a storage entry. Cookie additions default to the current host at / and can specify a domain and path allowed by WebKit. Edit or remove an existing cookie across the store by specifying its exact domain, or set cookieScope to current to limit the lookup to the active host. Requires confirmation.", [
            "action": options(["add", "edit", "remove"]), "type": options(StorageItem.StorageType.self),
            "key": query, "value": text, "newKey": query, "domain": query, "path": query, "encode": flag,
            "cookieScope": options(["current", "all"])
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
        let scope = try input.string("cookieScope")
        guard scope == nil || scope == "current" || scope == "all" else { throw AgentError("Invalid cookie scope.") }
        switch tool {
        case "storage_list":
            return try await listStorage(input, context, pageURL, allCookies: scope == "all")
        case "storage_write":
            return try await writeStorage(input, context, storage, pageURL, scope: scope)
        case "storage_clear":
            guard let type = try input.option("type", as: StorageItem.StorageType.self) else {
                throw AgentError("A storage type is required.")
            }
            let target = type == .cookies && scope == "all" ? "all cookies in this WebView's data store" : "\(type.rawValue) for \(host)"
            try await context.confirm("Clear \(target)?")
            storage.setNavigator(context.navigator)
            let isCurrentDocument = { (try? context.checkDocument()) != nil }
            let success = if type == .cookies && scope != "all" {
                await storage.clearCookies(forDomain: host, agentDocumentIsCurrent: isCurrentDocument)
            } else {
                await storage.clearStorage(type: type, pageURL: pageURL, agentDocumentIsCurrent: isCurrentDocument)
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
        let domain = try input.string("domain")
        let path = try input.string("path")
        let hasCookieFilter = domain != nil || path != nil
        let typeName = try input.string("type") ?? (hasCookieFilter ? "cookies" : "all")
        let type = StorageItem.StorageType(rawValue: typeName)
        guard type != nil || typeName == "all" else { throw AgentError("Invalid storage type.") }
        guard !hasCookieFilter || type == nil || type == .cookies else { throw AgentError("Domain and path are cookie filters.") }
        let format = try input.string("format") ?? "structured"
        guard ["structured", "text"].contains(format) else { throw AgentError("Invalid storage format.") }
        let byteOffset = try input.int("byteOffset", default: 0, range: 0...(16 * 1024 * 1024))
        guard format == "text" || byteOffset == 0 else { throw AgentError("A byte offset requires text export.") }
        let rowId = try input.string("rowId", maxLength: 64)
        guard (byteOffset > 0) == (rowId != nil), rowId.map({ $0.utf8.count == 64 && $0.utf8.allSatisfy(isHexDigit) }) ?? true else {
            throw AgentError("A text export continuation requires its byte offset and row ID.")
        }
        let query = try input.string("query") ?? ""
        let decode = try input.bool("decode") ?? false
        let includeContent = try input.bool("raw") ?? false
        if includeContent || allCookies || hasCookieFilter || !query.isEmpty || format == "text" {
            let action = format == "text" ? "Export" : "Inspect"
            try await context.confirm("\(action) \(allCookies ? "all domains' cookies and" : "the active page's") WebView storage on the Mac?")
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
            guard matchesCookieScope(item, domain: domain, path: path) else { return false }
            return query.isEmpty || item.key.localizedCaseInsensitiveContains(query) || item.value.localizedCaseInsensitiveContains(query)
                || item.cookieMetadata?.domain.localizedCaseInsensitiveContains(query) == true
                || item.cookieMetadata?.path.localizedCaseInsensitiveContains(query) == true
        }
        var result: [String: Any] = ["total": items.count]
        if !errors.isEmpty { result["errors"] = errors }
        if format == "text" {
            let sorted = items.sorted {
                ($0.storageType.sortOrder, $0.key, $0.cookieMetadata?.domain ?? "", $0.cookieMetadata?.path ?? "")
                    < ($1.storageType.sortOrder, $1.key, $1.cookieMetadata?.domain ?? "", $1.cookieMetadata?.path ?? "")
            }
            let page = try paginate(input, sorted)
            let export = try exportStorage(page, type: type, decode: decode, total: items.count, byteOffset: byteOffset, rowId: rowId)
            result.merge(export) { _, new in new }
            return result
        }
        result["entries"] = try paginate(input, items).map { item -> [String: Any] in
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
        return result
    }

    private static func exportStorage(
        _ page: ArraySlice<StorageItem>, type: StorageItem.StorageType?, decode: Bool, total: Int, byteOffset: Int, rowId: String?
    ) throws -> [String: Any] {
        guard byteOffset == 0 || !page.isEmpty else { throw AgentError("No storage entry to continue exporting.") }
        var output = byteOffset == 0 ? StorageExporter.heading(for: type) : ""
        var remaining = 256 * 1024 - output.utf8.count
        var rowOffset = byteOffset
        var exported = 0
        for item in page {
            let line = StorageExporter.line(item, includeType: type == nil, decode: decode)
            let digest = rowOffset == 0 ? nil : exportRowId(line)
            if let digest, digest != rowId {
                throw AgentError("The storage export row changed. Restart this export page.")
            }
            let bytes = line.utf8.dropFirst(rowOffset)
            guard let first = bytes.first, first & 0xc0 != 0x80 else { throw AgentError("Invalid storage entry byte offset.") }
            var end = bytes.endIndex
            if bytes.count > remaining {
                guard exported == 0 else { break }
                end = bytes.index(bytes.startIndex, offsetBy: remaining)
                while bytes[end] & 0xc0 == 0x80 { end = bytes.index(before: end) }
            }
            let chunk = bytes[..<end]
            guard let text = String(bytes: chunk, encoding: .utf8) else { throw AgentError("Could not encode the storage export.") }
            output += text
            if end != bytes.endIndex {
                return [
                    "export": output, "exported": exported, "exportTruncated": true,
                    "nextOffset": page.startIndex + exported, "nextByteOffset": rowOffset + chunk.count,
                    "nextRowId": digest ?? exportRowId(line)
                ]
            }
            remaining -= chunk.count
            rowOffset = 0
            exported += 1
        }
        var result: [String: Any] = ["export": output, "exported": exported, "exportTruncated": false]
        let nextOffset = page.startIndex + exported
        if nextOffset < total { result["nextOffset"] = nextOffset }
        return result
    }

    private static func exportRowId(_ line: String) -> String {
        SHA256.hash(data: Data(line.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (97...102).contains(byte)
    }

    private static func matchesCookieScope(_ item: StorageItem, domain: String?, path: String?) -> Bool {
        guard let cookie = item.cookieMetadata else { return true }
        let domainMatches = domain.map { cookie.domain.caseInsensitiveCompare($0) == .orderedSame } ?? true
        return domainMatches && (path == nil || cookie.path == path)
    }

    private static func writeStorage(
        _ input: AgentDevInput,
        _ context: AgentDevContext,
        _ storage: StorageManager,
        _ pageURL: URL,
        scope: String?
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
        guard type == .cookies || (domain == nil && path == nil && scope == nil) else {
            throw AgentError("Domain, path and cookie scope are cookie options.")
        }
        guard scope != "all" || (action != "add" && domain != nil) else {
            throw AgentError("All-domain cookie edits and removals require the exact domain. Cookie additions use the active origin.")
        }
        guard path?.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) != true else {
            throw AgentError("Invalid cookie path.")
        }
        let value = try storageWriteValue(input, action: action)
        if let domain {
            let validCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-:[]"))
            guard !domain.isEmpty, domain.unicodeScalars.allSatisfy(validCharacters.contains) else {
                throw AgentError("Invalid cookie domain.")
            }
        }
        let cookieScope: StorageCookieAddScope? = if action == "add", type == .cookies {
            try cookieAddScope(domain: domain, path: path ?? "/", host: pageURL.host ?? "")
        } else {
            nil
        }
        let host = pageURL.host ?? "the active page"
        let target: String
        if let cookieScope {
            let domain = cookieScope.domain.map { "\($0) and its subdomains where WebKit allows" } ?? "\(host) (host only)"
            target = "a cookie for \(domain) at path \(cookieScope.path)"
        } else if type == .cookies {
            let cookieDomain = domain.map { "the exact domain \($0)" } ?? "a domain matching \(host)"
            let cookiePath = path.map { "at path \($0)" } ?? "at any path, if only one matches"
            target = "a cookie for \(cookieDomain) \(cookiePath)"
        } else {
            target = "a \(type.rawValue) entry for \(host)"
        }
        try await context.confirm("Allow the Mac to \(action) \(target)?")
        let isCurrentDocument = { (try? context.checkDocument()) != nil }
        var result: [String: Any] = ["action": action, "applied": true]
        let success: Bool
        if action == "add" {
            storage.setNavigator(context.navigator)
            if let cookieScope {
                let applied = await storage.addCookie(
                    key: key, value: value, pageURL: pageURL, scope: cookieScope, isCurrentDocument: isCurrentDocument
                )
                success = applied != nil
                result["domain"] = applied?.domain
                result["path"] = applied?.path
            } else {
                success = await storage.addItem(
                    key: key, value: value, type: type, pageURL: pageURL, agentDocumentIsCurrent: isCurrentDocument
                )
            }
        } else {
            let candidates = try await StorageManager.readItems(
                type: type, pageURL: pageURL, allCookies: scope != "current" && domain != nil, navigator: context.navigator
            )
            try context.checkDocument()
            let matches = candidates.filter { $0.key == key && matchesCookieScope($0, domain: domain, path: path) }
            guard matches.count == 1, let item = matches.first else {
                throw AgentError("Storage entry not found or ambiguous. Supply the exact cookie domain and path if needed.")
            }
            result["domain"] = item.cookieMetadata?.domain
            result["path"] = item.cookieMetadata?.path
            storage.setNavigator(context.navigator)
            success = if action == "edit" {
                await storage.updateItem(item, key: newKey, value: value, agentDocumentIsCurrent: isCurrentDocument)
            } else {
                await storage.removeItem(item, agentDocumentIsCurrent: isCurrentDocument)
            }
        }
        guard success else {
            try context.checkDocument()
            throw AgentError(storage.errorMessage ?? "Walnut could not change the storage entry.")
        }
        refreshStorageIfCurrent(storage, pageURL: pageURL, context: context)
        return result
    }

    private static func storageWriteValue(_ input: AgentDevInput, action: String) throws -> String {
        let encode = try input.bool("encode") ?? false
        let value = action == "remove" ? "" : try input.required("value", maxLength: 16_384, allowEmpty: true)
        guard encode else { return value }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw AgentError("Could not URL-encode the storage value.")
        }
        return encoded
    }

    private static func cookieAddScope(domain: String?, path: String, host: String) throws -> StorageCookieAddScope {
        guard path.hasPrefix("/"), path.last != " ", path.unicodeScalars.allSatisfy({ (32...126).contains($0.value) && $0 != ";" }) else {
            throw AgentError("A cookie path must start with / and contain no semicolons or non-ASCII characters. Percent-encode the path if needed.")
        }
        let host = host.lowercased()
        guard let domain = domain?.lowercased(), domain != host else { return .init(domain: nil, path: path) }
        let requestedDomain = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        let labels = host.split(separator: ".")
        let isIPv4 = labels.count == 4 && labels.allSatisfy { UInt8($0) != nil }
        let validDomain = requestedDomain.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }
        guard !isIPv4, validDomain, requestedDomain.contains("."),
              requestedDomain == host || host.hasSuffix(".\(requestedDomain)") else {
            throw AgentError("A cookie domain must match the active host or an eligible parent domain.")
        }
        return .init(domain: requestedDomain, path: path)
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
