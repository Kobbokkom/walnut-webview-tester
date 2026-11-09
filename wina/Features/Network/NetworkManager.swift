//
//  NetworkManager.swift
//  wina
//
//  Network manager and body storage for request monitoring.
//

import Foundation

// MARK: - Log Clear Strategy

/// Strategy for clearing logs during navigation
enum LogClearStrategy: String, CaseIterable {
    case origin  // Clear when navigating to different origin (domain)
    case page    // Clear on every page navigation
    case keep    // Never auto-clear, manual only

    // 각 DevTools 별로 clear 전략을 독립 저장하기 위한 UserDefaults 키
    static let consoleDefaultsKey = "consoleLogClearStrategy"
    static let networkDefaultsKey = "networkLogClearStrategy"
    // 과거 단일 전략 키(1회 마이그레이션 전용)
    static let legacyDefaultsKey = "logClearStrategy"
    // 1회 마이그레이션 완료 플래그
    static let migrationFlagKey = "didMigrateLogClearStrategyKeys"

    var displayName: String {
        switch self {
        case .origin: return "Same Origin"
        case .page: return "Each Page"
        case .keep: return "Keep All"
        }
    }

    var description: String {
        switch self {
        case .origin: return "Clear when leaving current domain"
        case .page: return "Clear on every navigation"
        case .keep: return "Keep until manually cleared"
        }
    }
}

// MARK: - Log Clear Strategy Resolver

struct LogClearStrategyResolver {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // 마이그레이션을 먼저 보장한 뒤 콘솔/네트워크 전략을 각각 해석합니다.
    func resolveStrategies() -> (console: LogClearStrategy, network: LogClearStrategy) {
        migrateLegacyStrategyIfNeeded()
        return (
            resolvedStrategy(forKey: LogClearStrategy.consoleDefaultsKey),
            resolvedStrategy(forKey: LogClearStrategy.networkDefaultsKey)
        )
    }

    // 저장된 rawValue가 유효하지 않으면 안전하게 keep으로 폴백합니다.
    func resolvedStrategy(forKey key: String) -> LogClearStrategy {
        if let strategyRaw = defaults.string(forKey: key),
           let strategy = LogClearStrategy(rawValue: strategyRaw) {
            return strategy
        }
        return .keep
    }

    // 레거시 단일 키를 분리 키로 1회만 옮기고 재주입을 막습니다.
    func migrateLegacyStrategyIfNeeded() {
        guard !defaults.bool(forKey: LogClearStrategy.migrationFlagKey) else { return }

        let hasConsole = defaults.string(forKey: LogClearStrategy.consoleDefaultsKey) != nil
        let hasNetwork = defaults.string(forKey: LogClearStrategy.networkDefaultsKey) != nil

        if let legacyRaw = defaults.string(forKey: LogClearStrategy.legacyDefaultsKey),
           let legacyStrategy = LogClearStrategy(rawValue: legacyRaw) {
            if !hasConsole {
                defaults.set(legacyStrategy.rawValue, forKey: LogClearStrategy.consoleDefaultsKey)
            }
            if !hasNetwork {
                defaults.set(legacyStrategy.rawValue, forKey: LogClearStrategy.networkDefaultsKey)
            }
        }

        defaults.removeObject(forKey: LogClearStrategy.legacyDefaultsKey)
        defaults.set(true, forKey: LogClearStrategy.migrationFlagKey)
    }

    // URL 전환 시 clear 여부를 정책별로 일관되게 계산합니다.
    static func shouldClear(
        strategy: LogClearStrategy,
        currentURL: URL?,
        newURL: URL?
    ) -> Bool {
        switch strategy {
        case .keep:
            return false
        case .page:
            return true
        case .origin:
            guard let currentOrigin = normalizedOrigin(from: currentURL),
                  let nextOrigin = normalizedOrigin(from: newURL) else { return false }
            return currentOrigin != nextOrigin
        }
    }

    // 스킴/호스트/정규화된 포트로 Same Origin 비교 기준 문자열을 생성합니다.
    static func normalizedOrigin(from url: URL?) -> String? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else { return nil }

        let normalizedPort: Int? = if let explicitPort = url.port {
            explicitPort
        } else {
            switch scheme {
            case "http":
                80
            case "https":
                443
            default:
                nil
            }
        }

        if let normalizedPort {
            return "\(scheme)://\(host):\(normalizedPort)"
        }

        return "\(scheme)://\(host)"
    }
}

// MARK: - Network Body Storage (Disk-based)

final class NetworkBodyStorage {
    static let shared = NetworkBodyStorage()

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.wina.networkbodystorage", qos: .utility)
    // 같은 큐 내부 재진입 여부를 판별해 sync 데드락을 방지합니다.
    private let queueKey = DispatchSpecificKey<Void>()

