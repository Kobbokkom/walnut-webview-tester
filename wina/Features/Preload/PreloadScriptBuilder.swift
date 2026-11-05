//
//  PreloadScriptBuilder.swift
//  wina
//
//  Builds WKUserScript sources and native bridge response JavaScript.
//

import Foundation

// MARK: - Script Builder

enum PreloadScriptBuilder {
    static func bootstrapScript(for profile: WebViewPreloadProfile) -> String {
        guard profile.isEnabled else { return "" }

        var blocks: [String] = [baseHelpers]
        let bridgeChannels = profile.enabledBridgeChannelNames.filter { $0 != PreloadBridgeConstants.postMessageCaptureChannel }
        if !bridgeChannels.isEmpty {
            blocks.append(bridgeDocumentScript(channels: bridgeChannels))
        }

        for item in profile.windowItems where item.isEnabled {
            if let script = windowItemScript(item) {
                blocks.append(script)
            }
        }

        if profile.capturesWindowPostMessage {
            blocks.append(postMessageCaptureScript)
        }

        return """
            (function() {
                if (window.__winaPreloadApplied) return;
                window.__winaPreloadApplied = true;
            \(blocks.joined(separator: "\n\n"))
            })();
            """
    }

    private static func bridgeDocumentScript(channels: [String]) -> String {
        let names = channels.map(JavaScriptLiteral.quoted).joined(separator: ", ")
        return """
        (function() {
            const token = Array.from(crypto.getRandomValues(new Uint32Array(4))).join('-');
            Object.defineProperty(document, '__winaBridgeDocumentToken', { value: token });
            for (const name of [\(names)]) {
                const handler = window.webkit?.messageHandlers?.[name];
                if (!handler) continue;
                const post = handler.postMessage.bind(handler);
                Object.defineProperty(handler, 'postMessage', {
                    value: body => post({ __winaBridgeDocumentToken: token, body }),
                    writable: true,
                    configurable: true
                });
            }
        })();
        """
    }

    static func customScripts(for profile: WebViewPreloadProfile) -> [(source: String, forMainFrameOnly: Bool)] {
        guard profile.isEnabled else { return [] }
        return profile.customScripts
            .filter { $0.isEnabled && !$0.source.isEmpty }
            .map { customScript in
                (
                    source: """
                    (function() {
                        try {
                    \(customScript.source)
                        } catch (error) {
                            console.warn('[Walnut Preload] custom script failed:', error);
                        }
                    })();
                    """,
                    forMainFrameOnly: customScript.forMainFrameOnly
                )
            }
    }

    static func responseScript(
        for response: BridgeResponse,
        message: Any,
        channel: String
    ) -> String {
        guard BridgeResponseBodyValidator.isValidTemplate(response.bodyTemplate) else {
            return ""
        }
        let renderedBody = BridgeTemplateRenderer.renderResponseBody(response.bodyTemplate, message: message)
        guard let responseLiteral = JavaScriptLiteral.jsonLiteral(from: renderedBody) else {
            return ""
        }
        let channelLiteral = JavaScriptLiteral.quoted(channel)

        switch response.target {
        case .postMessage:
            return """
                (function() {
                var response = \(responseLiteral);
                if (typeof window.__winaPreloadPostNativeMessage === 'function') {
                    window.__winaPreloadPostNativeMessage(response);
                } else {
                    window.postMessage(response, '*');
                }
                })();
                """

        case .customEvent:
            let eventName = JavaScriptLiteral.quoted(response.eventName)
            return "window.dispatchEvent(new CustomEvent(\(eventName), { detail: \(responseLiteral) }));"

        case .callback:
            guard JavaScriptPath.isValid(response.callbackName) else { return "" }
            let pathLiteral = JavaScriptPath.arrayLiteral(response.callbackName)
            return """
                (function() {
                    var callback = window.__winaPreloadGetPath(\(pathLiteral));
                    if (typeof callback === 'function') {
                        callback(\(responseLiteral));
                    }
                })();
                """

        case .customJavaScript:
            let messageLiteral = JavaScriptLiteral.literal(
                from: BridgeTemplateRenderer.messageJSONString(message), valueKind: .json)
            return BridgeTemplateRenderer.render(
                response.customJavaScript,
                replacements: [
                    "message": messageLiteral,
                    "response": responseLiteral,
                    "channel": channelLiteral,
                ]
            )
        }
    }

