//
//  ConsoleView+JSInput.swift
//  wina
//
//  JavaScript input field and execution for Console DevTools.
//

import SwiftUI

// MARK: - JavaScript Input

extension ConsoleView {
    // MARK: - JavaScript Input Field

    var jsInputField: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 8) {
                // Prompt symbol
                Text(">")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)

                // Input field
                TextField("JavaScript to execute...", text: $session.jsInput, axis: .vertical)
                    .font(.system(size: 13, design: .monospaced))
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit {
                        executeJavaScript()
                    }
                    .submitLabel(.send)

                // History navigation buttons (only when there's history)
                if !session.commandHistory.isEmpty {
                    HStack(spacing: 4) {
                        Button {
                            navigateHistory(direction: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .disabled(session.historyIndex >= session.commandHistory.count - 1)

                        Button {
                            navigateHistory(direction: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .disabled(session.historyIndex <= 0)
                    }
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }

                // Execute button
                Button {
                    executeJavaScript()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(session.jsInput.isEmpty ? Color.gray : Color.cyan, in: Circle())
                }
                .disabled(session.jsInput.isEmpty)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }

    // MARK: - JavaScript Execution

    /// Replace iOS smart quotes with straight quotes for valid JavaScript
    func sanitizeSmartQuotes(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\u{2018}", with: "'")  // '
            .replacingOccurrences(of: "\u{2019}", with: "'")  // '
            .replacingOccurrences(of: "\u{201C}", with: "\"") // "
            .replacingOccurrences(of: "\u{201D}", with: "\"") // "
    }

    func executeJavaScript() {
        let rawCommand = session.jsInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = sanitizeSmartQuotes(rawCommand)
        guard !command.isEmpty, let nav = navigator else { return }

        // Add to history (with max limit)
        if session.commandHistory.last != command {
            session.commandHistory.append(command)
            if session.commandHistory.count > maxCommandHistory {
                session.commandHistory.removeFirst()
            }
        }
        session.historyIndex = -1

        // Log the command
        consoleManager.addLog(type: "command", message: command, source: "user input")

        // Clear input
        session.jsInput = ""

        // Execute and log result
        Task {
            let result = await nav.evaluateJavaScript(command)
            await MainActor.run {
                let resultText: String
                if let result {
                    resultText = formatJSResult(result)
                } else {
                    resultText = "undefined"
                }
                consoleManager.addLog(type: "result", message: resultText, source: nil)
            }
        }
    }

    func formatJSResult(_ result: Any) -> String {
        switch result {
        case let string as String:
            return "\"\(string)\""
        case let number as NSNumber:
            // Check if it's a boolean
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case let array as [Any]:
            let items = array.map { formatJSResult($0) }.joined(separator: ", ")
            return "[\(items)]"
        case let dict as [String: Any]:
            if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return String(describing: dict)
        default:
            return String(describing: result)
        }
    }

    func navigateHistory(direction: Int) {
        let newIndex = session.historyIndex - direction
        if newIndex >= 0 && newIndex < session.commandHistory.count {
            session.historyIndex = newIndex
            session.jsInput = session.commandHistory[session.commandHistory.count - 1 - session.historyIndex]
        } else if newIndex < 0 {
            session.historyIndex = -1
            session.jsInput = ""
        }
    }
}