    private lazy var cacheDirectory: URL = {
        // Use caches directory, fallback to temp directory if unavailable
        let baseDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = baseDir.appendingPathComponent("NetworkBodies", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    enum BodyType: String {
        case request
        case response
    }

    private init() {
        // 저장소 큐 식별자를 세팅해 load 동기화 시 재진입을 안전하게 처리합니다.
        queue.setSpecific(key: queueKey, value: ())
    }

    // MARK: - Public API

    func save(id: UUID, type: BodyType, body: String) {
        queue.async { [weak self] in
            guard let self, !body.isEmpty else { return }
            let url = self.fileURL(for: id, type: type)
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func load(id: UUID, type: BodyType) -> String? {
        // save/delete/clearAll과 동일한 직렬 큐 순서를 보장해 파일 읽기 경합을 없앱니다.
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return loadDirect(id: id, type: type)
        }
        return queue.sync { loadDirect(id: id, type: type) }
    }

    func loadAsync(id: UUID, type: BodyType, completion: @escaping (String?) -> Void) {
        queue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let result = self.load(id: id, type: type)
            DispatchQueue.main.async { completion(result) }
        }
    }

    func delete(id: UUID) {
        queue.async { [weak self] in
            guard let self else { return }
            try? self.fileManager.removeItem(at: self.fileURL(for: id, type: .request))
            try? self.fileManager.removeItem(at: self.fileURL(for: id, type: .response))
        }
    }

    func delete(ids: [UUID]) {
        queue.async { [weak self] in
            guard let self else { return }
            for id in ids {
                try? self.fileManager.removeItem(at: self.fileURL(for: id, type: .request))
                try? self.fileManager.removeItem(at: self.fileURL(for: id, type: .response))
            }
        }
    }

    func clearAll() {
        queue.async { [weak self] in
            guard let self else { return }
            try? self.fileManager.removeItem(at: self.cacheDirectory)
            try? self.fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        }
    }

    // Clear cache on app launch (previous session data)
    func clearOnLaunchIfNeeded() {
        // Only clear if not preserving logs
        let preserveLog = UserDefaults.standard.bool(forKey: "networkPreserveLog")
        if !preserveLog {
            clearAll()
        }
    }

    // MARK: - Private

    private func fileURL(for id: UUID, type: BodyType) -> URL {
        cacheDirectory.appendingPathComponent("\(id.uuidString)_\(type.rawValue).txt")
    }

    private func loadDirect(id: UUID, type: BodyType) -> String? {
        let url = fileURL(for: id, type: type)
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

// MARK: - Network Manager

@Observable
class NetworkManager {
    var requests: [NetworkRequest] = []
    var isCapturing: Bool = true
    var agentDocumentID: UUID?
    var pageURL: URL?  // Current page URL for mixed content detection

    // Limits for memory management (only affects request count, not body size)
    private let maxRequestCount = 500
    private let bodyStorage = NetworkBodyStorage.shared

    // Read preserveLog from UserDefaults
    var preserveLog: Bool {
        UserDefaults.standard.bool(forKey: "networkPreserveLog")
    }

    /// Whether the current page is using HTTPS
    var pageIsSecure: Bool {
        pageURL?.scheme?.lowercased() == "https"
    }

    func addRequest(
        id: String,
        method: String,
        url: String,
        requestType: String,
        headers: [String: String]?,
        body: String?
    ) {
        guard isCapturing else { return }

        let type = NetworkRequest.RequestType(rawValue: requestType) ?? .other
        let uuid = UUID(uuidString: id) ?? UUID()

        // Save full body to disk
        if let body, !body.isEmpty {
            bodyStorage.save(id: uuid, type: .request, body: body)
        }

        // Store only preview in memory
        let preview = body.map { String($0.prefix(NetworkRequest.previewLength)) }

        let request = NetworkRequest(
            id: uuid,
            method: method.uppercased(),
            url: url,
            requestHeaders: headers,
            requestBodyPreview: preview,
            startTime: Date(),
            pageIsSecure: pageIsSecure,
            requestType: type,
            agentDocumentID: type == .document ? nil : agentDocumentID
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Enforce max request count - delete disk files for removed requests
            if self.requests.count >= self.maxRequestCount {
                let removedRequest = self.requests.removeFirst()
                self.bodyStorage.delete(id: removedRequest.id)
            }
            self.requests.append(request)
        }
    }

    func updateRequest(
        id: String,
        status: Int?,
        statusText: String?,
        responseHeaders: [String: String]?,
        responseBody: String?,
        error: String?,
        requestBody: String? = nil
    ) {
        guard let uuid = UUID(uuidString: id) else { return }

        let responsePreview = responseBody.map { String($0.prefix(NetworkRequest.previewLength)) }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let index = self.requests.firstIndex(where: { $0.id == uuid }) else { return }

            if let responseBody, !responseBody.isEmpty {
                self.bodyStorage.save(id: uuid, type: .response, body: responseBody)
            }

            // Replace entire struct to ensure @Observable detects the change
            var updated = self.requests[index]

            // placeholder 본문이 실제 backfill 본문을 덮어쓰지 않도록 품질을 비교해 갱신합니다.
            if let requestBody,
               self.shouldReplaceRequestBody(existing: updated.requestBodyPreview, incoming: requestBody) {
                self.bodyStorage.save(id: uuid, type: .request, body: requestBody)
                updated.requestBodyPreview = String(requestBody.prefix(NetworkRequest.previewLength))
            }
            updated.status = status
            updated.statusText = statusText
            updated.responseHeaders = responseHeaders
            updated.responseBodyPreview = responsePreview
            updated.error = error
            updated.endTime = Date()
            self.requests[index] = updated
        }
    }

    func completeDocumentRequest(id: String, error: String?) {
        guard let uuid = UUID(uuidString: id) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let index = requests.firstIndex(where: { $0.id == uuid }) else { return }
            var request = requests[index]
            if let error { request.error = error }
            request.endTime = request.endTime ?? Date()
            requests[index] = request
        }
    }

    func updateRequestBody(
        id: String,
        requestBody: String?
    ) {
        guard let uuid = UUID(uuidString: id),
              let requestBody,
              !requestBody.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let index = self.requests.firstIndex(where: { $0.id == uuid }) else { return }

            // requestBody 전용 backfill은 완료 시각을 건드리지 않고 본문만 갱신합니다.
            // placeholder보다 의미 있는 본문이 우선되도록 갱신 정책을 동일하게 적용합니다.
            var updated = self.requests[index]
            guard self.shouldReplaceRequestBody(existing: updated.requestBodyPreview, incoming: requestBody) else {
                return
            }
            self.bodyStorage.save(id: uuid, type: .request, body: requestBody)
            updated.requestBodyPreview = String(requestBody.prefix(NetworkRequest.previewLength))
            self.requests[index] = updated
        }
    }

    func clear() {
        // Delete all disk files
        let ids = requests.map(\.id)
        bodyStorage.delete(ids: ids)
        requests.removeAll()
    }

    func assignAgentDocument(_ document: UUID, requestID: String?) {
        guard let requestID, let id = UUID(uuidString: requestID) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let index = requests.firstIndex(where: { $0.id == id }) else { return }
            var request = requests[index]
            request.agentDocumentID = document
            requests[index] = request
        }
    }

