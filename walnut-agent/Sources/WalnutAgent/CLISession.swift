import Darwin
import Foundation

struct CLISession {
    let screenshotDirectory: URL
    let recordingDirectory: URL
    let call: AgentToolCall

    init(
        screenshotDirectory: URL = RecordingDownload.directory.deletingLastPathComponent().appendingPathComponent("Screenshots"),
        recordingDirectory: URL = RecordingDownload.directory,
        call: @escaping AgentToolCall
    ) {
        self.screenshotDirectory = screenshotDirectory
        self.recordingDirectory = recordingDirectory
        self.call = call
    }

    func run(
        read: () throws -> Result<Data, AgentError>? = CLILineReader().next,
        write: (Data) throws -> Void = { try FileHandle.standardOutput.write(contentsOf: $0) }
    ) async throws -> Bool {
        var succeeded = true
        while let frame = try read() {
            var response: [String: Any]
            do {
                response = ["ok": true, "result": try await perform(frame.get())]
            } catch {
                succeeded = false
                response = ["ok": false, "error": error.localizedDescription]
                if let screenshotError = error as? ScreenshotOutputError {
                    response["result"] = screenshotError.result
                }
            }
            var bytes = try JSONSerialization.data(withJSONObject: response, options: .withoutEscapingSlashes)
            bytes.append(0x0A)
            try write(bytes)
        }
        return succeeded
    }

    private func perform(_ line: Data) async throws -> Any {
        guard String(data: line, encoding: .utf8) != nil else {
            throw AgentError("Session requests must use UTF-8.")
        }
        guard !line.contains(0), let request = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw AgentError("Send one JSON object per line.")
        }
        let name: String
        let arguments: [String: Any]
        switch request["op"] as? String {
        case "tools" where request.count == 1:
            name = "walnut_capabilities"
            arguments = [:]
        case "call" where request.keys.allSatisfy({ ["op", "name", "arguments"].contains($0) }):
            guard let requestedName = request["name"] as? String, !requestedName.isEmpty,
                  requestedName.utf8.count <= 128 else {
                throw AgentError("Invalid Walnut tool name.")
            }
            guard let requestedArguments = (request["arguments"] ?? [:]) as? [String: Any] else {
                throw AgentError("Tool arguments must be a JSON object.")
            }
            name = requestedName
            arguments = requestedArguments
        default:
            throw AgentError("Expected op tools, or op call with name and optional arguments.")
        }
        if name == "walnut_recording", arguments["action"] as? String == "read" {
            guard arguments["offset"] == nil else {
                throw AgentError("Omit offset to download the full recording.")
            }
            return try await RecordingDownload.save(using: call, arguments: arguments, to: recordingDirectory)
        }
        let result = try await call(name, arguments)
        switch name {
        case "walnut_capabilities":
            guard var envelope = result as? [String: Any], var data = envelope["data"] as? [String: Any],
                  let tools = data["tools"] as? [[String: Any]] else {
                throw AgentError("Walnut returned an invalid tool catalog.")
            }
            data["tools"] = tools.map(RecordingDownload.toolDefinition)
            envelope["data"] = data
            return envelope
        case "walnut_screenshot": return try saveScreenshot(result)
        default: return result
        }
    }

    private func saveScreenshot(_ result: Any) throws -> [String: Any] {
        guard var envelope = result as? [String: Any], var image = envelope["data"] as? [String: Any] else {
            throw AgentError("Walnut returned an invalid screenshot.")
        }
        let base64 = image.removeValue(forKey: "data") as? String
        image["path"] = nil
        do {
            guard image["mimeType"] as? String == "image/png", let base64, let bytes = Data(base64Encoded: base64),
                  bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
                throw AgentError("Walnut returned an invalid screenshot.")
            }
            image["path"] = try writeScreenshot(bytes).path
        } catch {
            envelope["data"] = image
            throw ScreenshotOutputError(result: envelope, cause: error)
        }
        envelope["data"] = image
        return envelope
    }

    private func writeScreenshot(_ bytes: Data) throws -> URL {
        try FileManager.default.createDirectory(
            at: screenshotDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let output = screenshotDirectory.appendingPathComponent("Walnut-\(UUID().uuidString).png")
        let descriptor = open(output.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw AgentError("Could not create a private screenshot file on the Mac.") }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try file.write(contentsOf: bytes)
            try file.close()
        } catch {
            try? file.close()
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        return output
    }
}

private struct ScreenshotOutputError: LocalizedError {
    let result: [String: Any]
    let cause: Error

    var errorDescription: String? { "Could not save the screenshot on the Mac. \(cause.localizedDescription)" }
}
