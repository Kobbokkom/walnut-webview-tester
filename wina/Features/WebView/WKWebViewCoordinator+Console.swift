//
//  WKWebViewCoordinator+Console.swift
//  wina
//
//  Console message handling for WKWebViewCoordinator.
//

import os
import WebKit

// MARK: - Console Message Handling

extension WKWebViewCoordinator {
    func handleConsoleMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              let msg = body["message"] as? String else {
            return
        }
        var messageText = msg
        let source = body["source"] as? String

        // Parse styledSegments if present
        var styledSegments: [[String: Any]]?
        if let segments = body["styledSegments"] as? [[String: Any]] {
            styledSegments = segments
        }

        let argValues = body["args"] as? [Any]
        if let argValues {
            let argTypes = argValues.prefix(5).map { item -> String in
                if let dict = item as? [String: Any], let argType = dict["type"] as? String {
                    return argType
                }
                return "unknown"
            }
            let preview = String(msg.prefix(200))
            logger.debug("Console message type=\(type, privacy: .public) msgLen=\(msg.count, privacy: .public) args=\(argValues.count, privacy: .public) styled=\(styledSegments?.count ?? 0, privacy: .public)")
            logger.debug("Console message preview: \(preview, privacy: .public)")
            logger.debug("Console args types: \(argTypes.joined(separator: ","), privacy: .public)")
            if let first = argValues.first {
                logger.debug("Console first arg raw: \(String(describing: first), privacy: .public)")
            }
        } else {
            logger.debug("Console message type=\(type, privacy: .public) msgLen=\(msg.count, privacy: .public) args=0 styled=\(styledSegments?.count ?? 0, privacy: .public)")
        }

        var objectValue: ConsoleValue?
        var inlineSegments: [ConsoleInlineSegment]?
        if let args = body["args"] as? [Any] {
            let parsedValues = args.compactMap { ConsoleValue.fromSerializedAny($0) }
            let hasExpandable = parsedValues.contains(where: { $0.isExpandable })

            if hasExpandable {
                if parsedValues.count == 1, let value = parsedValues.first {
                    messageText = ""
                    objectValue = value
                } else if let firstStringIndex = parsedValues.firstIndex(where: {
                    if case .string = $0 { return true }
                    return false
                }) {
                    if case .string(let label) = parsedValues[firstStringIndex] {
                        messageText = label
                    }
                    let remaining = parsedValues.enumerated().filter { $0.offset != firstStringIndex }.map(\.element)
                    objectValue = remaining.count == 1 ? remaining[0] : .array(ConsoleArray(elements: remaining, depth: 0))
                } else {
                    messageText = ""
                    objectValue = parsedValues.count == 1 ? parsedValues[0] : .array(ConsoleArray(elements: parsedValues, depth: 0))
                }
            } else if parsedValues.count == 1, case .string(let only) = parsedValues[0] {
                messageText = only
            }

            if objectValue == nil, styledSegments?.isEmpty ?? true {
                inlineSegments = buildInlineSegments(from: args, hasExpandable: hasExpandable)
            }
        }

        if objectValue != nil {
            messageText = messageText
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        navigator?.consoleManager.addLog(
            type: type,
            message: messageText,
            source: source,
            objectValue: objectValue,
            styledSegments: styledSegments,
            inlineSegments: inlineSegments
        )
    }

    func buildInlineSegments(from args: [Any], hasExpandable: Bool) -> [ConsoleInlineSegment]? {
        guard !hasExpandable else { return nil }
        guard args.count >= 2 else { return nil }

        if let format = stringValue(from: args.first) {
            if hasFormatSpecifiers(format) {
                return parseFormatSegments(format: format, args: args)
            }
            return joinSegments(label: format, values: Array(args.dropFirst()))
        }

        return joinValueSegments(args)
    }

    func hasFormatSpecifiers(_ format: String) -> Bool {
        format.range(of: "%[sdifoOc%]", options: .regularExpression) != nil
    }

    func parseFormatSegments(format: String, args: [Any]) -> [ConsoleInlineSegment] {
        var segments: [ConsoleInlineSegment] = []
        var buffer = ""
        var index = format.startIndex
        var argIndex = 1

        func flushBuffer() {
            if !buffer.isEmpty {
                segments.append(ConsoleInlineSegment(text: buffer, kind: nil))
                buffer = ""
            }
        }

        while index < format.endIndex {
            let char = format[index]
            if char == "%" {
                let nextIndex = format.index(after: index)
                if nextIndex < format.endIndex {
                    let spec = format[nextIndex]
                    switch spec {
                    case "%":
                        buffer.append("%")
                    case "c":
                        flushBuffer()
                        argIndex += 1
                    case "s", "d", "i", "f", "o", "O":
                        flushBuffer()
                        if argIndex < args.count, let seg = inlineSegment(for: args[argIndex]) {
                            segments.append(seg)
                        }
                        argIndex += 1
                    default:
                        buffer.append("%")
                        buffer.append(spec)
                    }
                    index = format.index(after: nextIndex)
                    continue
                }
            }
            buffer.append(char)
            index = format.index(after: index)
        }

        flushBuffer()

        while argIndex < args.count {
            segments.append(ConsoleInlineSegment(text: " ", kind: nil))
            if let seg = inlineSegment(for: args[argIndex]) {
                segments.append(seg)
            }
            argIndex += 1
        }

        return segments
    }

