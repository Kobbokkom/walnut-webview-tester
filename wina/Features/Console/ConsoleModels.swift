//
//  ConsoleModels.swift
//  wina
//
//  Console data models for DevTools.
//

import SwiftUI

// MARK: - Console Log Model

struct ConsoleLog: Identifiable, Equatable {
    let id = UUID()
    let type: LogType
    let message: String
    let source: String?  // e.g., "main.js:45"
    var timestamp: Date
    var groupLevel: Int = 0  // Indentation level for groups
    var groupId: UUID?  // For groupCollapsed toggle
    var isCollapsed: Bool = false  // For groupCollapsed
    var tableData: [[String: String]]?  // For console.table

    // ✨ Timer Support (console.time/timeLog/timeEnd)
    var timerLabel: String?
    var timerElapsed: TimeInterval?

    // ✨ Count Support (console.count/countReset)
    var countLabel: String?
    var countValue: Int?

    // ✨ Trace Support (console.trace)
    var stackTrace: String?

    // ✨ Styled Segments Support (console.log("%c..."))
    var styledSegments: [[String: Any]]?  // Raw JSON from JavaScript

    // ✨ Inline Segments Support (console.log("label", 1, true))
    var inlineSegments: [ConsoleInlineSegment]?

    // ✨ Object Support (console.dir, console.log with objects)
    var objectValue: ConsoleValue?
    var repeatCount: Int = 1
    var agentDocumentID: UUID?

    enum LogType: String, CaseIterable {
        case log
        case info
        case warn
        case error
        case debug
        case group
        case groupCollapsed
        case groupEnd
        case table
        // ✨ New types
        case time           // console.time
        case timeLog        // console.timeLog
        case timeEnd        // console.timeEnd
        case count          // console.count
        case countReset     // console.countReset
        case assert         // console.assert
        case dir            // console.dir
        case trace          // console.trace
        case command        // User input command
        case result         // Command execution result

        var icon: String {
            switch self {
            case .log: return "chevron.right"
            case .info: return "info.circle.fill"
            case .warn: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            case .debug: return "ant.fill"
            case .group, .groupCollapsed: return "folder"
            case .groupEnd: return "folder"
            case .table: return "tablecells"
            case .time, .timeLog, .timeEnd: return "stopwatch.fill"
            case .count, .countReset: return "number.circle.fill"
            case .assert: return "exclamationmark.circle.fill"
            case .dir: return "tree"
            case .trace: return "arrow.down.right.circle.fill"
            case .command: return "chevron.right.circle.fill"
            case .result: return "checkmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .log: return .secondary
            case .info: return .blue
            case .warn: return .orange
            case .error: return .red
            case .debug: return .purple
            case .group, .groupCollapsed, .groupEnd: return .secondary
            case .table: return .cyan
            case .time, .timeLog, .timeEnd: return .mint
            case .count, .countReset: return .indigo
            case .assert: return .orange
            case .dir: return .blue
            case .trace: return .gray
            case .command: return .cyan
            case .result: return .green
            }
        }

        var label: String {
            switch self {
            case .log: return "Log"
            case .info: return "Info"
            case .warn: return "Warnings"
            case .error: return "Errors"
            case .debug: return "Debug"
            case .group, .groupCollapsed: return "Group"
            case .groupEnd: return "GroupEnd"
            case .table: return "Table"
            case .time: return "Timer"
            case .timeLog: return "Timer"
            case .timeEnd: return "Timer"
            case .count: return "Count"
            case .countReset: return "Count"
            case .assert: return "Assert"
            case .dir: return "Dir"
            case .trace: return "Trace"
            case .command: return "Command"
            case .result: return "Result"
            }
        }

        var shortLabel: String {
            switch self {
            case .log: return "LOG"
            case .info: return "INFO"
            case .warn: return "WARN"
            case .error: return "ERROR"
            case .debug: return "DEBUG"
            case .group: return "GROUP"
            case .groupCollapsed: return "GROUP"
            case .groupEnd: return "END"
            case .table: return "TABLE"
            case .time: return "TIME"
            case .timeLog: return "TIME"
            case .timeEnd: return "TIME"
            case .count: return "COUNT"
            case .countReset: return "COUNT"
            case .assert: return "ASSERT"
            case .dir: return "DIR"
            case .trace: return "TRACE"
            case .command: return "CMD"
            case .result: return "RES"
            }
        }

        // Types shown in filter tabs
        static var filterTypes: [LogType] {
            [.error, .warn, .info, .log, .debug, .assert, .trace]
        }

        // Types that can be displayed (excludes internal types like groupEnd)
        static var displayableTypes: [LogType] {
            [
                .log, .info, .warn, .error, .debug, .group, .groupCollapsed, .table,
                .time, .timeLog, .timeEnd, .count, .countReset, .assert, .dir, .trace,
                .command, .result
            ]
        }

        // Types shown in settings (one representative per label group)
        static var settingsDisplayTypes: [LogType] {
            [.log, .info, .warn, .error, .debug, .group, .table, .time, .count, .assert, .dir, .trace, .command, .result]
        }

        // Related types controlled by a representative type (for settings toggles)
        var relatedTypes: [LogType] {
            switch self {
            case .group: return [.group, .groupCollapsed]
            case .time: return [.time, .timeLog, .timeEnd]
            case .count: return [.count, .countReset]
            default: return [self]
            }
        }
    }

    static func == (lhs: ConsoleLog, rhs: ConsoleLog) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Scroll Metrics

struct ScrollMetrics: Equatable {
    let offset: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
}

// MARK: - Share Content

struct ShareContent: Identifiable, Equatable {
    let id = UUID()
    let content: String

    static func == (lhs: ShareContent, rhs: ShareContent) -> Bool {
        lhs.id == rhs.id
    }
}
