//
//  StorageSheets.swift
//  wina
//
//  Storage edit and add sheets for StorageView.
//

import SwiftUI

// MARK: - Storage Edit Sheet

struct StorageEditSheet: View {
    let item: StorageItem
    let storageManager: StorageManager
    let onSave: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editedKey: String = ""
    @State private var editedValue: String = ""
    @State private var isSaving: Bool = false
    @State private var isDeleting: Bool = false
    @State private var showJsonEditor: Bool = false
    @State private var feedbackState = CopiedFeedbackState()
    @State private var isURLDecoded: Bool = true

    private var isValueJson: Bool {
        JsonParser.isValidJson(editedValue)
    }

    private var isCookie: Bool {
        item.storageType == .cookies
    }

    private var keyChanged: Bool {
        editedKey != item.key
    }

    private var hasChanges: Bool {
        editedKey != item.key || editedValue != item.value
    }

    private var isDuplicateKey: Bool {
        guard keyChanged else { return false }
        if item.storageType == .cookies {
            // Cookie keys can duplicate across domains/paths.
            guard let metadata = item.cookieMetadata else { return false }
            let existingKeys = storageManager.items
                .filter {
                    $0.storageType == .cookies
                        && $0.key != item.key
                        && $0.cookieMetadata?.domain == metadata.domain
                        && $0.cookieMetadata?.path == metadata.path
                }
                .map(\.key)
            return existingKeys.contains(editedKey)
        }
        let existingKeys = storageManager.items
            .filter { $0.storageType == item.storageType && $0.key != item.key }
            .map(\.key)
        return existingKeys.contains(editedKey)
    }

    private var valueType: StorageValueType {
        StorageValueType.detect(from: editedValue)
    }

