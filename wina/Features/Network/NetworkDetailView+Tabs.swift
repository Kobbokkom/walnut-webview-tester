//
//  NetworkDetailView+Tabs.swift
//  wina
//
//  Tab content extensions for NetworkDetailView.
//

import SwiftUI

// MARK: - Tab Content

extension NetworkDetailView {
    // MARK: - Overview Tab

    @ViewBuilder
    var overviewContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Timing visualization
            NetworkTimingView(request: request)

            // Stack trace - shows where the request originated
            StackTraceView(stackFrames: request.stackFrames)
        }
        .padding()
    }

    // MARK: - Headers Tab

    @ViewBuilder
    var headersContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // General info section
            DetailSection(title: "General", rawText: generalRawText, onCopy: copyToClipboard) {
                DetailTableRow(key: "Request URL", value: request.url, onCopy: copyToClipboard)
                DetailTableRow(key: "Request Method", value: request.method, onCopy: copyToClipboard)
                if let status = request.status, let statusText = request.statusText {
                    DetailTableRow(key: "Status Code", value: "\(status) \(statusText)", onCopy: copyToClipboard)
                } else if let status = request.status {
                    DetailTableRow(key: "Status Code", value: "\(status)", onCopy: copyToClipboard)
                } else if let statusText = request.statusText {
                    DetailTableRow(key: "Status", value: statusText, onCopy: copyToClipboard)
                }
                DetailTableRow(
                    key: "Type",
                    value: request.requestType.rawValue.capitalized,
                    onCopy: copyToClipboard,
                    showBorder: false
                )
            }

            // Response headers
            if let headers = request.responseHeaders, !headers.isEmpty {
                let sortedHeaders = headers.sorted(by: { $0.key.lowercased() < $1.key.lowercased() })
                DetailSection(
                    title: "Response Headers",
                    rawText: formatHeadersForCopy(headers),
                    onCopy: copyToClipboard
                ) {
                    ForEach(Array(sortedHeaders.enumerated()), id: \.element.key) { index, pair in
                        DetailTableRow(
                            key: pair.key,
                            value: pair.value,
                            onCopy: copyToClipboard,
                            showBorder: index < sortedHeaders.count - 1
                        )
                    }
                }
            }

            // Request headers
            if let headers = request.requestHeaders, !headers.isEmpty {
                let sortedHeaders = headers.sorted(by: { $0.key.lowercased() < $1.key.lowercased() })
                DetailSection(
                    title: "Request Headers",
                    rawText: formatHeadersForCopy(headers),
                    onCopy: copyToClipboard
                ) {
                    ForEach(Array(sortedHeaders.enumerated()), id: \.element.key) { index, pair in
                        DetailTableRow(
                            key: pair.key,
                            value: pair.value,
                            onCopy: copyToClipboard,
                            showBorder: index < sortedHeaders.count - 1
                        )
                    }
                }
            }

            if request.requestHeaders == nil && request.responseHeaders == nil {
                emptyState(message: "No headers available")
            }
        }
        .padding()
    }

    var generalRawText: String {
        var lines: [String] = []
        lines.append("Request URL: \(request.url)")
        lines.append("Request Method: \(request.method)")
        if let status = request.status, let statusText = request.statusText {
            lines.append("Status Code: \(status) \(statusText)")
        } else if let status = request.status {
            lines.append("Status Code: \(status)")
        } else if let statusText = request.statusText {
            lines.append("Status: \(statusText)")
        }
        lines.append("Type: \(request.requestType.rawValue.capitalized)")
        return lines.joined(separator: "\n")
    }

    // MARK: - Request Tab

    @ViewBuilder
    var requestContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // URL breakdown
            if let urlComponents = URLComponents(string: request.url) {
                DetailSection(title: "URL", rawText: urlRawText(urlComponents), onCopy: copyToClipboard) {
                    if let scheme = urlComponents.scheme {
                        DetailTableRow(key: "Scheme", value: scheme, onCopy: copyToClipboard)
                    }
                    if let host = urlComponents.host {
                        DetailTableRow(key: "Host", value: host, onCopy: copyToClipboard)
                    }
                    if let port = urlComponents.port {
                        DetailTableRow(key: "Port", value: "\(port)", onCopy: copyToClipboard)
                    }
                    DetailTableRow(
                        key: "Path",
                        value: urlComponents.path.isEmpty ? "/" : urlComponents.path,
                        onCopy: copyToClipboard,
                        showBorder: false
                    )
                }

                // Query parameters
                if let queryItems = urlComponents.queryItems, !queryItems.isEmpty {
                    DetailSection(
                        title: "Query Parameters",
                        rawText: queryParametersRawText(queryItems),
                        onCopy: copyToClipboard
                    ) {
                        ForEach(Array(queryItems.enumerated()), id: \.element.name) { index, item in
                            DetailTableRow(
                                key: item.name,
                                value: item.value ?? "(empty)",
                                onCopy: copyToClipboard,
                                showBorder: index < queryItems.count - 1
                            )
                        }
                    }
                }
            }

            // Request body
            if let body = request.requestBody, !body.isEmpty {
                let networkContentType = detectContentType(body: body, headers: request.requestHeaders)
                let responseFormatterType = networkContentType.toResponseContentType()
                let bodySize = body.data(using: .utf8)?.count ?? 0
                let discrepancyMessage = contentTypeDiscrepancyMessage(body: body, headers: request.requestHeaders)
                DetailSection(title: "Request Body", rawText: body, onCopy: copyToClipboard) {
                    BodyHeaderView(
                        contentType: networkContentType,
                        size: bodySize,
                        discrepancyMessage: discrepancyMessage
                    )
                    ResponseFormatterView(
                        responseBody: body,
                        contentType: responseFormatterType
                    )
                    .frame(minHeight: 200)
                }
            } else {
                emptyState(message: "No request body")
            }
        }
        .padding()
    }

    func urlRawText(_ components: URLComponents) -> String {
        var lines: [String] = []
        if let scheme = components.scheme {
            lines.append("Scheme: \(scheme)")
        }
        if let host = components.host {
            lines.append("Host: \(host)")
        }
        if let port = components.port {
            lines.append("Port: \(port)")
        }
        lines.append("Path: \(components.path.isEmpty ? "/" : components.path)")
        return lines.joined(separator: "\n")
    }

    func queryParametersRawText(_ items: [URLQueryItem]) -> String {
        items.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    }

    private func contentTypeDiscrepancyMessage(body: String, headers: [String: String]?) -> String? {
        guard let contentTypeHeader = headers?["Content-Type"] ?? headers?["content-type"] else {
            return nil
        }
        guard let headerType = normalizedContentType(from: contentTypeHeader) else {
            return nil
        }
        guard let bodyType = inferredBodyType(from: body) else {
            return nil
        }
        guard headerType != bodyType else { return nil }
        return "Content-Type is \(headerType.label), but the body looks like \(bodyType.label)."
    }

    private enum BodyContentHint: Equatable {
        case json
        case html
        case xml
        case text
        case formUrlEncoded

        var label: String {
            switch self {
            case .json:
                return "JSON"
            case .html:
                return "HTML"
            case .xml:
                return "XML"
            case .text:
                return "Text"
            case .formUrlEncoded:
                return "form-urlencoded"
            }
        }
    }

    private func normalizedContentType(from header: String) -> BodyContentHint? {
        let lowercased = header.lowercased()
        if lowercased.contains("application/json") {
            return .json
        }
        if lowercased.contains("text/html") {
            return .html
        }
        if lowercased.contains("application/xml") || lowercased.contains("text/xml") {
            return .xml
        }
        if lowercased.contains("text/plain") {
            return .text
        }
        if lowercased.contains("application/x-www-form-urlencoded") {
            return .formUrlEncoded
        }
        return nil
    }

    private func inferredBodyType(from body: String) -> BodyContentHint? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return .json
        }

        if trimmed.hasPrefix("<") {
            if trimmed.range(of: "<html", options: .caseInsensitive) != nil {
                return .html
            }
            if trimmed.hasPrefix("<?xml") {
                return .xml
            }
            if trimmed.range(of: "</", options: .caseInsensitive) != nil {
                return .xml
            }
        }

        if looksLikeFormUrlEncoded(trimmed) {
            return .formUrlEncoded
        }

        return .text
    }

    private func looksLikeFormUrlEncoded(_ text: String) -> Bool {
        // Quick heuristic: key=value pairs separated by '&', no leading JSON/XML markers.
        let pairs = text.split(separator: "&", omittingEmptySubsequences: true)
        guard !pairs.isEmpty else { return false }
        let sampleCount = min(pairs.count, 6)
        let validPairs = pairs.prefix(sampleCount).filter { pair in
            pair.contains("=") && !pair.hasPrefix("=")
        }
        return validPairs.count == sampleCount
    }

    // MARK: - Response Tab

    @ViewBuilder
    var responseContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let body = request.responseBody, !body.isEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    let networkContentType = detectContentType(body: body, headers: request.responseHeaders)
                    let responseFormatterType = networkContentType.toResponseContentType()
                    let bodySize = body.data(using: .utf8)?.count ?? 0
                    let discrepancyMessage = contentTypeDiscrepancyMessage(body: body, headers: request.responseHeaders)

                    DetailSection(
                        title: "Response Body",
                        rawText: body,
                        onCopy: copyToClipboard,
                        onShare: {
                            shareResponseBodyAsFile(body: body, contentType: networkContentType)
                        },
                        content: {
                            BodyHeaderView(
                                contentType: networkContentType,
                                size: bodySize,
                                discrepancyMessage: discrepancyMessage
                            )
                            ResponseFormatterView(
                                responseBody: body,
                                contentType: responseFormatterType
                            )
                            .frame(minHeight: 200)
                        }
                    )
                }
                .padding()
            } else if request.requestType == .fetch || request.requestType == .xhr {
                // fetch/XHR requests can capture response but this one has empty body
                emptyState(message: "No response body")
                    .padding()
            } else {
                // Document/other types: browser-initiated, cannot intercept
                SecurityRestrictionBanner(type: .staticResourceBody)
                    .padding()
            }
        }
    }
}
