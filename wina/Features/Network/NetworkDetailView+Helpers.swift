//
//  NetworkDetailView+Helpers.swift
//  wina
//
//  Helper methods for NetworkDetailView.
//

import SwiftUI

// MARK: - Helper Methods

extension NetworkDetailView {
    func emptyState(message: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "eye.slash")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 40)
    }

    func copyToClipboard(_ text: String, label: String) {
        // Pretty-print if JSON, otherwise return original
        UIPasteboard.general.string = JSONParser.prettyPrintIfJSON(text)
        feedbackState.showCopied(label)
    }

    func formatHeadersForCopy(_ headers: [String: String]) -> String {
        headers
            .sorted(by: { $0.key.lowercased() < $1.key.lowercased() })
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }

    func shareRequest() {
        // Header first to prevent iOS from detecting URL as web content
        var text = """
        === Network Request ===
        Method: \(request.method)
        URL: \(request.url)
        Status: \(request.status.map { "\($0)" } ?? request.statusText ?? (request.isPending ? "Pending" : "—"))
        Duration: \(request.durationText)
        Type: \(request.requestType.rawValue.capitalized)
        """

        if let headers = request.requestHeaders, !headers.isEmpty {
            text += "\n\n--- Request Headers ---\n"
            text += formatHeadersForCopy(headers)
        }

        if let body = request.requestBody, !body.isEmpty {
            text += "\n\n--- Request Body ---\n"
            text += body
        }

        if let headers = request.responseHeaders, !headers.isEmpty {
            text += "\n\n--- Response Headers ---\n"
            text += formatHeadersForCopy(headers)
        }

        if let body = request.responseBody, !body.isEmpty {
            text += "\n\n--- Response Body ---\n"
            text += body
        }

        shareItem = NetworkShareContent(content: text)
    }

    func copyAsCurl() {
        UIPasteboard.general.string = request.curlCommand
        feedbackState.showCopied("cURL")
    }

    func shareResponseBodyAsFile(body: String, contentType: NetworkContentType) {
        // Determine file extension based on content type
        let fileExtension: String
        switch contentType {
        case .json:
            fileExtension = "json"
        case .html:
            fileExtension = "html"
        case .xml:
            fileExtension = "xml"
        case .formUrlEncoded, .text:
            fileExtension = "txt"
        }

        // Build filename: host_path_timestamp.ext
        let host = request.host
            .replacingOccurrences(of: "www.", with: "")
            .replacingOccurrences(of: ".", with: "_")
        let pathComponent = request.path.split(separator: "/").last.map(String.init) ?? "response"
        let sanitizedPath = pathComponent.replacingOccurrences(
            of: "[^a-zA-Z0-9_-]",
            with: "_",
            options: .regularExpression
        )
        let timestamp = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HHmmss"
            return formatter.string(from: Date())
        }()
        let fileName = "\(host)_\(sanitizedPath)_\(timestamp).\(fileExtension)"

        // Write to temp directory
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try body.write(to: fileURL, atomically: true, encoding: .utf8)
            shareFileURL = fileURL
        } catch {
            // Fallback to text share if file creation fails
            shareItem = NetworkShareContent(content: body)
        }
    }

    var methodColor: Color {
        switch request.method {
        case "GET": return .blue.opacity(0.8)
        case "POST": return .green.opacity(0.8)
        case "PUT": return .orange.opacity(0.8)
        case "DELETE": return .red.opacity(0.8)
        case "PATCH": return .purple.opacity(0.8)
        default: return .secondary
        }
    }

    func detectContentType(body: String, headers: [String: String]?) -> NetworkContentType {
        // Check Content-Type header first
        if let contentTypeHeader = headers?["Content-Type"] ?? headers?["content-type"] {
            if contentTypeHeader.contains("application/json") {
                return .json
            } else if contentTypeHeader.contains("text/html") {
                return .html
            } else if contentTypeHeader.contains("text/xml") || contentTypeHeader.contains("application/xml") {
                return .xml
            } else if contentTypeHeader.contains("text/plain") {
                return .text
            } else if contentTypeHeader.contains("application/x-www-form-urlencoded") {
                return .formUrlEncoded
            }
        }

        // Fallback: detect from body content
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            // Validate JSON
            if let data = body.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return .json
            }
        }
        if trimmed.hasPrefix("<!DOCTYPE") || trimmed.hasPrefix("<html") {
            return .html
        }
        if trimmed.hasPrefix("<?xml") || trimmed.hasPrefix("<") {
            return .xml
        }
        if trimmed.contains("=") && trimmed.contains("&") {
            return .formUrlEncoded
        }
        return .text
    }
}
