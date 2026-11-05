//
//  PerformanceModels.swift
//  wina
//
//  Performance data models and manager.
//

import SwiftUI

// MARK: - Performance Score Rating

enum PerformanceRating: String {
    case good = "Good"
    case needsImprovement = "Needs Improvement"
    case poor = "Poor"
    case unknown = "N/A"

    var color: Color {
        switch self {
        case .good: .green
        case .needsImprovement: .orange
        case .poor: .red
        case .unknown: .secondary
        }
    }

    var icon: String {
        switch self {
        case .good: "checkmark.circle.fill"
        case .needsImprovement: "exclamationmark.circle.fill"
        case .poor: "xmark.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }
}

// MARK: - Metric Thresholds (Google Web Vitals 2025)

struct MetricThresholds {
    // Core Web Vitals (Official 2025)
    // LCP: Largest Contentful Paint
    static let lcpGood: Double = 2500  // ≤ 2.5s
    static let lcpPoor: Double = 4000  // > 4s

    // Note: INP removed - Safari/WKWebView doesn't support Event Timing API (until 2026)

    // CLS: Cumulative Layout Shift (unitless)
    static let clsGood: Double = 0.1  // ≤ 0.1
    static let clsPoor: Double = 0.25  // > 0.25

    // Other Web Vitals
    // FCP: First Contentful Paint
    static let fcpGood: Double = 1800  // ≤ 1.8s
    static let fcpPoor: Double = 3000  // > 3s

    // TTFB: Time to First Byte (Google recommends ≤200ms)
    static let ttfbGood: Double = 200  // ≤ 200ms
    static let ttfbPoor: Double = 600  // > 600ms

    // TBT: Total Blocking Time
    static let tbtGood: Double = 200  // ≤ 200ms
    static let tbtPoor: Double = 600  // > 600ms

    // DOM Content Loaded
    static let dclGood: Double = 1500  // ≤ 1.5s
    static let dclPoor: Double = 3000  // > 3s

    // DNS Lookup
    static let dnsGood: Double = 50  // ≤ 50ms
    static let dnsPoor: Double = 200  // > 200ms

    // TCP/TLS Connection
    static let connectGood: Double = 100  // ≤ 100ms
    static let connectPoor: Double = 300  // > 300ms

    static func rate(_ value: Double, good: Double, poor: Double, isLowerBetter: Bool = true) -> PerformanceRating {
        if value < 0 { return .unknown }
        if isLowerBetter {
            if value <= good { return .good }
            if value < poor { return .needsImprovement }
            return .poor
        } else {
            if value >= good { return .good }
            if value > poor { return .needsImprovement }
            return .poor
        }
    }

    static func score(_ value: Double, good: Double, poor: Double, isLowerBetter: Bool = true) -> Int {
        if value < 0 { return 0 }
        if isLowerBetter {
            if value <= good { return 100 }
            if value >= poor { return 0 }
            let ratio = (poor - value) / (poor - good)
            return Int(ratio * 100)
        } else {
            if value >= good { return 100 }
            if value <= poor { return 0 }
            let ratio = (value - poor) / (good - poor)
            return Int(ratio * 100)
        }
    }
}

// MARK: - Navigation Timing

struct NavigationTiming: Codable, Equatable {
    let startTime: Double
    let redirectTime: Double
    let dnsTime: Double
    let tcpTime: Double
    let tlsTime: Double
    let requestTime: Double
    let responseTime: Double
    let domProcessingTime: Double
    let domContentLoadedTime: Double
    let loadEventTime: Double

    var timeToFirstByte: Double?

    // TTFB = time from navigation start to first byte of response
    var ttfb: Double {
        timeToFirstByte ?? -1
    }

    // Connection time = TCP + TLS
    var connectionTime: Double {
        tcpTime + tlsTime
    }
}

// MARK: - Resource Timing

struct ResourceTiming: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let initiatorType: String
    let startTime: Double
    let duration: Double
    let transferSize: Int
    let encodedBodySize: Int
    let decodedBodySize: Int

    var resourceType: ResourceType {
        ResourceType.from(initiatorType: initiatorType, name: name)
    }

    var shortName: String {
        if let url = URL(string: name) {
            return url.lastPathComponent.isEmpty ? url.host() ?? name : url.lastPathComponent
        }
        return String(name.suffix(30))
    }

    /// Best available size (transferSize > encodedBodySize > decodedBodySize > 0)
    /// transferSize can be 0 for cached resources or cross-origin without CORS
    var displaySize: Int {
        if transferSize > 0 { return transferSize }
        if encodedBodySize > 0 { return encodedBodySize }
        if decodedBodySize > 0 { return decodedBodySize }
        return 0
    }
}

// MARK: - Resource Type

enum ResourceType: String, CaseIterable {
    case document = "Document"
    case script = "Script"
    case stylesheet = "Stylesheet"
    case image = "Image"
    case font = "Font"
    case fetch = "Fetch/XHR"
    case other = "Other"

