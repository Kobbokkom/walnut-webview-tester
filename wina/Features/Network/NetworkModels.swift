//
//  NetworkModels.swift
//  wina
//
//  Network request models and content types.
//

import SwiftUI

// MARK: - Stack Frame (for request initiator tracking)

struct StackFrame: Identifiable, Equatable, Codable {
    let id: UUID
    let functionName: String
    let fileName: String
    let lineNumber: Int
    let columnNumber: Int

    init(id: UUID = UUID(), functionName: String, fileName: String, lineNumber: Int, columnNumber: Int) {
        self.id = id
        self.functionName = functionName
        self.fileName = fileName
        self.lineNumber = lineNumber
        self.columnNumber = columnNumber
    }

    /// Display format: "functionName (fileName:lineNumber:columnNumber)"
    var displayText: String {
        "\(functionName) (\(fileName):\(lineNumber):\(columnNumber))"
    }

    /// Just file name without path
    var displayFileName: String {
        (fileName as NSString).lastPathComponent
    }
}

// MARK: - Network Request Model

struct NetworkRequest: Identifiable, Equatable {
    let id: UUID
    let method: String
    let url: String
    let requestHeaders: [String: String]?
    var requestBodyPreview: String?  // First 500 chars for list display
    let startTime: Date
    let pageIsSecure: Bool  // Whether the page was HTTPS when this request was made
    var status: Int?
    var statusText: String?
    var responseHeaders: [String: String]?
    var responseBodyPreview: String?  // First 500 chars for list display
    var endTime: Date?
    var error: String?
    var requestType: RequestType
    var stackFrames: [StackFrame]?  // JavaScript call stack at request time
    var initiatorFunction: String?  // Top-level function name from stack

    // Preview length for memory storage
    static let previewLength = 500

    // Load full body from disk (for detail view, copy, share)
    func loadFullRequestBody() -> String? {
        NetworkBodyStorage.shared.load(id: id, type: .request)
    }

    func loadFullResponseBody() -> String? {
        NetworkBodyStorage.shared.load(id: id, type: .response)
    }

    // Convenience: return full body if available, otherwise preview
    var requestBody: String? {
        loadFullRequestBody() ?? requestBodyPreview
    }

    var curlCommand: String {
        func shellArgument(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }

        var command = "curl --globoff --proto '=http,https' --request \(shellArgument(method)) --url \(shellArgument(url))"
        for (name, value) in (requestHeaders ?? [:]).sorted(by: { $0.key < $1.key }) where !name.hasPrefix("@") {
            command += " \\\n  --header \(shellArgument("\(name): \(value)"))"
        }
        if let body = requestBody, !body.isEmpty {
            command += " \\\n  --data-raw \(shellArgument(body))"
        }
        return command
    }

    var responseBody: String? {
        loadFullResponseBody() ?? responseBodyPreview
    }

    enum RequestType: String, CaseIterable {
        case fetch
        case xhr
        case document
        case other

        var icon: String {
            switch self {
            case .fetch: return "arrow.down.doc"
            case .xhr: return "arrow.triangle.2.circlepath"
            case .document: return "doc.text"
            case .other: return "questionmark.circle"
            }
        }

        var label: String {
            switch self {
            case .fetch: return "Fetch"
            case .xhr: return "XHR"
            case .document: return "Doc"
            case .other: return "Other"
            }
        }
    }

    var duration: TimeInterval? {
        guard let endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }

    var durationText: String {
        guard let duration else { return "..." }
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else {
            return String(format: "%.2fs", duration)
        }
    }

    var statusColor: Color {
        guard let status else { return .secondary }
        switch status {
        case 200..<300: return .secondary  // Success - no highlight needed
        case 300..<400: return .secondary  // Redirects - subtle
        case 400..<500: return .orange.opacity(0.8)
        case 500...: return .red.opacity(0.8)
        default: return .secondary
        }
    }

    var isComplete: Bool {
        endTime != nil || error != nil
    }

    var isPending: Bool {
        !isComplete
    }

