import Foundation
import UIKit

@Observable
final class AgentNavigation {
    private(set) var runID = UUID()
    private(set) var documentID: UUID?
    private(set) var phase = "idle"
    private(set) var url: URL?
    private(set) var status: Int?
    private(set) var error: String?
    private var identity: ObjectIdentifier?
    @ObservationIgnored weak var captureView: UIView?

    func start(_ object: AnyObject, url: URL?) {
        identity = ObjectIdentifier(object)
        runID = UUID()
        documentID = nil
        phase = "loading"
        self.url = url
        status = nil
        error = nil
    }

    func response(_ status: Int, url: URL?) {
        guard phase == "loading" else { return }
        self.status = status
        self.url = url
    }

    func commit(_ documentID: UUID, navigation: AnyObject?) {
        guard matches(navigation) else { return }
        self.documentID = documentID
    }

    func redirect(_ object: AnyObject, url: URL) {
        guard matches(object), phase == "loading" else { return }
        self.url = url
    }

    func finish(_ object: AnyObject?, url: URL?, error: Error? = nil) {
        guard matches(object) else { return }
        phase = error == nil ? "finished" : "failed"
        if let url { self.url = url }
        self.error = error.map { ($0 as NSError).domain + " " + String(($0 as NSError).code) }
    }

    func matches(_ object: AnyObject?) -> Bool {
        guard let object else { return false }
        return identity == ObjectIdentifier(object)
    }

    var evidence: [String: Any] {
        var result: [String: Any] = ["phase": phase]
        if let url { result["url"] = Self.redactedURL(url) }
        if let status { result["httpStatus"] = status }
        if let error { result["error"] = error }
        return result
    }

    static func redactedURL(_ url: URL) -> String {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.user = nil
        parts?.password = nil
        parts?.query = nil
        parts?.fragment = nil
        return parts?.string ?? ""
    }
}
