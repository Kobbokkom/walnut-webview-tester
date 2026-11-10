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
        read: () -> String? = { readLine() },
        write: (Data) throws -> Void = { try FileHandle.standardOutput.write(contentsOf: $0) }
    ) async throws -> Bool {
        var succeeded = true
        while let line = read() {
            let response: [String: Any]
            do {
                response = ["ok": true, "result": try await perform(line)]
            } catch {
                succeeded = false
                response = ["ok": false, "error": error.localizedDescription]
            }
            var bytes = try JSONSerialization.data(withJSONObject: response, options: .withoutEscapingSlashes)
            bytes.append(0x0A)
            try write(bytes)
        }
        return succeeded
    }

    private func perform(_ line: String) async throws -> Any {
        guard line.utf8.count <= DeviceBridge.requestLimit else {
            throw AgentError("The session request exceeds 256 KiB.")
        }
        guard let request = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            throw AgentError("Send one JSON object per line.")
        }
        switch request["op"] as? String {
        case "tools" where request.count == 1:
            guard var result = try await call("walnut_capabilities", [:]) as? [String: Any],
                  var data = result["data"] as? [String: Any], let tools = data["tools"] as? [[String: Any]] else {
                throw AgentError("Walnut returned an invalid tool catalog.")
            }
            data["tools"] = tools.map(RecordingDownload.toolDefinition)
            result["data"] = data
            return result
        case "call" where request.keys.allSatisfy({ ["op", "name", "arguments"].contains($0) }):
            guard let name = request["name"] as? String, !name.isEmpty, name.utf8.count <= 128 else {
                throw AgentError("Invalid Walnut tool name.")
            }
            guard let arguments = (request["arguments"] ?? [:]) as? [String: Any] else {
                throw AgentError("Tool arguments must be a JSON object.")
            }
            if name == "walnut_recording", arguments["action"] as? String == "read" {
                return try await RecordingDownload.save(using: call, arguments: arguments, to: recordingDirectory)
            }
            let result = try await call(name, arguments)
            return name == "walnut_screenshot" ? try saveScreenshot(result) : result
        default:
            throw AgentError("Expected op tools, or op call with name and optional arguments.")
        }
    }

    private func saveScreenshot(_ result: Any) throws -> [String: Any] {
        guard var envelope = result as? [String: Any], var image = envelope["data"] as? [String: Any],
              image["mimeType"] as? String == "image/png", let base64 = image.removeValue(forKey: "data") as? String,
              let bytes = Data(base64Encoded: base64), bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
            throw AgentError("Walnut returned an invalid screenshot.")
        }
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
        image["path"] = output.path
        envelope["data"] = image
        return envelope
    }
}