    private static func windowItemScript(_ item: WindowInjectionItem) -> String? {
        guard JavaScriptPath.isValid(item.name) else { return nil }
        let pathLiteral = JavaScriptPath.arrayLiteral(item.name)

        switch item.kind {
        case .variable:
            return
                "window.__winaPreloadSetPath(\(pathLiteral), \(JavaScriptLiteral.literal(from: item.value, valueKind: item.valueKind)));"

        case .functionReturn:
            let literal = JavaScriptLiteral.literal(from: item.value, valueKind: item.valueKind)
            return "window.__winaPreloadSetPath(\(pathLiteral), function() { return \(literal); });"

        case .functionBody:
            // Build the function from a string via `new Function` so a SYNTAX error in the
            // user's body throws a catchable error at runtime instead of failing to parse the
            // whole shared bootstrap IIFE (which would silently drop helpers + every other
            // item). The try/catch also contains runtime errors, mirroring customScripts.
            let bodyLiteral = JavaScriptLiteral.quoted(item.value)
            return """
                try {
                    window.__winaPreloadSetPath(\(pathLiteral), new Function(\(bodyLiteral)));
                } catch (error) {
                    console.warn('[Walnut Preload] window item failed:', error);
                }
                """
        }
    }

    private static let baseHelpers = """
            window.__wina = window.__wina || {};
            window.__wina.preload = window.__wina.preload || {};

            window.__winaPreloadSetPath = function(parts, value) {
                var target = window;
                for (var i = 0; i < parts.length - 1; i += 1) {
                    var key = parts[i];
                    if (!target[key] || typeof target[key] !== 'object') {
                        target[key] = {};
                    }
                    target = target[key];
                }
                target[parts[parts.length - 1]] = value;
            };

            window.__winaPreloadGetPath = function(parts) {
                var target = window;
                for (var i = 0; i < parts.length; i += 1) {
                    if (target == null) return undefined;
                    target = target[parts[i]];
                }
                return target;
            };

        """

    private static let postMessageCaptureScript = """
            (function() {
                const tokenKey = '__winaPreloadNativePostMessageToken';
                const token = String(Date.now()) + ':' + String(Math.random());
                window.__winaPreloadPostNativeMessage = function(value) {
                    window.postMessage({ [tokenKey]: token, payload: value }, '*');
                };
                // Unwrap transport metadata before page listeners, without altering the payload.
                window.addEventListener('message', function(event) {
                    try {
                        const data = event.data;
                        if (data && data[tokenKey] === token) {
                            Object.defineProperty(event, 'data', { value: data.payload });
                            return;
                        }
                        if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.winaPostMessage) {
                            return;
                        }
                        window.webkit.messageHandlers.winaPostMessage.postMessage({
                            origin: event.origin,
                            data: data
                        });
                    } catch (_) {}
                }, true);
            })();
        """
}

// MARK: - Template Rendering

enum BridgeTemplateRenderer {
    static func render(_ template: String, message: Any) -> String {
        renderResponseBody(template, message: message)
    }

    static func renderResponseBody(_ template: String, message: Any) -> String {
        renderResponseBody(
            template,
            textReplacements: messageReplacements(message),
            jsonReplacements: messageJSONLiteralReplacements(message)
        )
    }

    static func render(
        _ template: String,
        replacements: [String: String],
        unresolvedReplacement: String? = nil
    ) -> String {
        var rendered = ""
        var cursor = template.startIndex

        while let openRange = template[cursor...].range(of: "{{") {
            rendered += template[cursor..<openRange.lowerBound]

            let tokenStart = openRange.upperBound
            guard let closeRange = template[tokenStart...].range(of: "}}") else {
                rendered += template[openRange.lowerBound...]
                return rendered
            }

            let key = String(template[tokenStart..<closeRange.lowerBound])
            rendered += replacements[key]
                ?? unresolvedReplacement
                ?? String(template[openRange.lowerBound..<closeRange.upperBound])
            cursor = closeRange.upperBound
        }

        rendered += template[cursor...]
        return rendered
    }

    static func messageJSONString(_ message: Any) -> String {
        if JSONSerialization.isValidJSONObject(message),
           let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        {
            return JavaScriptLiteral.escapedJavaScriptUnsafeCharacters(text)
        }
        if let text = message as? String {
            return JavaScriptLiteral.quoted(text)
        }
        return "null"
    }

    private static func renderResponseBody(
        _ template: String,
        textReplacements: [String: String],
        jsonReplacements: [String: String]
    ) -> String {
        var rendered = ""
        var cursor = template.startIndex

        while let openRange = template[cursor...].range(of: "{{") {
            rendered += template[cursor..<openRange.lowerBound]
            let tokenStart = openRange.upperBound
            guard let closeRange = template[tokenStart...].range(of: "}}") else {
                rendered += template[openRange.lowerBound...]
                return rendered
            }

            let key = String(template[tokenStart..<closeRange.lowerBound])
            if isFullQuotedToken(rendered: rendered, template: template, closeUpperBound: closeRange.upperBound),
               !isJSONStringObjectKey(template: template, closeUpperBound: closeRange.upperBound)
            {
                rendered.removeLast()
                rendered += jsonReplacements[key] ?? "null"
                cursor = template.index(after: closeRange.upperBound)
            } else if isInsideJSONString(rendered) {
                rendered += textReplacements[key] ?? "null"
                cursor = closeRange.upperBound
            } else {
                rendered += jsonReplacements[key] ?? "null"
                cursor = closeRange.upperBound
            }
        }

        rendered += template[cursor...]
        return rendered
    }

