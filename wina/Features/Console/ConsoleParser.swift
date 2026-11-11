//
//  ConsoleParser.swift
//  wina
//
//  Console log parsing utilities for JSON extraction, regex filtering, and export.
//

import Foundation

// MARK: - JSON Parser

/// Utilities for parsing and extracting JSON from console log messages
enum JSONParser {

    /// Result of JSON parsing with original, formatted, and minified versions
    struct ParsedJSON: Equatable {
        let original: String
        let formatted: String
        let minified: String
    }

    /// Parse a JSON string and return formatted versions
    /// - Parameter str: JSON string to parse
    /// - Returns: ParsedJSON with original, formatted, and minified versions, or nil if invalid
    static func parse(_ str: String) -> ParsedJSON? {
        guard let data = str.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(json),
              let formatted = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let minified = try? JSONSerialization.data(withJSONObject: json),
              let formattedStr = String(data: formatted, encoding: .utf8),
              let minifiedStr = String(data: minified, encoding: .utf8) else {
            return nil
        }
        return ParsedJSON(original: str, formatted: formattedStr, minified: minifiedStr)
    }

    /// Extract JSON from a message string (may contain non-JSON text around it)
    /// - Parameter message: Message that may contain JSON
    /// - Returns: ParsedJSON if JSON found, nil otherwise
    static func extract(from message: String) -> ParsedJSON? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if entire message is JSON
        if let result = parse(trimmed) {
            return result
        }

        // Try to find JSON object or array using regex (safe extraction)
        // Pattern matches {...} or [...] including nested structures
        let patterns = [
            "\\{[^{}]*(?:\\{[^{}]*\\}[^{}]*)*\\}",  // Simple nested objects
            "\\[[^\\[\\]]*(?:\\[[^\\[\\]]*\\][^\\[\\]]*)*\\]"  // Simple nested arrays
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range, in: trimmed) {
                let jsonPart = String(trimmed[range])
                if let result = parse(jsonPart) {
                    return result
                }
            }
        }

        return nil
    }

    /// Pretty-print a string if it's valid JSON, otherwise return original
    /// - Parameter str: String to pretty-print
    /// - Returns: Pretty-printed JSON if valid, original string otherwise
    static func prettyPrintIfJSON(_ str: String) -> String {
        if let parsed = parse(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed.formatted
        }
        return str
    }

    /// Parse table data from a JSON array message (for console.table)
    /// - Parameter message: JSON array string
    /// - Returns: Array of dictionaries with string values, or nil if invalid
    static func parseTableData(from message: String) -> [[String: String]]? {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return json.map { row in
            row.mapValues { String(describing: $0) }
        }
    }
}

// MARK: - Regex Filter

/// Utilities for regex-based filtering of console logs
enum RegexFilter {

    /// Result of regex compilation
    enum CompileResult {
        case success(NSRegularExpression)
        case invalidPattern(String)
    }

    /// Compile a regex pattern
    /// - Parameter pattern: Regex pattern string
    /// - Returns: CompileResult with regex or error message
    static func compile(_ pattern: String) -> CompileResult {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            return .success(regex)
        } catch {
            return .invalidPattern(error.localizedDescription)
        }
    }

    /// Check if text matches regex pattern
    /// - Parameters:
    ///   - text: Text to search
    ///   - regex: Compiled regex
    /// - Returns: true if pattern found in text
    static func matches(_ text: String, regex: NSRegularExpression) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    /// Check if text matches regex pattern string (convenience method)
    /// - Parameters:
    ///   - text: Text to search
    ///   - pattern: Regex pattern string
    /// - Returns: true if pattern found in text, false if invalid pattern or no match
    static func matches(_ text: String, pattern: String) -> Bool {
        guard case .success(let regex) = compile(pattern) else {
            return false
        }
        return matches(text, regex: regex)
    }

    /// Filter logs by regex pattern matching message or source
    /// - Parameters:
    ///   - message: Log message
    ///   - source: Log source (optional)
    ///   - regex: Compiled regex
    /// - Returns: true if either message or source matches
    static func matchesLog(message: String, source: String?, regex: NSRegularExpression) -> Bool {
        if matches(message, regex: regex) {
            return true
        }
        if let source = source, matches(source, regex: regex) {
            return true
        }
        return false
    }
}

// MARK: - Console Exporter

/// Utilities for exporting console logs to various formats
enum ConsoleExporter {

    /// Export logs as formatted text
    /// - Returns: Formatted text string with blank lines between entries
    static func exportAsText(_ logs: [ConsoleLog], includeObjects: Bool = false) -> String {
        textLines(logs, includeObjects: includeObjects).joined(separator: "\n\n")
    }

    static func textLines(_ logs: some Collection<ConsoleLog>, includeObjects: Bool) -> some Collection<String> {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        return logs.lazy.map { log in
            var line = "[\(dateFormatter.string(from: log.timestamp))] [\(log.type.shortLabel)] \(log.message)"
            if let source = log.source {
                line += " (\(source))"
            }
            if includeObjects, let object = log.objectValue {
                line += "\n" + object.copyableString
            }
            return line
        }
    }

    /// Export logs as JSON array
    /// - Parameter logs: Array of ConsoleLog
    /// - Returns: Pretty-printed JSON string
    static func exportAsJSON(_ logs: [ConsoleLog]) -> String {
        let dateFormatter = ISO8601DateFormatter()
        let logDicts: [[String: Any]] = logs.map { log in
            var dict: [String: Any] = [
                "timestamp": dateFormatter.string(from: log.timestamp),
                "type": log.type.rawValue,
                "message": log.message
            ]
            if let source = log.source {
                dict["source"] = source
            }
            return dict
        }

        if let data = try? JSONSerialization.data(withJSONObject: logDicts, options: .prettyPrinted),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return "[]"
    }
}