    /// Whether this request URL uses HTTPS
    var isSecure: Bool {
        url.lowercased().hasPrefix("https://")
    }

    /// Mixed content: page is HTTPS but this request is HTTP
    var isMixedContent: Bool {
        pageIsSecure && !isSecure
    }

    /// Security icon for display
    var securityIcon: String {
        if isMixedContent {
            return "exclamationmark.shield.fill"
        } else if isSecure {
            return "lock.fill"
        } else {
            return "lock.open.fill"
        }
    }

    /// Security icon color
    var securityIconColor: Color {
        if isMixedContent {
            return .orange
        } else if isSecure {
            return .green
        } else {
            return .secondary
        }
    }

    // Extract host from URL
    var host: String {
        guard let parsedURL = URL(string: url) else { return url }
        return parsedURL.host ?? url
    }

    // Extract path from URL
    var path: String {
        guard let url = URL(string: url) else { return self.url }
        return url.path.isEmpty ? "/" : url.path
    }

    // Response content type from headers or body detection
    var responseContentType: String {
        // Check Content-Type header first
        if let contentTypeHeader = responseHeaders?["Content-Type"] ?? responseHeaders?["content-type"] {
            if contentTypeHeader.contains("application/json") {
                return "JSON"
            } else if contentTypeHeader.contains("text/html") {
                return "HTML"
            } else if contentTypeHeader.contains("text/xml") || contentTypeHeader.contains("application/xml") {
                return "XML"
            } else if contentTypeHeader.contains("text/plain") {
                return "Text"
            } else if contentTypeHeader.contains("text/css") {
                return "CSS"
            } else if contentTypeHeader.contains("javascript") {
                return "JS"
            } else if contentTypeHeader.contains("image/") {
                return "Image"
            } else if contentTypeHeader.contains("font/") {
                return "Font"
            }
        }

        // Fallback: detect from body content (use preview to avoid disk I/O)
        guard let body = responseBodyPreview else { return "—" }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return "JSON"
        }
        if trimmed.hasPrefix("<!DOCTYPE") || trimmed.hasPrefix("<html") {
            return "HTML"
        }
        if trimmed.hasPrefix("<?xml") {
            return "XML"
        }
        return "Text"
    }

    // Color for response content type (muted, subtle)
    var responseContentTypeColor: Color {
        switch responseContentType {
        case "JSON": return .purple.opacity(0.7)
        case "HTML": return .orange.opacity(0.6)
        case "XML": return .teal.opacity(0.7)
        case "CSS": return .pink.opacity(0.6)
        case "JS": return .yellow.opacity(0.7)
        case "Image": return .green.opacity(0.6)
        case "Font": return .cyan.opacity(0.6)
        case "Text": return .secondary
        default: return .gray
        }
    }

    static func == (lhs: NetworkRequest, rhs: NetworkRequest) -> Bool {
        lhs.id == rhs.id &&
        lhs.status == rhs.status &&
        lhs.endTime == rhs.endTime &&
        lhs.error == rhs.error
    }
}

// MARK: - Content Type

enum NetworkContentType: String {
    case json = "JSON"
    case html = "HTML"
    case xml = "XML"
    case text = "Text"
    case formUrlEncoded = "Form Data"

    var color: Color {
        switch self {
        case .json: return .purple.opacity(0.7)
        case .html: return .orange.opacity(0.6)
        case .xml: return .teal.opacity(0.7)
        case .text: return .secondary
        case .formUrlEncoded: return .blue.opacity(0.7)
        }
    }

    var icon: String {
        switch self {
        case .json: return "curlybraces"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .xml: return "chevron.left.forwardslash.chevron.right"
        case .text: return "doc.text"
        case .formUrlEncoded: return "list.bullet.rectangle"
        }
    }

    var badge: TypeBadge {
        TypeBadge(text: rawValue, color: color, icon: icon)
    }
}

// MARK: - Share Content

struct NetworkShareContent: Identifiable {
    let id = UUID()
    let content: String
}

// Extension to make URL work with sheet(item:)
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
