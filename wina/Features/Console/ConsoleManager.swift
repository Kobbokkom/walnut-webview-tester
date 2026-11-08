//
//  ConsoleManager.swift
//  wina
//
//  Console log manager for DevTools.
//

import Foundation

// MARK: - Console Manager

@Observable
class ConsoleManager {
    var logs: [ConsoleLog] = []
    var isCapturing: Bool = true
    var agentDocumentID: UUID?
    var collapsedGroups: Set<UUID> = []
    private var currentGroupLevel: Int = 0
    private var groupStack: [UUID] = []

    // Memory management: max logs limit
    private let maxLogs = 5000

    // ✨ Timer support (console.time/timeEnd)
    private var timerContexts: [String: Date] = [:]

    // ✨ Count support (console.count/countReset)
    private var countContexts: [String: Int] = [:]

    // Read preserveLog from UserDefaults (set via @AppStorage in ConsoleSettingsSheet)
    var preserveLog: Bool {
        UserDefaults.standard.bool(forKey: "consolePreserveLog")
    }

    func addLog(
        type: String,
        message: String,
        source: String? = nil,
        tableData: [[String: String]]? = nil,
        objectValue: ConsoleValue? = nil,
        styledSegments: [[String: Any]]? = nil,
        inlineSegments: [ConsoleInlineSegment]? = nil
    ) {
        guard isCapturing else { return }

        // Filter CORS "Script error" - uninformative due to cross-origin security
        let msg = message.lowercased()
        if msg.contains("script error") && (source == nil || source?.isEmpty == true) {
            return
        }

        let logType = ConsoleLog.LogType(rawValue: type) ?? .log
        let document = agentDocumentID

        DispatchQueue.main.async {
            var log = ConsoleLog(type: logType, message: message, source: source, timestamp: Date())
            log.agentDocumentID = document
            log.tableData = tableData
            log.objectValue = objectValue
            log.styledSegments = styledSegments
            log.inlineSegments = inlineSegments

            // Handle group levels
            switch logType {
            case .group:
                log.groupLevel = self.currentGroupLevel
                let groupId = UUID()
                log.groupId = groupId
                self.groupStack.append(groupId)
                self.currentGroupLevel += 1
            case .groupCollapsed:
                log.groupLevel = self.currentGroupLevel
                let groupId = UUID()
                log.groupId = groupId
                log.isCollapsed = true
                self.groupStack.append(groupId)
                self.collapsedGroups.insert(groupId)
                self.currentGroupLevel += 1
            case .groupEnd:
                if self.currentGroupLevel > 0 {
                    self.currentGroupLevel -= 1
                    _ = self.groupStack.popLast()
                }
                log.groupLevel = self.currentGroupLevel
            default:
                log.groupLevel = self.currentGroupLevel
                if let currentGroup = self.groupStack.last {
                    log.groupId = currentGroup
                }
            }

            if self.shouldCollapseRepeat(log: log), let lastIndex = self.logs.indices.last {
                var updated = self.logs[lastIndex]
                if updated.agentDocumentID == document, self.isSameRepeat(lhs: updated, rhs: log) {
                    updated.repeatCount += 1
                    updated.timestamp = log.timestamp
                    self.logs[lastIndex] = updated
                    return
                }
            }

            self.logs.append(log)

            // Auto-trim if exceeding max logs limit
            if self.logs.count > self.maxLogs {
                self.logs.removeFirst(self.logs.count - self.maxLogs)
            }
        }
    }

    private func shouldCollapseRepeat(log: ConsoleLog) -> Bool {
        switch log.type {
        case .log, .info, .warn, .error, .debug, .dir, .trace:
            return true
        default:
            return false
        }
    }

    private func isSameRepeat(lhs: ConsoleLog, rhs: ConsoleLog) -> Bool {
        guard lhs.type == rhs.type,
              lhs.message == rhs.message,
              lhs.source == rhs.source,
              lhs.groupLevel == rhs.groupLevel,
              lhs.groupId == rhs.groupId,
              lhs.tableData == rhs.tableData,
              lhs.objectValue == rhs.objectValue,
              lhs.inlineSegments == rhs.inlineSegments else {
            return false
        }
        return styledSegmentsEqual(lhs.styledSegments, rhs.styledSegments)
    }