    var icon: String {
        switch self {
        case .document: "doc.fill"
        case .script: "curlybraces"
        case .stylesheet: "paintbrush.fill"
        case .image: "photo.fill"
        case .font: "textformat"
        case .fetch: "arrow.down.circle.fill"
        case .other: "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .document: .blue
        case .script: .yellow
        case .stylesheet: .purple
        case .image: .green
        case .font: .orange
        case .fetch: .cyan
        case .other: .gray
        }
    }

    static func from(initiatorType: String, name: String) -> ResourceType {
        switch initiatorType.lowercased() {
        case "navigation": return .document
        case "script": return .script
        case "link", "css": return .stylesheet
        case "img", "image": return .image
        case "font": return .font
        case "fetch", "xmlhttprequest": return .fetch
        default:
            // Fallback to extension-based detection
            let ext = (name as NSString).pathExtension.lowercased()
            switch ext {
            case "js", "mjs": return .script
            case "css": return .stylesheet
            case "png", "jpg", "jpeg", "gif", "webp", "svg", "ico": return .image
            case "woff", "woff2", "ttf", "otf", "eot": return .font
            default: return .other
            }
        }
    }
}

// MARK: - Paint Timing

struct PaintTiming: Codable, Equatable {
    let name: String
    let startTime: Double
}

// MARK: - Performance Data

struct PerformanceData: Equatable {
    var navigation: NavigationTiming?
    var resources: [ResourceTiming] = []
    var paints: [PaintTiming] = []
    var timestamp = Date()

    // Core Web Vitals (2025)
    var cls: Double = -1  // Cumulative Layout Shift (unitless), -1 = not measured
    var tbt: Double = -1  // Total Blocking Time (ms), -1 = not measured

    var totalResources: Int { resources.count }
    var totalTransferSize: Int {
        resources.reduce(0) { $0 + $1.displaySize }
    }

    var firstContentfulPaint: Double? {
        paints.first { $0.name == "first-contentful-paint" }?.startTime
    }

    var firstPaint: Double? {
        paints.first { $0.name == "first-paint" }?.startTime
    }

    var largestContentfulPaint: Double?

    // MARK: - Core Web Vitals Scores

    var lcpScore: Int {
        guard let lcp = largestContentfulPaint else { return 0 }
        return MetricThresholds.score(lcp, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor)
    }

    var lcpRating: PerformanceRating {
        guard let lcp = largestContentfulPaint else { return .unknown }
        return MetricThresholds.rate(lcp, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor)
    }

    var clsScore: Int {
        guard cls >= 0 else { return 0 }
        return MetricThresholds.score(cls, good: MetricThresholds.clsGood, poor: MetricThresholds.clsPoor)
    }

    var clsRating: PerformanceRating {
        guard cls >= 0 else { return .unknown }
        return MetricThresholds.rate(cls, good: MetricThresholds.clsGood, poor: MetricThresholds.clsPoor)
    }

    // MARK: - Overall Score (Core Web Vitals weighted)

    var totalScore: Int {
        var scores: [Int] = []
        var weights: [Int] = []

        // Core Web Vitals (higher weight) - LCP and CLS only
        // Note: INP not supported in Safari/WKWebView until 2026
        if largestContentfulPaint != nil {
            scores.append(lcpScore)
            weights.append(3)  // LCP weight: 3x
        }
        if cls >= 0 {
            scores.append(clsScore)
            weights.append(2)  // CLS weight: 2x
        }

        // Other vitals (lower weight)
        if let fcp = firstContentfulPaint {
            scores.append(MetricThresholds.score(fcp, good: MetricThresholds.fcpGood, poor: MetricThresholds.fcpPoor))
            weights.append(1)
        }
        if let nav = navigation {
            scores.append(MetricThresholds.score(nav.ttfb, good: MetricThresholds.ttfbGood, poor: MetricThresholds.ttfbPoor))
            weights.append(1)
        }

        guard !scores.isEmpty else { return 0 }

        let weightedSum = zip(scores, weights).reduce(0) { $0 + $1.0 * $1.1 }
        let totalWeight = weights.reduce(0, +)
        return weightedSum / totalWeight
    }