    func joinSegments(label: String, values: [Any]) -> [ConsoleInlineSegment] {
        var segments: [ConsoleInlineSegment] = [ConsoleInlineSegment(text: label, kind: nil)]
        for value in values {
            segments.append(ConsoleInlineSegment(text: " ", kind: nil))
            if let seg = inlineSegment(for: value) {
                segments.append(seg)
            }
        }
        return segments
    }

    func joinValueSegments(_ args: [Any]) -> [ConsoleInlineSegment]? {
        var segments: [ConsoleInlineSegment] = []
        for (idx, value) in args.enumerated() {
            if idx > 0 {
                segments.append(ConsoleInlineSegment(text: " ", kind: nil))
            }
            if let seg = inlineSegment(for: value) {
                segments.append(seg)
            }
        }
        return segments.isEmpty ? nil : segments
    }

    func stringValue(from raw: Any?) -> String? {
        guard let dict = raw as? [String: Any],
              let type = dict["type"] as? String,
              type == "string" else {
            return nil
        }
        return dict["value"] as? String ?? ""
    }

    func inlineSegment(for raw: Any) -> ConsoleInlineSegment? {
        guard let dict = raw as? [String: Any],
              let type = dict["type"] as? String else {
            return nil
        }

        switch type {
        case "string":
            return ConsoleInlineSegment(text: dict["value"] as? String ?? "", kind: .string)
        case "number":
            return ConsoleInlineSegment(text: formattedNumber(dict["value"]), kind: .number)
        case "boolean":
            let value = dict["value"] as? Bool ?? false
            return ConsoleInlineSegment(text: value ? "true" : "false", kind: .boolean)
        case "null":
            return ConsoleInlineSegment(text: "null", kind: .null)
        case "undefined":
            return ConsoleInlineSegment(text: "undefined", kind: .undefined)
        case "function":
            let name = dict["name"] as? String ?? "anonymous"
            return ConsoleInlineSegment(text: "[Function: \(name)]", kind: .function)
        case "date":
            let value = dict["value"] as? String ?? ""
            return ConsoleInlineSegment(text: "Date(\(value))", kind: .date)
        case "symbol":
            let value = dict["value"] as? String ?? "Symbol()"
            return ConsoleInlineSegment(text: value, kind: .symbol)
        case "bigint":
            let value = dict["value"] as? String ?? "0n"
            return ConsoleInlineSegment(text: value, kind: .bigint)
        case "regexp":
            let value = dict["value"] as? String ?? "/(?:)/"
            return ConsoleInlineSegment(text: value, kind: .regexp)
        case "error":
            let message = dict["message"] as? String ?? "Error"
            let stack = dict["stack"] as? String
            let text = stack?.isEmpty == false ? "Error: \(message)\n\(stack ?? "")" : "Error: \(message)"
            return ConsoleInlineSegment(text: text, kind: .error)
        case "dom":
            let tag = dict["tag"] as? String ?? "element"
            let attributes = dict["attributes"] as? [String: String] ?? [:]
            let id = attributes["id"].map { $0.isEmpty ? "" : "#\($0)" } ?? ""
            let classList = attributes["class"]
                .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: ".") } ?? ""
            let classSuffix = classList.isEmpty ? "" : ".\(classList)"
            return ConsoleInlineSegment(text: "<\(tag)\(id)\(classSuffix)>", kind: .dom)
        case "map":
            let entries = dict["entries"] as? [[String: Any]] ?? []
            return ConsoleInlineSegment(text: "Map(\(entries.count)) { ... }", kind: .map)
        case "set":
            let values = dict["values"] as? [Any] ?? []
            return ConsoleInlineSegment(text: "Set(\(values.count)) { ... }", kind: .set)
        case "array":
            let length = dict["length"] as? Int ?? 0
            return ConsoleInlineSegment(text: "[ \(length) items ]", kind: .array)
        case "object":
            let props = dict["properties"] as? [String: Any] ?? [:]
            return ConsoleInlineSegment(text: "{ \(props.count) properties }", kind: .object)
        case "circular":
            let path = dict["path"] as? String ?? "root"
            return ConsoleInlineSegment(text: "[Circular \(path)]", kind: .circular)
        default:
            return nil
        }
    }

    func formattedNumber(_ value: Any?) -> String {
        if let number = value as? NSNumber {
            return ConsoleValue.formatNumber(number.doubleValue)
        }
        return String(describing: value ?? "")
    }
}