    private func styledSegmentsEqual(_ lhs: [[String: Any]]?, _ rhs: [[String: Any]]?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhsArray?, rhsArray?):
            return NSArray(array: lhsArray).isEqual(rhsArray)
        default:
            return false
        }
    }

    func toggleGroup(_ groupId: UUID) {
        if collapsedGroups.contains(groupId) {
            collapsedGroups.remove(groupId)
        } else {
            collapsedGroups.insert(groupId)
        }
    }

    // MARK: - Timer Methods (console.time/timeLog/timeEnd)

    /// console.time(label) - 타이머 시작
    func time(label: String = "default") {
        let document = agentDocumentID
        DispatchQueue.main.async {
            self.timerContexts[label] = Date()
            var log = ConsoleLog(type: .time, message: "Timer '\(label)' started", source: nil, timestamp: Date())
            log.agentDocumentID = document
            log.timerLabel = label
            self.logs.append(log)
        }
    }

    /// console.timeLog(label) - 현재까지 경과 시간 로깅
    func timeLog(label: String = "default") {
        let document = agentDocumentID
        DispatchQueue.main.async {
            guard let startTime = self.timerContexts[label] else {
                self.addLog(type: "error", message: "Timer '\(label)' not found")
                return
            }
            let elapsed = Date().timeIntervalSince(startTime) * 1000  // milliseconds
            var log = ConsoleLog(type: .timeLog, message: "\(label): \(String(format: "%.3f", elapsed))ms", source: nil, timestamp: Date())
            log.agentDocumentID = document
            log.timerLabel = label
            log.timerElapsed = elapsed / 1000
            self.logs.append(log)
        }
    }

    /// console.timeEnd(label) - 타이머 종료 및 결과 로깅
    func timeEnd(label: String = "default") {
        let document = agentDocumentID
        DispatchQueue.main.async {
            guard let startTime = self.timerContexts[label] else {
                self.addLog(type: "error", message: "Timer '\(label)' not found")
                return
            }
            let elapsed = Date().timeIntervalSince(startTime) * 1000  // milliseconds
            self.timerContexts.removeValue(forKey: label)
            var log = ConsoleLog(type: .timeEnd, message: "\(label): \(String(format: "%.3f", elapsed))ms", source: nil, timestamp: Date())
            log.agentDocumentID = document
            log.timerLabel = label
            log.timerElapsed = elapsed / 1000
            self.logs.append(log)
        }
    }

    // MARK: - Count Methods (console.count/countReset)

    /// console.count(label) - 카운트 증가 및 로깅
    func count(label: String = "default") {
        let document = agentDocumentID
        DispatchQueue.main.async {
            let newCount = (self.countContexts[label] ?? 0) + 1
            self.countContexts[label] = newCount
            var log = ConsoleLog(type: .count, message: "\(label): \(newCount)", source: nil, timestamp: Date())
            log.agentDocumentID = document
            log.countLabel = label
            log.countValue = newCount
            self.logs.append(log)
        }
    }

    /// console.countReset(label) - 카운트 리셋
    func countReset(label: String = "default") {
        DispatchQueue.main.async {
            let previousCount = self.countContexts[label] ?? 0
            self.countContexts.removeValue(forKey: label)
            self.addLog(type: "countReset", message: "\(label) count reset (was \(previousCount))")
        }
    }

    /// console.assert(condition, message) - 조건 검증
    func assert(_ condition: Bool, message: String) {
        guard !condition else { return }
        DispatchQueue.main.async {
            self.addLog(type: "assert", message: "Assertion failed: \(message)")
        }
    }

    func clear() {
        logs.removeAll()
        currentGroupLevel = 0
        groupStack.removeAll()
        collapsedGroups.removeAll()
        timerContexts.removeAll()
        countContexts.removeAll()
    }

    func clearIfNotPreserved() {
        guard !preserveLog else { return }
        clear()
    }

    var errorCount: Int { logs.filter { $0.type == .error }.count }
    var warnCount: Int { logs.filter { $0.type == .warn }.count }

    // Export logs as formatted text
    func exportAsText() -> String {
        ConsoleExporter.exportAsText(logs)
    }

    // Export logs as JSON
    func exportAsJSON() -> String {
        ConsoleExporter.exportAsJSON(logs)
    }
}