    var scoreRating: PerformanceRating {
        let score = totalScore
        if score == 0 { return .unknown }
        if score >= 90 { return .good }
        if score >= 50 { return .needsImprovement }
        return .poor
    }

    // Core Web Vitals pass/fail (LCP + CLS only)
    // Note: INP not supported in Safari/WKWebView until 2026
    var coreWebVitalsPass: Bool {
        lcpRating == .good && clsRating == .good
    }
}

// MARK: - Performance Manager

@Observable
class PerformanceManager {
    var data = PerformanceData()
    var isLoading: Bool = false
    var lastError: String?
    private(set) var isReloading = false
    @ObservationIgnored private var collectionID = UUID()

    // JavaScript to inject PerformanceObservers at page load (for LCP, CLS)
    // Note: INP removed - Safari/WKWebView doesn't support Event Timing API (until 2026)
    static let observerInjectionScript = """
    (function() {
        if (window.__webVitals_initialized) return;
        window.__webVitals_initialized = true;

        // LCP tracking
        window.__webVitals_lcp = -1;
        try {
            new PerformanceObserver((list) => {
                const entries = list.getEntries();
                if (entries.length > 0) {
                    window.__webVitals_lcp = entries[entries.length - 1].startTime;
                }
            }).observe({ type: 'largest-contentful-paint', buffered: true });
        } catch (e) {}

        // CLS tracking
        window.__webVitals_cls = -1;
        if (typeof PerformanceObserver !== 'undefined' && PerformanceObserver.supportedEntryTypes?.includes('layout-shift')) {
            let sessionStart = null;
            let lastShift = 0;
            let sessionScore = 0;
            try {
                window.__webVitals_cls = 0;
                new PerformanceObserver((list) => {
                    for (const entry of list.getEntries()) {
                        if (entry.hadRecentInput) continue;
                        if (sessionStart === null || entry.startTime - lastShift >= 1000 ||
                            entry.startTime - sessionStart >= 5000) {
                            sessionStart = entry.startTime;
                            sessionScore = 0;
                        }
                        lastShift = entry.startTime;
                        sessionScore += entry.value;
                        window.__webVitals_cls = Math.max(window.__webVitals_cls, sessionScore);
                    }
                }).observe({ type: 'layout-shift', buffered: true });
            } catch (e) {
                window.__webVitals_cls = -1;
            }
        }
    })();
    """

    // JavaScript to collect Performance API data (Web Vitals 2025)
    static let collectionScript = """
    (function() {
        const result = {
            navigation: null,
            resources: [],
            paints: [],
            lcp: -1,
            cls: -1,
            tbt: -1
        };

        // Navigation Timing
        const navEntries = performance.getEntriesByType('navigation');
        if (navEntries.length > 0) {
            const nav = navEntries[0];
            result.navigation = {
                startTime: nav.startTime,
                redirectTime: nav.redirectEnd - nav.redirectStart,
                dnsTime: nav.domainLookupEnd - nav.domainLookupStart,
                tcpTime: nav.connectEnd - nav.connectStart,
                tlsTime: nav.secureConnectionStart > 0 ? nav.connectEnd - nav.secureConnectionStart : 0,
                timeToFirstByte: nav.responseStart - nav.startTime,
                requestTime: nav.responseStart - nav.requestStart,
                responseTime: nav.responseEnd - nav.responseStart,
                domProcessingTime: nav.domComplete - nav.domInteractive,
                domContentLoadedTime: nav.domContentLoadedEventEnd - nav.startTime,
                loadEventTime: nav.loadEventEnd - nav.startTime
            };
        }

        // Resource Timing
        const resourceEntries = performance.getEntriesByType('resource');
        result.resources = resourceEntries.map(r => ({
            name: r.name,
            initiatorType: r.initiatorType,
            startTime: r.startTime,
            duration: r.duration,
            transferSize: r.transferSize || 0,
            encodedBodySize: r.encodedBodySize || 0,
            decodedBodySize: r.decodedBodySize || 0
        }));

        // Paint Timing
        const paintEntries = performance.getEntriesByType('paint');
        result.paints = paintEntries.map(p => ({
            name: p.name,
            startTime: p.startTime
        }));

        // LCP (Largest Contentful Paint)
        // Prefer observer value, fallback to getEntriesByType
        try {
            if (typeof window.__webVitals_lcp === 'number' && window.__webVitals_lcp >= 0) {
                result.lcp = window.__webVitals_lcp;
            } else {
                const lcpEntries = performance.getEntriesByType('largest-contentful-paint');
                if (lcpEntries.length > 0) {
                    result.lcp = lcpEntries[lcpEntries.length - 1].startTime;
                }
            }
        } catch (e) {}

        // CLS (Cumulative Layout Shift)
        if (typeof window.__webVitals_cls === 'number') {
            result.cls = window.__webVitals_cls;
        }

        // TBT approximation - sum of long task blocking time
        try {
            const longTasks = performance.getEntriesByType('longtask');
            let tbt = 0;
            for (const task of longTasks) {
                const blockingTime = task.duration - 50; // 50ms threshold
                if (blockingTime > 0) {
                    tbt += blockingTime;
                }
            }
            result.tbt = tbt;
        } catch (e) {}

        return JSON.stringify(result);
    })()
    """

