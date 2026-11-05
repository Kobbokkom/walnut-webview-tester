import SwiftUI

// MARK: - JSON Editor Sheet

/// Full-screen JSON editor with tree-based editing and CRUD operations
struct JsonEditorSheet: View {
    @Binding var jsonText: String
    @Environment(\.dismiss) private var dismiss

    @State private var draftText: String

    init(jsonText: Binding<String>) {
        self._jsonText = jsonText
        self._draftText = State(initialValue: jsonText.wrappedValue)
    }

    @State private var editingNode: JsonNode?
    @State private var addingToNode: JsonNode?
    @State private var parseResult: JsonParser.ParseResult = .empty
    @State private var expandedNodes: Set<String> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let node = parseResult.node {
                    treeEditorView(node: node)
                } else {
                    invalidJsonView
                }
            }
            .navigationTitle("Edit JSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        jsonText = draftText
                        dismiss()
                    }
                }
            }
            .onAppear {
                parseResult = JsonParser.parse(draftText)
            }
        }
    }

    // MARK: - Tree Editor

    private func treeEditorView(node: JsonNode) -> some View {
        List {
            Section {
                // Root level controls
                rootControls(for: node)

                ForEach(node.children ?? [node]) { child in
                    JsonNodeRow(
                        node: child,
                        expandedNodes: $expandedNodes,
                        onEdit: { editNode($0) },
                        onAdd: { addToNode($0) },
                        onDelete: { deleteNode($0) }
                    )
                }
            } header: {
                HStack {
                    Text("Structure")
                    Spacer()
                    Button("Expand All") {
                        expandAll(from: node)
                    }
                    .font(.caption)
                    Button("Collapse") {
                        expandedNodes.removeAll()
                    }
                    .font(.caption)
                }
            }
        }
        .sheet(item: $editingNode) { node in
            NodeEditSheet(
                node: node,
                jsonText: $draftText,
                onSave: { refreshParseResult() }
            )
        }
        .sheet(item: $addingToNode) { node in
            AddNodeSheet(
                parentNode: node,
                jsonText: $draftText,
                onSave: { refreshParseResult() }
            )
        }
    }

    @ViewBuilder
    private func rootControls(for node: JsonNode) -> some View {
        switch node.value {
        case .object:
            Button {
                addingToNode = node
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                    Text("Add Property")
                }
                .foregroundStyle(.blue)
            }
        case .array:
            Button {
                addingToNode = node
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                    Text("Add Item")
                }
                .foregroundStyle(.blue)
            }
        default:
            EmptyView()
        }
    }

    private var invalidJsonView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Invalid JSON")
                .font(.headline)
            if let error = parseResult.error {
                Text(error.displayMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func editNode(_ node: JsonNode) {
        editingNode = node
    }

    private func addToNode(_ node: JsonNode) {
        addingToNode = node
    }

    private func deleteNode(_ node: JsonNode) {
        guard let updated = JsonParser.delete(draftText, at: node.path) else { return }
        draftText = updated
        refreshParseResult()
    }

    private func refreshParseResult() {
        parseResult = JsonParser.parse(draftText)
    }

    private func expandAll(from node: JsonNode) {
        var ids: Set<String> = []
        collectIds(from: node, into: &ids)
        expandedNodes = ids
    }

    private func collectIds(from node: JsonNode, into ids: inout Set<String>) {
        if node.isExpandable {
            ids.insert(node.id)
            node.children?.forEach { collectIds(from: $0, into: &ids) }
        }
    }
}

// MARK: - JSON Node Row

private struct JsonNodeRow: View {
    let node: JsonNode
    @Binding var expandedNodes: Set<String>
    let onEdit: (JsonNode) -> Void
    let onAdd: (JsonNode) -> Void
    let onDelete: (JsonNode) -> Void

    var body: some View {
        if node.isExpandable {
            expandableRow
        } else {
            leafRow
        }
    }

    private var expandableRow: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedNodes.contains(node.id) },
                set: { newValue in
                    if newValue {
                        expandedNodes.insert(node.id)
                    } else {
                        expandedNodes.remove(node.id)
                    }
                }
            )
        ) {
            // Add button for nested containers
            Button {
                onAdd(node)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                    Text(node.value.isObject ? "Add Property" : "Add Item")
                }
                .font(.system(size: 13))
                .foregroundStyle(.blue)
            }

            ForEach(node.children ?? []) { child in
                JsonNodeRow(
                    node: child,
                    expandedNodes: $expandedNodes,
                    onEdit: onEdit,
                    onAdd: onAdd,
                    onDelete: onDelete
                )
            }
        } label: {
            nodeLabel(showValue: false)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete(node)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                onAdd(node)
            } label: {
                Label(node.value.isObject ? "Add Property" : "Add Item", systemImage: "plus")
            }
            Divider()
            Button(role: .destructive) {
                onDelete(node)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var leafRow: some View {
        Button {
            onEdit(node)
        } label: {
            nodeLabel(showValue: true)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete(node)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                onEdit(node)
            } label: {
                Label("Edit Value", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                onDelete(node)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func nodeLabel(showValue: Bool) -> some View {
        HStack(spacing: 4) {
            if let key = node.key {
                Text(key)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)

                if showValue {
                    Text(":")
                        .foregroundStyle(.secondary)
                }
            }

            if showValue {
                Text(node.displayValue)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(node.displayValue)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
    }
}

// MARK: - Node Edit Sheet

private struct NodeEditSheet: View {
    let node: JsonNode
    @Binding var jsonText: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editedKey: String = ""
    @State private var editedValue: String = ""

    private var isInObject: Bool {
        // Check if parent is object (key exists means it's in an object)
        node.key != nil && !node.key!.hasPrefix("[")
    }

    private var keyChanged: Bool {
        guard let originalKey = node.key else { return false }
        return editedKey != originalKey
    }

    var body: some View {
        NavigationStack {
            Form {
                if node.key != nil, isInObject {
                    Section("Key") {
                        TextField("Key", text: $editedKey)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } else if let key = node.key {
                    Section("Index") {
                        Text(key)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Value") {
                    TextEditor(text: $editedValue)
                        .font(.system(size: 14, design: .monospaced))
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveValue()
                    }
                    .disabled(isInObject && editedKey.isEmpty)
                }
            }
            .onAppear {
                editedKey = node.key ?? ""
                editedValue = node.rawValue
            }
        }
        .presentationDetents([.medium])
    }

    private func saveValue() {
        // Convert edited value to appropriate type
        let newValue: Any
        switch node.typeColor {
        case .string:
            newValue = editedValue
        case .number:
            newValue = Double(editedValue) ?? 0
        case .bool:
            newValue = editedValue.lowercased() == "true"
        case .null:
            newValue = NSNull()
        case .object, .array:
            // For complex types, try to parse as JSON
            if let data = editedValue.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data)
            {
                newValue = parsed
            } else {
                newValue = editedValue
            }
        }

        if keyChanged, isInObject {
            // Key changed: delete old, add new
            let parentPath = Array(node.path.dropLast())
            if let deleted = JsonParser.delete(jsonText, at: node.path),
               let updated = JsonParser.addToObject(deleted, at: parentPath, key: editedKey, value: newValue)
            {
                jsonText = updated
                onSave()
            }
        } else {
            // Only value changed
            if let updated = JsonParser.update(jsonText, at: node.path, value: newValue) {
                jsonText = updated
                onSave()
            }
        }
        dismiss()
    }
}

// MARK: - Add Node Sheet

private struct AddNodeSheet: View {
    let parentNode: JsonNode
    @Binding var jsonText: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newKey: String = ""
    @State private var newValue: String = ""
    @State private var selectedType: ValueType = .string

    enum ValueType: String, CaseIterable {
        case string = "String"
        case number = "Number"
        case bool = "Boolean"
        case null = "Null"
        case object = "Object"
        case array = "Array"

        var defaultValue: String {
            switch self {
            case .string: return ""
            case .number: return "0"
            case .bool: return "true"
            case .null: return "null"
            case .object: return "{}"
            case .array: return "[]"
            }
        }
    }

    private var isAddingToObject: Bool {
        parentNode.value.isObject
    }

    private var existingKeys: Set<String> {
        guard case let .object(dict) = parentNode.value else { return [] }
        return Set(dict.keys)
    }

    private var isDuplicateKey: Bool {
        isAddingToObject && existingKeys.contains(newKey)
    }

    private var valueValidationError: String? {
        switch selectedType {
        case .object:
            if newValue.isEmpty || newValue == "{}" { return nil }
            guard let data = newValue.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) != nil
            else {
                return "Invalid JSON object"
            }
            return nil
        case .array:
            if newValue.isEmpty || newValue == "[]" { return nil }
            guard let data = newValue.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data) as? [Any]) != nil
            else {
                return "Invalid JSON array"
            }
            return nil
        case .number:
            if Double(newValue) == nil && !newValue.isEmpty {
                return "Invalid number"
            }
            return nil
        default:
            return nil
        }
    }

    private var keyValidationError: String? {
        if isAddingToObject {
            if newKey.isEmpty {
                return nil  // Show nothing if empty (disabled button is enough)
            }
            if isDuplicateKey {
                return "Key '\(newKey)' already exists"
            }
        }
        return nil
    }

    private var canAdd: Bool {
        let keyValid = isAddingToObject ? (!newKey.isEmpty && !isDuplicateKey) : true
        let valueValid = valueValidationError == nil
        return keyValid && valueValid
    }

    var body: some View {
        NavigationStack {
            Form {
                if isAddingToObject {
                    Section {
                        TextField("Property name", text: $newKey)
                            .font(.system(size: 14, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } header: {
                        Text("Key")
                    } footer: {
                        if let error = keyValidationError {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Type") {
                    Picker(selection: $selectedType) {
                        ForEach(ValueType.allCases, id: \.self) { type in
                            Text(type.rawValue)
                                .tag(type)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .onChange(of: selectedType) { _, newType in
                        newValue = newType.defaultValue
                    }
                }

                Section {
                    if selectedType == .bool {
                        Picker("Value", selection: $newValue) {
                            Text("true").tag("true")
                            Text("false").tag("false")
                        }
                        .pickerStyle(.segmented)
                    } else if selectedType == .null {
                        Text("null")
                            .foregroundStyle(.secondary)
                    } else {
                        TextEditor(text: $newValue)
                            .font(.system(size: 14, design: .monospaced))
                            .frame(minHeight: 80)
                    }
                } header: {
                    Text("Value")
                } footer: {
                    if let error = valueValidationError {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isAddingToObject ? "Add Property" : "Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addItem()
                    }
                    .disabled(!canAdd)
                }
            }
            .onAppear {
                newValue = selectedType.defaultValue
            }
        }
        .presentationDetents([.medium])
    }

    private func addItem() {
        let value = convertValue()

        if isAddingToObject {
            if let updated = JsonParser.addToObject(jsonText, at: parentNode.path, key: newKey, value: value) {
                jsonText = updated
                onSave()
            }
        } else {
            if let updated = JsonParser.appendToArray(jsonText, at: parentNode.path, value: value) {
                jsonText = updated
                onSave()
            }
        }
        dismiss()
    }

    private func convertValue() -> Any {
        switch selectedType {
        case .string:
            return newValue
        case .number:
            return Double(newValue) ?? 0
        case .bool:
            return newValue == "true"
        case .null:
            return NSNull()
        case .object:
            if let data = newValue.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                return obj
            }
            return [String: Any]()
        case .array:
            if let data = newValue.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [Any]
            {
                return arr
            }
            return [Any]()
        }
    }
}

// MARK: - JsonValue Extension

extension JsonValue {
    var isObject: Bool {
        if case .object = self { return true }
        return false
    }

    var isArray: Bool {
        if case .array = self { return true }
        return false
    }
}

// MARK: - JSON Explorer View (Read-only tree, Chrome DevTools style)

struct JsonExplorerView: View {
    let jsonText: String

    var body: some View {
        if let data = jsonText.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data)
        {
            let rootNode = ExplorerNode.parse(json)
            ScrollView(.vertical, showsIndicators: true) {
                ExplorerNodeView(node: rootNode, depth: 0, isLast: true)
                    .padding(12)
            }
        }
    }
}

// MARK: - Explorer Node (Chrome DevTools style enum)

enum ExplorerNode: Identifiable {
    case null(key: String?)
    case bool(key: String?, value: Bool)
    case number(key: String?, value: Double)
    case string(key: String?, value: String)
    case array(key: String?, values: [ExplorerNode])
    case object(key: String?, pairs: [(String, ExplorerNode)])

    var id: String {
        switch self {
        case .null(let key): return "null-\(key ?? "root")-\(UUID().uuidString)"
        case .bool(let key, _): return "bool-\(key ?? "root")-\(UUID().uuidString)"
        case .number(let key, _): return "number-\(key ?? "root")-\(UUID().uuidString)"
        case .string(let key, _): return "string-\(key ?? "root")-\(UUID().uuidString)"
        case .array(let key, _): return "array-\(key ?? "root")-\(UUID().uuidString)"
        case .object(let key, _): return "object-\(key ?? "root")-\(UUID().uuidString)"
        }
    }

    var key: String? {
        switch self {
        case .null(let key), .bool(let key, _), .number(let key, _),
             .string(let key, _), .array(let key, _), .object(let key, _):
            return key
        }
    }

    var isExpandable: Bool {
        switch self {
        case .array, .object: return true
        default: return false
        }
    }

    var childCount: Int {
        switch self {
        case .array(_, let values): return values.count
        case .object(_, let pairs): return pairs.count
        default: return 0
        }
    }

    /// Convert node back to JSON-serializable value
    func toJsonValue() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(_, let value): return value
        case .number(_, let value): return value
        case .string(_, let value): return value
        case .array(_, let values): return values.map { $0.toJsonValue() }
        case .object(_, let pairs):
            var dict: [String: Any] = [:]
            for (key, node) in pairs {
                dict[key] = node.toJsonValue()
            }
            return dict
        }
    }

    /// Convert node to formatted JSON string
    func toJsonString() -> String? {
        let value = toJsonValue()
        guard let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
        ),
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    static func parse(_ json: Any, key: String? = nil) -> ExplorerNode {
        switch json {
        case is NSNull:
            return .null(key: key)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(key: key, value: number.boolValue)
            }
            return .number(key: key, value: number.doubleValue)
        case let string as String:
            return .string(key: key, value: string)
        case let array as [Any]:
            let nodes = array.enumerated().map { parse($1, key: "[\($0)]") }
            return .array(key: key, values: nodes)
        case let dict as [String: Any]:
            let pairs = dict.sorted { $0.key < $1.key }.map { ($0.key, parse($0.value, key: $0.key)) }
            return .object(key: key, pairs: pairs)
        default:
            return .string(key: key, value: String(describing: json))
        }
    }
}

// MARK: - Explorer Node View (Chrome DevTools style)

private struct ExplorerNodeView: View {
    let node: ExplorerNode
    let depth: Int
    let isLast: Bool
    @State private var isExpanded: Bool = false
    @State private var showCopiedFeedback: Bool = false

    // Chrome DevTools style colors
    private let primitiveColor = Color(red: 0.0, green: 0.45, blue: 0.73)  // Blue
    private let stringColor = Color(red: 0.77, green: 0.1, blue: 0.09)     // Red

    // Auto-expand first level
    init(node: ExplorerNode, depth: Int, isLast: Bool) {
        self.node = node
        self.depth = depth
        self.isLast = isLast
        self._isExpanded = State(initialValue: depth == 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Current node row
            HStack(spacing: 0) {
                // Expand/collapse chevron for expandable nodes
                if node.isExpandable {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.6))
                        .frame(width: 20, height: 20)
                } else {
                    Spacer().frame(width: 20)
                }

                // Key (if exists) - Chrome DevTools style: plain text
                if let key = node.key {
                    Text(key)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text(": ")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // Value or preview
                valueView

                Spacer(minLength: 28)
            }
            .frame(minHeight: 20)
            .contentShape(Rectangle())
            .onTapGesture {
                guard node.isExpandable else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }
            .overlay(alignment: .trailing) {
                // Copy button - fixed to right edge
                Button {
                    if let jsonString = node.toJsonString() {
                        UIPasteboard.general.string = jsonString
                        showCopiedFeedback = true
                    }
                } label: {
                    Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(showCopiedFeedback ? .green : .secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(showCopiedFeedback ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.2), value: showCopiedFeedback)
                .onChange(of: showCopiedFeedback) { _, newValue in
                    if newValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopiedFeedback = false
                        }
                    }
                }
            }

            // Children (if expanded)
            if isExpanded {
                childrenView
            }
        }
        .padding(.leading, CGFloat(depth) * 10)
    }

    @ViewBuilder
    private var valueView: some View {
        switch node {
        case .null:
            Text("null")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(primitiveColor)
        case .bool(_, let value):
            Text(value ? "true" : "false")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(primitiveColor)
        case .number(_, let value):
            Text(formatNumber(value))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(primitiveColor)
        case .string(_, let value):
            Text("\"\(value)\"")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(stringColor)
                .lineLimit(5)
        case .array(_, let values):
            Text("Array[\(values.count)]")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.5))
        case .object(_, let pairs):
            Text("Object{\(pairs.count)}")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.5))
        }
    }

    @ViewBuilder
    private var childrenView: some View {
        switch node {
        case .array(_, let values):
            ForEach(Array(values.enumerated()), id: \.offset) { index, childNode in
                ExplorerNodeView(
                    node: childNode,
                    depth: depth + 1,
                    isLast: index == values.count - 1
                )
            }
        case .object(_, let pairs):
            ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
                ExplorerNodeView(
                    node: pair.1,
                    depth: depth + 1,
                    isLast: index == pairs.count - 1
                )
            }
        default:
            EmptyView()
        }
    }

    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        return String(value)
    }
}