    private var formattedSize: String {
        let bytes = editedValue.utf8.count
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Info section (Storage + Type + Size + Domain)
                Section("Info") {
                    LabeledContent("Storage") {
                        HStack(spacing: 4) {
                            Image(systemName: item.storageType.icon)
                                .font(.system(size: 12))
                            Text(item.storageType.label)
                        }
                        .foregroundStyle(item.storageType.tintColor)
                    }
                    if isCookie, let domain = item.cookieMetadata?.domain {
                        LabeledContent("Domain", value: domain)
                    }
                    HStack {
                        Text("Type")
                        Spacer()
                        if let badge = valueType.badge {
                            badge
                        } else {
                            Text(valueType.label)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Size")
                        Spacer()
                        Text(formattedSize)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                // Cookie metadata section
                if let metadata = item.cookieMetadata {
                    Section("Cookie Attributes") {
                        LabeledContent("Path", value: metadata.path)

                        if let expires = metadata.expiresDate {
                            LabeledContent("Expires") {
                                HStack(spacing: 4) {
                                    Text(expires, style: .date)
                                    Text(expires, style: .time)
                                }
                                .foregroundStyle(.secondary)
                            }
                        } else {
                            LabeledContent("Expires", value: "Session")
                        }

                        if let sameSite = metadata.sameSitePolicy {
                            LabeledContent("SameSite", value: sameSite)
                        }

                        HStack {
                            if metadata.isSecure {
                                TypeBadge(text: "Secure", color: .green, icon: "lock.fill")
                            }
                            if metadata.isHTTPOnly {
                                TypeBadge(text: "HttpOnly", color: .orange, icon: "server.rack")
                            }
                        }
                    }
                }

                Section {
                    TextField("Key", text: $editedKey)
                        .font(.system(size: 14, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    HStack {
                        Text("Key")
                        Spacer()
                        CopyIconButton(text: editedKey) {
                            feedbackState.showCopied("Key")
                        }
                    }
                } footer: {
                    if isDuplicateKey {
                        Text("Key '\(editedKey)' already exists")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    TextEditor(text: $editedValue)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 120, maxHeight: 200)
                        .scrollIndicators(.visible)

                    if isCookie {
                        HStack(spacing: 8) {
                            Picker("URL Encoding", selection: $isURLDecoded) {
                                Text(verbatim: "Encoded").tag(false)
                                Text(verbatim: "Decoded").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: isURLDecoded) { oldValue, newValue in
                                if newValue && !oldValue {
                                    // Switching to decoded view
                                    if let decoded = editedValue.removingPercentEncoding {
                                        editedValue = decoded
                                    }
                                } else if !newValue && oldValue {
                                    // Switching to encoded view
                                    if let encoded = editedValue.addingPercentEncoding(
                                        withAllowedCharacters: .urlQueryAllowed
                                    ) {
                                        editedValue = encoded
                                    }
                                }
                            }

                            InfoPopoverButton(
                                text: "Values are automatically URL-encoded when saved."
                            )
                        }
                    }
                } header: {
                    HStack {
                        Text("Value")
                        Spacer()
                        CopyIconButton(text: editedValue) {
                            feedbackState.showCopied("Value")
                        }
                        if !editedValue.isEmpty {
                            HeaderActionButton(label: "Clear", icon: "xmark") {
                                editedValue = ""
                            }
                        }
                        if isValueJson {
                            HeaderActionButton(label: "Edit", icon: "pencil") {
                                showJsonEditor = true
                            }
                        }
                    }
                }

                // JSON Explorer section (only for valid JSON)
                if isValueJson {
                    Section {
                        JsonExplorerView(jsonText: editedValue)
                            .frame(minHeight: 200)
                            .listRowInsets(EdgeInsets())
                    } header: {
                        HStack {
                            Text(verbatim: "JSON Explorer")
                            Spacer()
                            Text("\(JsonParser.countElements(editedValue)) items")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if let error = storageManager.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        if isDeleting {
                            ProgressView()
                        } else {
                            GlassActionButton("Delete", icon: "trash", style: .destructive) {
                                deleteItem()
                            }
                        }
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle(Text(verbatim: "Edit Item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveItem()
                    }
                    .disabled(isSaving || !hasChanges || editedKey.isEmpty || isDuplicateKey)
                }
            }
            .sheet(isPresented: $showJsonEditor) {
                JsonEditorSheet(jsonText: $editedValue)
            }
            .onAppear {
                editedKey = item.key
                // Default to decoded view for cookies
                if isCookie, let decoded = item.value.removingPercentEncoding {
                    editedValue = decoded
                } else {
                    editedValue = item.value
                }
            }
            .copiedFeedbackOverlay($feedbackState.message)
        }
    }
    private func saveItem() {
        isSaving = true
        Task {
            // If viewing decoded, re-encode before saving
            var finalValue = editedValue
            if isURLDecoded, isCookie {
                finalValue = editedValue.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryAllowed
                ) ?? editedValue
            }

            // Minify JSON before saving (storage typically stores compact JSON)
            let valueToSave = JsonParser.minify(finalValue) ?? finalValue

            let success = await storageManager.updateItem(item, key: editedKey, value: valueToSave)

            if success {
                onSave()
                dismiss()
            }
            isSaving = false
        }
    }

    private func deleteItem() {
        isDeleting = true
        Task {
            if await storageManager.removeItem(item) {
                onDelete()
                dismiss()
            }
            isDeleting = false
        }
    }
}

// MARK: - Storage Add Sheet

struct StorageAddSheet: View {
    let storageManager: StorageManager
    let storageType: StorageItem.StorageType
    let pageURL: URL
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var key: String = ""
    @State private var value: String = ""
    @State private var isSaving: Bool = false
    @State private var showJsonEditor: Bool = false
    @State private var didSave: Bool = false
    @State private var showSaveFailure = false

    private var isValueJson: Bool {
        JsonParser.isValidJson(value)
    }

    private var isDuplicateKey: Bool {
        // Skip duplicate check after successful save (items already updated)
        guard !didSave else { return false }
        if storageType == .cookies {
            return false
        }
        let existingKeys = storageManager.items
            .filter { $0.storageType == storageType }
            .map(\.key)
        return existingKeys.contains(key)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Enter key", text: $key)
                        .font(.system(size: 14, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Key")
                } footer: {
                    if isDuplicateKey {
                        Text("Key '\(key)' already exists")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    TextEditor(text: $value)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 100)
                } header: {
                    HStack {
                        Text("Value")
                        Spacer()
                        if isValueJson {
                            HeaderActionButton(label: "Edit", icon: "pencil") {
                                showJsonEditor = true
                            }
                        }
                    }
                }

                // JSON Explorer section (only for valid JSON)
                if isValueJson {
                    Section {
                        JsonExplorerView(jsonText: value)
                            .frame(minHeight: 160)
                            .listRowInsets(EdgeInsets())
                    } header: {
                        HStack {
                            Text(verbatim: "JSON Explorer")
                            Spacer()
                            Text("\(JsonParser.countElements(value)) items")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Add to \(storageType.label)"))
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
                    .disabled(isSaving || key.isEmpty || isDuplicateKey)
                }
            }
            .sheet(isPresented: $showJsonEditor) {
                JsonEditorSheet(jsonText: $value)
            }
            .alert("Could not add item", isPresented: $showSaveFailure) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check the current page, key and available storage, then try again.")
            }
        }
    }

    private func addItem() {
        isSaving = true
        Task {
            // Minify JSON before saving (storage typically stores compact JSON)
            let valueToSave = JsonParser.minify(value) ?? value
            if await storageManager.addItem(key: key, value: valueToSave, type: storageType, pageURL: pageURL) {
                didSave = true
                onSave()
                dismiss()
            } else {
                showSaveFailure = true
            }
            isSaving = false
        }
    }
}