    private static func isFullQuotedToken(
        rendered: String,
        template: String,
        closeUpperBound: String.Index
    ) -> Bool {
        endsWithUnescapedQuote(rendered)
            && closeUpperBound < template.endIndex
            && template[closeUpperBound] == "\""
    }

    private static func endsWithUnescapedQuote(_ text: String) -> Bool {
        guard text.last == "\"" else { return false }
        var backslashCount = 0
        var index = text.index(before: text.endIndex)
        while index > text.startIndex {
            index = text.index(before: index)
            guard text[index] == "\\" else { break }
            backslashCount += 1
        }
        return backslashCount.isMultiple(of: 2)
    }

    private static func isJSONStringObjectKey(template: String, closeUpperBound: String.Index) -> Bool {
        guard closeUpperBound < template.endIndex else { return false }
        var index = template.index(after: closeUpperBound)
        while index < template.endIndex {
            let character = template[index]
            if character == ":" { return true }
            if !character.isWhitespace { return false }
            index = template.index(after: index)
        }
        return false
    }

    private static func isInsideJSONString(_ rendered: String) -> Bool {
        var quoteCount = 0
        var backslashCount = 0

        for character in rendered {
            if character == "\\" {
                backslashCount += 1
                continue
            }

            if character == "\"", backslashCount.isMultiple(of: 2) {
                quoteCount += 1
            }
            backslashCount = 0
        }

        return !quoteCount.isMultiple(of: 2)
    }

    private static func messageReplacements(_ message: Any) -> [String: String] {
        var replacements: [String: String] = [:]
        collect(prefix: "message", value: message, into: &replacements)
        return replacements
    }

    private static func messageJSONLiteralReplacements(_ message: Any) -> [String: String] {
        var replacements: [String: String] = [:]
        collectJSONLiteral(prefix: "message", value: message, into: &replacements)
        return replacements
    }

    private static func collect(prefix: String, value: Any, into replacements: inout [String: String]) {
        replacements[prefix] =
            BridgeMessageValueFormatter.stringValue(
                value,
                escapesStringContent: true,
                nullString: "null"
            ) ?? ""

        if let dictionary = value as? [String: Any] {
            for (key, nested) in dictionary {
                collect(prefix: "\(prefix).\(key)", value: nested, into: &replacements)
            }
            return
        }

        if let array = value as? [Any] {
            for (index, nested) in array.enumerated() {
                collect(prefix: "\(prefix).\(index)", value: nested, into: &replacements)
            }
            return
        }
    }

    private static func collectJSONLiteral(prefix: String, value: Any, into replacements: inout [String: String]) {
        replacements[prefix] = BridgeMessageValueFormatter.jsonLiteral(value)

        if let dictionary = value as? [String: Any] {
            for (key, nested) in dictionary {
                collectJSONLiteral(prefix: "\(prefix).\(key)", value: nested, into: &replacements)
            }
            return
        }

        if let array = value as? [Any] {
            for (index, nested) in array.enumerated() {
                collectJSONLiteral(prefix: "\(prefix).\(index)", value: nested, into: &replacements)
            }
            return
        }
    }
}

enum BridgeResponseBodyValidator {
    nonisolated static func isValidTemplate(_ template: String) -> Bool {
        guard invalidTemplateToken(in: template) == nil else { return false }
        return isValidJSONFragment(replacingTemplateTokens(in: template, with: "null"))
    }

    nonisolated static func isValidRenderedBody(_ body: String) -> Bool {
        isValidJSONFragment(body)
    }

    nonisolated private static func replacingTemplateTokens(in template: String, with replacement: String) -> String {
        var rendered = ""
        var cursor = template.startIndex

        while let openRange = template[cursor...].range(of: "{{") {
            rendered += template[cursor..<openRange.lowerBound]
            let tokenStart = openRange.upperBound
            guard let closeRange = template[tokenStart...].range(of: "}}") else {
                rendered += template[openRange.lowerBound...]
                return rendered
            }

            rendered += replacement
            cursor = closeRange.upperBound
        }

        rendered += template[cursor...]
        return rendered
    }