    func clearForNavigation(preserving requestID: String?) {
        let preservedID = requestID.flatMap(UUID.init(uuidString:))
        // Queue behind request insertion/response updates from the committing navigation.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.bodyStorage.delete(ids: self.requests.filter { $0.id != preservedID }.map(\.id))
            self.requests.removeAll { $0.id != preservedID }
        }
    }

    func clearIfNotPreserved() {
        guard !preserveLog else { return }
        clear()
    }

    var pendingCount: Int { requests.filter(\.isPending).count }
    var errorCount: Int { requests.filter { $0.error != nil || ($0.status ?? 0) >= 400 }.count }
    var mixedContentCount: Int { requests.filter(\.isMixedContent).count }

    // 본문 표기의 품질 점수를 비교해 실제 데이터가 placeholder보다 우선 유지되도록 합니다.
    private func shouldReplaceRequestBody(existing: String?, incoming: String) -> Bool {
        guard !incoming.isEmpty else { return false }

        guard let existing else { return true }
        guard !existing.isEmpty else { return true }

        let incomingScore = requestBodyQualityScore(incoming)
        let existingScore = requestBodyQualityScore(existing)

        if incomingScore < existingScore {
            return false
        }
        return true
    }

    // placeholder(ReadableStream/Blob/File/TypedArray)보다 실제 텍스트/JSON 본문을 더 높은 점수로 간주합니다.
    private func requestBodyQualityScore(_ body: String) -> Int {
        isRequestBodyPlaceholder(body) ? 1 : 2
    }

    // 자바스크립트 레벨에서 생성되는 바디 placeholder 표기를 판별합니다.
    private func isRequestBodyPlaceholder(_ body: String) -> Bool {
        if body == "ReadableStream" || body == "[Body already consumed]" {
            return true
        }
        if body.hasPrefix("[File:") || body.hasPrefix("[Blob:") || body.hasPrefix("[ArrayBuffer ") {
            return true
        }

        // TypedArray placeholder 예: [Uint8Array 128 bytes]
        if body.hasPrefix("["),
           body.hasSuffix(" bytes]"),
           body.contains("Array") {
            return true
        }
        return false
    }
}