    @MainActor
    func collect(using navigator: WebViewNavigator, reload: Bool) async {
        let id = UUID()
        collectionID = id
        isLoading = true
        isReloading = reload
        lastError = nil
        defer {
            if collectionID == id {
                isLoading = false
                isReloading = false
            }
        }

        guard navigator.isAttached else {
            lastError = "Failed to collect performance data. Make sure a page is loaded."
            return
        }
        let initialDocument = navigator.documentID
        if reload {
            clear()
            navigator.reload()
        }

        let script = """
        if (document.readyState === 'complete' &&
            (performance.getEntriesByType('navigation')[0]?.loadEventEnd ?? 1) > 0) {
            \(Self.collectionScript)
        }
        """
        for _ in 0..<20 {
            guard !Task.isCancelled, collectionID == id else { return }
            let document = navigator.documentID
            if !reload || document != initialDocument {
                let result = await navigator.evaluateJavaScript(script)
                guard !Task.isCancelled, collectionID == id else { return }
                if navigator.documentID == document, let result = result as? String {
                    parseData(from: result)
                    if data.navigation == nil && data.paints.isEmpty {
                        lastError = "Page load incomplete. Try refreshing again."
                    }
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        if !Task.isCancelled, collectionID == id {
            lastError = "Page load incomplete. Try refreshing again."
        }
    }

    func parseData(from jsonString: String) {
        guard let jsonData = jsonString.data(using: .utf8) else {
            lastError = "Failed to convert string to data"
            return
        }

        do {
            let decoded = try JSONDecoder().decode(RawPerformanceData.self, from: jsonData)
            data = PerformanceData(
                navigation: decoded.navigation,
                resources: decoded.resources.map { raw in
                    ResourceTiming(
                        id: UUID(),
                        name: raw.name,
                        initiatorType: raw.initiatorType,
                        startTime: raw.startTime,
                        duration: raw.duration,
                        transferSize: raw.transferSize,
                        encodedBodySize: raw.encodedBodySize,
                        decodedBodySize: raw.decodedBodySize
                    )
                },
                paints: decoded.paints,
                timestamp: Date(),
                cls: decoded.cls,
                tbt: decoded.tbt,
                largestContentfulPaint: decoded.lcp >= 0 ? decoded.lcp : nil
            )
            lastError = nil
        } catch {
            lastError = "Parse error: \(error.localizedDescription)"
        }
    }

    func clear() {
        data = PerformanceData()
        lastError = nil
    }
}

// Raw JSON structures for decoding
private struct RawPerformanceData: Codable {
    let navigation: NavigationTiming?
    let resources: [RawResourceTiming]
    let paints: [PaintTiming]
    let lcp: Double
    let cls: Double
    let tbt: Double
}

private struct RawResourceTiming: Codable {
    let name: String
    let initiatorType: String
    let startTime: Double
    let duration: Double
    let transferSize: Int
    let encodedBodySize: Int
    let decodedBodySize: Int
}
