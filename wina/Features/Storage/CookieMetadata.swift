import Foundation

// MARK: - Cookie Metadata

struct CookieMetadata: Equatable {
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool
    let sameSitePolicy: String?

    var isSession: Bool { expiresDate == nil }

    init(from cookie: HTTPCookie) {
        self.domain = cookie.domain
        self.path = cookie.path
        self.expiresDate = cookie.expiresDate
        self.isSecure = cookie.isSecure
        self.isHTTPOnly = cookie.isHTTPOnly
        if let policy = cookie.sameSitePolicy {
            self.sameSitePolicy = policy.rawValue
        } else {
            self.sameSitePolicy = nil
        }
    }
}
