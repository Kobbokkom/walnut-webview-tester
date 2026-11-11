//
//  ConsoleComponents.swift
//  wina
//
//  Supporting views for ConsoleView.
//

import SwiftUI

// MARK: - Console Filter Tab

struct ConsoleFilterTab: View {
    let label: String
    let count: Int
    let isSelected: Bool
    var color: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                if count != 0 {  // swiftlint:disable:this empty_count
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(isSelected ? color.opacity(0.2) : Color.secondary.opacity(0.15), in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? color : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(color)
                        .frame(height: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Log Row

struct LogRow: View {
    let log: ConsoleLog
    let consoleManager: ConsoleManager
    @State private var isExpanded: Bool = false
    @State private var showCopyFeedback: Bool = false
    @State private var copyFeedbackMessage: String = ""

    /// 복사용 전체 문자열 (message + objectValue)
    private var fullCopyableString: String {
        var result = log.message
        if let objValue = log.objectValue {
            if !result.isEmpty {
                result += "\n"
            }
            result += objValue.copyableString
        }
        return result
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    // Indentation based on group level (12pt per level)
    private var indentation: CGFloat {
        CGFloat(log.groupLevel) * 12
    }

    // Check if this is a group header
    private var isGroupHeader: Bool {
        log.type == .group || log.type == .groupCollapsed
    }

    // Check if group is collapsed
    private var isGroupCollapsed: Bool {
        guard let groupId = log.groupId else { return false }
        return consoleManager.collapsedGroups.contains(groupId)
    }

    // Check if message needs expansion
    // - 4+ lines (explicit multiline)
    private var needsExpansion: Bool {
        guard log.type != .table else { return false }
        return log.message.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count >= 4
    }

    // Parse table data from message JSON
    private var parsedTableData: [[String: String]]? {
        guard log.type == .table else { return nil }
        if let tableData = log.tableData { return tableData }
        return JSONParser.parseTableData(from: log.message)
    }

    // Extract JSON from message (returns original, formatted and minified versions)
    private var extractedJSON: JSONParser.ParsedJSON? {
        guard log.type != .table else { return nil }
        return JSONParser.extract(from: log.message)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Main content row
            HStack(alignment: .top, spacing: 8) {
                // Group toggle or expand indicator
                if isGroupHeader {
                    Image(systemName: isGroupCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                        .padding(.top, 4)
                } else if needsExpansion {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                        .padding(.top, 4)
                }

                // Content area
                Group {
                    if log.type == .table, let tableData = parsedTableData {
                        // Table rendering
                        tableView(data: tableData)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            if let segments = log.styledSegments, !segments.isEmpty {
                                styledSegmentsText(segments: segments)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(isExpanded || !needsExpansion ? nil : 3)
                                    .truncationMode(.tail)
                            } else if let inlineSegments = log.inlineSegments, !inlineSegments.isEmpty, !isGroupHeader {
                                inlineSegmentsText(segments: inlineSegments)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(isExpanded || !needsExpansion ? nil : 3)
                                    .truncationMode(.tail)
                            } else if !log.message.isEmpty || isGroupHeader {
                                // Regular message
                                HStack(alignment: .top, spacing: 4) {
                                    // Group header has folder icon
                                    if isGroupHeader {
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(log.message)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(log.type == .error ? .red : (isGroupHeader ? .secondary : .primary))
                                        .fontWeight(isGroupHeader ? .semibold : .regular)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(isExpanded || !needsExpansion ? nil : 3)
                                        .truncationMode(.tail)

                                    // JSON copy button (only if JSON detected)
                                    if let json = extractedJSON {
                                        Menu {
                                            Button {
                                                UIPasteboard.general.string = json.formatted
                                                copyFeedbackMessage = "Copied formatted JSON"
                                                showCopyFeedback = true
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                                    showCopyFeedback = false
                                                }
                                            } label: {
                                                Label("Copy Formatted", systemImage: "doc.on.doc")
                                            }
                                            Button {
                                                UIPasteboard.general.string = json.minified
                                                copyFeedbackMessage = "Copied minified JSON"
                                                showCopyFeedback = true
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                                    showCopyFeedback = false
                                                }
                                            } label: {
                                                Label("Copy Minified", systemImage: "arrow.right.arrow.left")
                                            }
                                        } label: {
                                            Image(systemName: "curlybraces")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.blue)
                                                .padding(4)
                                                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                                        }
                                    }
                                }
                            }

                            if let objValue = log.objectValue {
                                // Object/Array value with tree view
                                ConsoleValueView(value: objValue)
                            }
                        }
                    }
                }

                // Right side: repeat count + type badge
                HStack(spacing: 6) {
                    if log.repeatCount > 1 {
                        Text("×\(log.repeatCount)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }

                    ConsoleTypeBadge(type: log.type)
                }
            }

            // Footer row: Source + Copy + Timestamp (always at the bottom)
            HStack(spacing: 6) {
                if let source = log.source {
                    Text(source)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(isExpanded ? nil : 1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                Button {
                    UIPasteboard.general.string = fullCopyableString
                    copyFeedbackMessage = "Copied"
                    showCopyFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopyFeedback = false
                    }
                } label: {
                    Image(systemName: showCopyFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(showCopyFeedback ? Color.green : Color.gray)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: showCopyFeedback)
                Text(Self.timeFormatter.string(from: log.timestamp))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, isGroupHeader || needsExpansion ? 18 : 0)
        }
        .padding(.leading, 12 + indentation)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(
            log.type == .error ? Color.red.opacity(0.08) : (isGroupHeader ? Color.secondary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isGroupHeader, let groupId = log.groupId {
                withAnimation(.easeInOut(duration: 0.2)) {
                    consoleManager.toggleGroup(groupId)
                }
            } else if needsExpansion {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 12 + indentation)
        }
        .overlay(alignment: .center) {
            if showCopyFeedback {
                CopiedFeedbackToast(message: copyFeedbackMessage)
                    .transition(.opacity)
            }
        }
    }

    private func styledSegmentsText(segments: [[String: Any]]) -> Text {
        var result = AttributedString()
        for segment in segments {
            let text = segment["text"] as? String ?? ""
            let colorStr = segment["color"] as? String
            let bgColorStr = segment["backgroundColor"] as? String
            let isBold = segment["isBold"] as? Bool ?? false
            let fontSize = segment["fontSize"] as? Int

            var part = AttributedString(text)
            part.foregroundColor = colorFromString(colorStr) ?? .primary
            part.backgroundColor = colorFromString(bgColorStr) ?? .clear
            part.font = .system(size: CGFloat(fontSize ?? 12), weight: isBold ? .semibold : .regular, design: .monospaced)
            result.append(part)
        }
        return Text(result)
    }

    private func inlineSegmentsText(segments: [ConsoleInlineSegment]) -> Text {
        var result = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text)
            part.foregroundColor = inlineSegmentColor(segment.kind)
            part.font = .system(size: 12, design: .monospaced)
            result.append(part)
        }
        return Text(result)
    }

    private func inlineSegmentColor(_ kind: ConsoleInlineKind?) -> Color {
        guard let kind else {
            return .primary
        }
        switch kind {
        case .string:
            return Color(red: 0.9, green: 0.6, blue: 0.0)
        case .number:
            return Color(red: 0.2, green: 0.7, blue: 1.0)
        case .boolean:
            return Color(red: 0.8, green: 0.2, blue: 0.8)
        case .null, .undefined:
            return Color(red: 0.7, green: 0.7, blue: 0.7)
        case .function:
            return .orange
        case .date:
            return .purple
        case .error:
            return .red
        case .dom, .regexp:
            return .red
        case .symbol, .bigint, .map, .set, .array, .object, .circular:
            return .secondary
        }
    }

    private func colorFromString(_ cssColor: String?) -> Color? {
        guard let cssColor = cssColor?.lowercased().trimmingCharacters(in: .whitespaces) else { return nil }

        // Common CSS color names
        let colorMap: [String: Color] = [
            "red": .red, "blue": .blue, "green": .green, "yellow": .yellow,
            "orange": .orange, "purple": .purple, "pink": .pink, "gray": .gray,
            "black": .black, "white": .white, "cyan": .cyan, "indigo": .indigo,
            "mint": .mint, "teal": .teal
        ]

        if let color = colorMap[cssColor] {
            return color
        }

        // Handle hex colors (simplified)
        if cssColor.hasPrefix("#") {
            let hex = String(cssColor.dropFirst())
            if hex.count == 6 {
                if let rgbValue = UInt(hex, radix: 16) {
                    let red = Double((rgbValue >> 16) & 0xFF) / 255.0
                    let green = Double((rgbValue >> 8) & 0xFF) / 255.0
                    let blue = Double(rgbValue & 0xFF) / 255.0
                    return Color(red: red, green: green, blue: blue)
                }
            }
        }

        // Handle rgb/rgba
        if cssColor.hasPrefix("rgb") {
            // Simplified: just return primary for now
            return nil
        }

        return nil
    }

    // MARK: - Table View

    @ViewBuilder
    private func tableView(data: [[String: String]]) -> some View {
        // Sort columns with (index) first, then alphabetically
        let allColumns = data.first?.keys.sorted() ?? []
        let columns = allColumns.sorted { lhs, rhs in
            if lhs == "(index)" { return true }
            if rhs == "(index)" { return false }
            return lhs < rhs
        }

        if columns.isEmpty {
            Text("(empty table)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.tertiary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    // Header row
                    GridRow {
                        ForEach(columns, id: \.self) { column in
                            Text(column)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: column == "(index)" ? 50 : 60, maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                        }
                    }
                    .background(Color.secondary.opacity(0.1))

                    // Data rows
                    ForEach(Array(data.enumerated()), id: \.offset) { index, row in
                        GridRow {
                            ForEach(columns, id: \.self) { column in
                                Text(row[column] ?? "")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(column == "(index)" ? .tertiary : .primary)
                                    .frame(minWidth: column == "(index)" ? 50 : 60, maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                            }
                        }
                        .background(index.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.03))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                }
            }
        }
    }
}

// MARK: - Console Type Badge

struct ConsoleTypeBadge: View {
    let type: ConsoleLog.LogType

    var body: some View {
        Text(type.shortLabel)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(type.color)
            .frame(width: 48, alignment: .trailing)
    }
}

// MARK: - Console Settings Sheet

struct ConsoleSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var useRegex: Bool
    @Binding var preserveLog: Bool
    @Binding var clearStrategy: LogClearStrategy
    var logTypeEnabled: (ConsoleLog.LogType) -> Binding<Bool>

    var body: some View {
        NavigationStack {
            List {
                Section("Search") {
                    HStack {
                        Toggle("Regex Filter", isOn: $useRegex)
                        InfoPopoverButton(text: "Use regular expressions for filtering logs.")
                    }
                }

                Section("Logging") {
                    HStack {
                        Picker("Clear Strategy", selection: $clearStrategy) {
                            ForEach(LogClearStrategy.allCases, id: \.self) { strategy in
                                Text(strategy.displayName).tag(strategy)
                            }
                        }
                        InfoPopoverButton(
                            text: """
                            When to clear logs during navigation:
                            • Keep All: Manual clear only
                            • Same Origin: Clear when leaving domain
                            • Each Page: Clear on every navigation
                            """
                        )
                    }

                    HStack {
                        Toggle("Preserve on Reload", isOn: $preserveLog)
                        InfoPopoverButton(text: "Keep logs when the page is reloaded.")
                    }
                }

                Section("Log Types in 'All' Tab") {
                    ForEach(ConsoleLog.LogType.settingsDisplayTypes, id: \.self) { type in
                        Toggle(isOn: logTypeEnabled(type)) {
                            HStack(spacing: 8) {
                                Image(systemName: type.icon)
                                    .foregroundStyle(type.color)
                                    .frame(width: 20)
                                Text(type.label)
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Console Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
