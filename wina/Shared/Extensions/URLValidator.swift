//
//  URLValidator.swift
//  wina
//
//  URL validation utilities for testing and validating URLs and IP addresses.
//

import Foundation

// MARK: - URL Validator

/// Utilities for validating URLs and IP addresses
enum URLValidator {

    // Cached NSDataDetector for URL validation (expensive to create)
    private static let linkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    /// Validates if a string is a valid URL
    /// - Parameter string: URL string to validate
    /// - Returns: true if valid URL, false otherwise
    static func isValidURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Add scheme if none present (http for local/private hosts, https otherwise)
        let urlString = normalizeURL(trimmed)

        guard let url = URL(string: urlString), let host = url.host else {
            return false
        }

        // Special handling for localhost
        if host == "localhost" {
            return true
        }

        // Special handling for IP addresses
        if isValidIPv4Address(host) {
            return true
        }

        // Host must contain at least one dot (for TLD)
        // This rejects "www.naver" but allows "www.naver.com"
        guard host.contains(".") else {
            return false
        }

        // URL validation using cached NSDataDetector (Apple's link detection engine)
        guard let detector = linkDetector else {
            return false
        }

        let range = NSRange(urlString.startIndex..., in: urlString)
        let matches = detector.matches(in: urlString, options: [], range: range)

        // Exactly one match must cover the entire string
        guard matches.count == 1,
              let match = matches.first,
              match.range.location == 0,
              match.range.length == urlString.utf16.count else {
            return false
        }

        return true
    }

    /// Validates if a string is a valid IPv4 address
    /// - Parameter string: IP address string to validate
    /// - Returns: true if valid IPv4 address, false otherwise
    static func isValidIPv4Address(_ string: String) -> Bool {
        let parts = string.split(separator: ".")
        guard parts.count == 4 else { return false }

        return parts.allSatisfy { part in
            // Must be a valid number
            guard let num = Int(part) else { return false }
            // Must be in range 0-255
            guard num >= 0 && num <= 255 else { return false }
            // Must not have leading zeros (except for "0" itself)
            // "01" is invalid, "0" is valid, "10" is valid
            if part.count > 1 && part.first == "0" { return false }
            return true
        }
    }

    /// Normalizes a URL string by adding a scheme if missing.
    ///
    /// Schemeless input gets `http://` when the host is local (localhost or a
    /// private/loopback/link-local IPv4 address) and `https://` otherwise.
    /// Local dev servers almost always speak plain HTTP, so forcing https on a
    /// bare IP/localhost would break the very local-testing flow this app exists for.
    /// - Parameter string: URL string to normalize
    /// - Returns: Normalized URL string with scheme
    static func normalizeURL(_ string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        let scheme = isLocalHost(trimmed) ? "http://" : "https://"
        return scheme + trimmed
    }

    /// Returns whether a schemeless URL string points at a local host
    /// (localhost or a private/loopback/link-local IPv4 address).
    /// Strips any path, query, fragment, and port before checking.
    static func isLocalHost(_ string: String) -> Bool {
        // Isolate the authority, then the host (drop path/query/fragment, then port)
        let authority = string.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        let host = authority.split(separator: ":", maxSplits: 1).first.map(String.init) ?? String(authority)

        if host.lowercased() == "localhost" { return true }
        return isPrivateOrLoopbackIPv4(host)
    }

    /// Returns whether the string is an IPv4 address in a private, loopback,
    /// link-local, or unspecified range (RFC 1918 / 5735).
    static func isPrivateOrLoopbackIPv4(_ string: String) -> Bool {
        guard isValidIPv4Address(string) else { return false }
        let octets = string.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }

        switch (octets[0], octets[1]) {
        case (0, _):                       return true   // 0.0.0.0/8 unspecified ("this host")
        case (10, _):                      return true   // 10.0.0.0/8 private
        case (127, _):                     return true   // 127.0.0.0/8 loopback
        case (169, 254):                   return true   // 169.254.0.0/16 link-local
        case (172, 16...31):               return true   // 172.16.0.0/12 private
        case (192, 168):                   return true   // 192.168.0.0/16 private
        default:                           return false
        }
    }

    /// Checks whether the URL string is supported by SFSafariViewController.
    /// SafariVC only accepts http/https URLs.
    static func isSupportedSafariURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized = URL(string: normalizeURL(trimmed)),
              let host = normalized.host, !host.isEmpty else { return false }

        switch URL(string: trimmed)?.scheme?.lowercased() {
        case nil, "http", "https":
            return true
        default:
            // Foundation also treats a bare hostname followed by a port as a scheme.
            return normalized.port != nil && isValidURL(trimmed)
        }
    }

    /// Extracts the host from a URL string
    /// - Parameter string: URL string
    /// - Returns: Host string or nil if invalid
    static func extractHost(_ string: String) -> String? {
        let normalized = normalizeURL(string)
        return URL(string: normalized)?.host
    }
}