    nonisolated private static func invalidTemplateToken(in template: String) -> String? {
        var cursor = template.startIndex

        while let openRange = template[cursor...].range(of: "{{") {
            let tokenStart = openRange.upperBound
            guard let closeRange = template[tokenStart...].range(of: "}}") else {
                return String(template[tokenStart...])
            }

            let token = String(template[tokenStart..<closeRange.lowerBound])
            guard token == "message" || isValidMessagePathToken(token) else {
                return token
            }
            cursor = closeRange.upperBound
        }

        return nil
    }

    nonisolated private static func isValidMessagePathToken(_ token: String) -> Bool {
        guard token.hasPrefix("message.") else { return false }
        let suffix = token.dropFirst("message.".count)
        return suffix
            .split(separator: ".", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty }
    }

    nonisolated private static func isValidJSONFragment(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }
}

// MARK: - Matching

enum BridgeRuleMatcher {
    static func matches(_ matcher: BridgeMatcher, message: Any) -> Bool {
        switch matcher {
        case .any:
            return true

        case .typeEquals(let expected):
            return value(at: "type", in: message) == expected

        case .jsonPathEquals(let path, let expected):
            return value(at: path, in: message) == expected
        }
    }

    static func value(at path: String, in message: Any) -> String? {
        let parts = path.split(separator: ".").map(String.init)
        guard !parts.isEmpty else { return nil }

        var current: Any? = message
        for part in parts {
            if let dictionary = current as? [String: Any] {
                current = dictionary[part]
            } else if let array = current as? [Any], let index = Int(part), array.indices.contains(index) {
                current = array[index]
            } else {
                return nil
            }
        }

        guard let current else { return nil }
        return BridgeMessageValueFormatter.stringValue(
            current,
            escapesStringContent: false,
            nullString: nil
        )
    }
}

// MARK: - JavaScript Utilities

private enum BridgeMessageValueFormatter {
    static func stringValue(
        _ value: Any,
        escapesStringContent: Bool,
        nullString: String?
    ) -> String? {
        if value is NSNull { return nullString }
        if let text = value as? String {
            return escapesStringContent ? JavaScriptLiteral.escapedStringContent(text) : text
        }
        if let number = value as? NSNumber {
            return isBooleanNumber(number) ? (number.boolValue ? "true" : "false") : number.stringValue
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8)
        {
            return escapesStringContent
                ? JavaScriptLiteral.escapedStringContent(text)
                : JavaScriptLiteral.escapedJavaScriptUnsafeCharacters(text)
        }
        return String(describing: value)
    }

    static func jsonLiteral(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if let text = value as? String { return JavaScriptLiteral.quoted(text) }
        if let number = value as? NSNumber {
            return isBooleanNumber(number) ? (number.boolValue ? "true" : "false") : number.stringValue
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8)
        {
            return JavaScriptLiteral.escapedJavaScriptUnsafeCharacters(text)
        }
        return JavaScriptLiteral.quoted(String(describing: value))
    }

    private static func isBooleanNumber(_ number: NSNumber) -> Bool {
        CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID()
    }
}

enum BridgeChannelNameValidator {
    static let reservedNames: Set<String> = [
        "consoleLog",
        "networkRequest",
        "resourceTiming",
        PreloadBridgeConstants.postMessageCaptureChannel,
    ]

    nonisolated static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let regex = #"^[A-Za-z_][A-Za-z0-9_]*$"#
        return name.range(of: regex, options: .regularExpression) != nil
    }
}

enum JavaScriptPath {
    nonisolated static func isValid(_ path: String) -> Bool {
        let parts = pathParts(path)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy(BridgeChannelNameValidator.isValid)
    }

    nonisolated static func arrayLiteral(_ path: String) -> String {
        let parts = pathParts(path)
        let quoted = parts.map(JavaScriptLiteral.quoted).joined(separator: ", ")
        return "[\(quoted)]"
    }

    nonisolated private static func pathParts(_ path: String) -> [String] {
        path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    }
}

enum JavaScriptLiteral {
    nonisolated static func literal(from value: String, valueKind: PreloadValueKind) -> String {
        switch valueKind {
        case .string:
            return quoted(value)

        case .json:
            return jsonLiteral(from: value) ?? quoted(value)
        }
    }

    nonisolated static func jsonLiteral(from value: String) -> String? {
        guard BridgeResponseBodyValidator.isValidRenderedBody(value) else {
            return nil
        }
        return value
    }

    nonisolated static func quoted(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed),
            let text = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        return
            escapedJavaScriptUnsafeCharacters(text)
    }

    nonisolated static func escapedStringContent(_ value: String) -> String {
        let quotedValue = quoted(value)
        guard quotedValue.count >= 2 else { return value }
        return String(quotedValue.dropFirst().dropLast())
    }

    nonisolated static func escapedJavaScriptUnsafeCharacters(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<", with: "\\u003C")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
