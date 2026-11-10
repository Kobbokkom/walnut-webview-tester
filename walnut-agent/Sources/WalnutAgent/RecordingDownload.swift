import Darwin
import Foundation

enum RecordingDownload {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Walnut Agent/Recordings")
    }

    static func save(
        using call: AgentToolCall,
        arguments: [String: Any],
        to directory: URL
    ) async throws -> [String: Any] {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let output = directory.appendingPathComponent("Walnut-\(UUID().uuidString).mov")
        let staging = directory.appendingPathComponent(".\(output.lastPathComponent).partial")
        let descriptor = open(staging.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw AgentError("Could not create a private recording file on the Mac.") }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var saved = false
        defer {
            if !saved {
                try? file.close()
                try? FileManager.default.removeItem(at: staging)
            }
        }

        var params = arguments
        var offset = 0
        var recordingID: String?
        var expectedSize: Int?
        while true {
            params["offset"] = offset
            let response = try await call("walnut_recording", params)
            try Task.checkCancellation()
            guard var envelope = response as? [String: Any], let chunk = envelope["data"] as? [String: Any],
                  chunk["mimeType"] as? String == "video/quicktime", let id = chunk["recordingId"] as? String, !id.isEmpty,
                  let size = chunk["size"] as? Int, (1...512 * 1024 * 1024).contains(size),
                  (recordingID ?? id) == id, (expectedSize ?? size) == size,
                  chunk["offset"] as? Int == offset, let next = chunk["nextOffset"] as? Int,
                  next > offset, next <= size, next - offset <= 512 * 1024,
                  let base64 = chunk["data"] as? String, base64.utf8.count == ((next - offset + 2) / 3) * 4,
                  let bytes = Data(base64Encoded: base64),
                  bytes.count == next - offset, chunk["done"] as? Bool == (next == size) else {
                throw AgentError("Walnut returned an invalid recording chunk or the recording changed during transfer.")
            }
            try file.write(contentsOf: bytes)
            if next == size {
                try file.close()
                guard renamex_np(staging.path, output.path, UInt32(RENAME_EXCL)) == 0 else {
                    throw AgentError("Could not finish saving the recording on the Mac.")
                }
                saved = true
                envelope["data"] = ["mimeType": "video/quicktime", "path": output.path, "size": size]
                return envelope
            }
            recordingID = id
            expectedSize = size
            offset = next
        }
    }

    static func toolDefinition(_ tool: [String: Any]) -> [String: Any] {
        guard tool["name"] as? String == "walnut_recording", var schema = tool["inputSchema"] as? [String: Any],
              var properties = schema["properties"] as? [String: Any] else { return tool }
        properties.removeValue(forKey: "offset")
        schema["properties"] = properties
        var definition = tool
        definition["inputSchema"] = schema
        definition["description"] = "Start or stop an approved screen recording, query status, or save a completed recording to a private .mov file on the Mac with action read."
        return definition
    }
}
