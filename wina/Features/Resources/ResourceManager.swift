//
//  ResourceManager.swift
//  wina
//
//  Manages resource timing entries from Performance API.
//

import Foundation

// MARK: - Resource Manager

@Observable
class ResourceManager {
    var resources: [ResourceEntry] = []
    var isCapturing: Bool = true
    var agentDocumentID: UUID?

    private let maxResourceCount = 1000

    // Read preserveLog from UserDefaults (shared with NetworkManager)
    var preserveLog: Bool {
        UserDefaults.standard.bool(forKey: "networkPreserveLog")
    }

    // swiftlint:disable:next function_parameter_count
    private func addResource(
        name: String,
        initiatorType: String,
        startTime: Double,
        duration: Double,
        transferSize: Int,
        encodedBodySize: Int,
        decodedBodySize: Int,
        dnsTime: Double,
        tcpTime: Double,
        tlsTime: Double,
        requestTime: Double,
        responseTime: Double
    ) {
        guard isCapturing else { return }

        // Skip duplicate entries (same URL and startTime)
        let isDuplicate = resources.contains { entry in
            entry.agentDocumentID == agentDocumentID && entry.name == name && abs(entry.startTime - startTime) < 1
        }
        guard !isDuplicate else { return }

        let entry = ResourceEntry(
            id: UUID(),
            name: name,
            initiatorType: .init(rawString: initiatorType, url: name),
            startTime: startTime,
            duration: duration,
            transferSize: transferSize,
            encodedBodySize: encodedBodySize,
            decodedBodySize: decodedBodySize,
            dnsTime: dnsTime,
            tcpTime: tcpTime,
            tlsTime: tlsTime,
            requestTime: requestTime,
            responseTime: responseTime,
            timestamp: Date(),
            agentDocumentID: agentDocumentID
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.resources.count >= self.maxResourceCount {
                self.resources.removeFirst()
            }
            self.resources.append(entry)
        }
    }

    func addResources(from entries: [[String: Any]]) {
        for entry in entries {
            guard let name = entry["name"] as? String else { continue }

            addResource(
                name: name,
                initiatorType: entry["initiatorType"] as? String ?? "other",
                startTime: entry["startTime"] as? Double ?? 0,
                duration: entry["duration"] as? Double ?? 0,
                transferSize: entry["transferSize"] as? Int ?? 0,
                encodedBodySize: entry["encodedBodySize"] as? Int ?? 0,
                decodedBodySize: entry["decodedBodySize"] as? Int ?? 0,
                dnsTime: entry["dnsTime"] as? Double ?? 0,
                tcpTime: entry["tcpTime"] as? Double ?? 0,
                tlsTime: entry["tlsTime"] as? Double ?? 0,
                requestTime: entry["requestTime"] as? Double ?? 0,
                responseTime: entry["responseTime"] as? Double ?? 0
            )
        }
    }

    func clear() {
        resources.removeAll()
    }

    func clearIfNotPreserved() {
        guard !preserveLog else { return }
        clear()
    }

    // MARK: - Statistics

    var stats: ResourceStats {
        var byType: [ResourceEntry.InitiatorType: (count: Int, size: Int)] = [:]

        for resource in resources {
            let size = resource.transferSize > 0 ? resource.transferSize :
                       (resource.encodedBodySize > 0 ? resource.encodedBodySize : resource.decodedBodySize)
            let current = byType[resource.initiatorType] ?? (count: 0, size: 0)
            byType[resource.initiatorType] = (count: current.count + 1, size: current.size + size)
        }

        let totalSize = resources.reduce(0) { sum, resource in
            let size = resource.transferSize > 0 ? resource.transferSize :
                       (resource.encodedBodySize > 0 ? resource.encodedBodySize : resource.decodedBodySize)
            return sum + size
        }

        let totalDuration = resources.map(\.duration).max() ?? 0

        return ResourceStats(
            totalCount: resources.count,
            totalSize: totalSize,
            totalDuration: totalDuration,
            byType: byType
        )
    }

    func count(for filter: ResourceFilter) -> Int {
        if filter == .all {
            return resources.count
        }
        return resources.filter { filter.matches($0.initiatorType) }.count
    }
}
