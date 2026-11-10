import Foundation

struct MCPServer: Sendable {
    let recordingDirectory: URL
    let call: AgentToolCall

    init(recordingDirectory: URL = RecordingDownload.directory, call: @escaping AgentToolCall) {
        self.recordingDirectory = recordingDirectory
        self.call = call
    }

    func run() async throws {
        let input = AsyncStream<Data> { continuation in
            DispatchQueue(label: "walnut-agent.stdin").async {
                while let line = readLine() {
                    if case .terminated = continuation.yield(Data(line.utf8)) { break }
                }
                continuation.finish()
            }
        }
        try await run(input: input) { try FileHandle.standardOutput.write(contentsOf: $0) }
    }

    func run(input: AsyncStream<Data>, write: @escaping @Sendable (Data) throws -> Void) async throws {
        let queue = MCPRequestQueue { data in
            guard let response = await respond(to: data), !Task.isCancelled else { return }
            var payload = try JSONSerialization.data(withJSONObject: response, options: [.withoutEscapingSlashes])
            payload.append(0x0A)
            if !Task.isCancelled { try write(payload) }
        }
        for await data in input { await queue.receive(data) }
        try await queue.finish()
    }

    func respond(to data: Data) async -> [String: Any]? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else {
            return error(id: NSNull(), code: -32700, message: "Parse error")
        }
        guard let request = object as? [String: Any], request["jsonrpc"] as? String == "2.0",
              let method = request["method"] as? String else {
            return error(id: NSNull(), code: -32600, message: "Invalid Request")
        }
        guard let id = request["id"] else { return nil }
        guard MCPRequestID(id) != nil else {
            return error(id: NSNull(), code: -32600, message: "Invalid Request ID")
        }
        let params = request["params"] as? [String: Any]
        switch method {
        case "initialize":
            guard let requestedVersion = params?["protocolVersion"] as? String else {
                return error(id: id, code: -32602, message: "Invalid initialize parameters")
            }
            let version = requestedVersion == "2025-06-18" ? requestedVersion : "2025-11-25"
            return success(id: id, result: [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "walnut-agent", "version": CLI.version]
            ])
        case "ping":
            return success(id: id, result: [:])
        case "tools/list":
            do {
                let envelope = try await call("walnut_capabilities", [:]) as? [String: Any]
                let details = envelope?["data"] as? [String: Any]
                guard let tools = details?["tools"] as? [[String: Any]] else {
                    throw AgentError("Walnut returned an invalid tool catalog.")
                }
                return success(id: id, result: ["tools": tools.map(RecordingDownload.toolDefinition)])
            } catch {
                return self.error(id: id, code: -32000, message: error.localizedDescription)
            }
        case "tools/call":
            guard let name = params?["name"] as? String, !name.isEmpty, name.utf8.count <= 128 else {
                return error(id: id, code: -32602, message: "Invalid Walnut tool name")
            }
            let arguments = params?["arguments"] ?? [:] as [String: Any]
            guard let arguments = arguments as? [String: Any] else {
                return error(id: id, code: -32602, message: "Tool arguments must be a JSON object")
            }
            do {
                let result: Any
                if name == "walnut_recording", arguments["action"] as? String == "read" {
                    result = try await RecordingDownload.save(using: call, arguments: arguments, to: recordingDirectory)
                } else {
                    result = try await call(name, arguments)
                }
                return success(id: id, result: try toolResult(result, name: name))
            } catch {
                return success(id: id, result: ["isError": true, "content": [text(error.localizedDescription)]])
            }
        default:
            return error(id: id, code: -32601, message: "Method not found")
        }
    }

    private func toolResult(_ result: Any, name: String) throws -> [String: Any] {
        if name == "walnut_screenshot", var envelope = result as? [String: Any],
           var image = envelope["data"] as? [String: Any], image["mimeType"] as? String == "image/png",
           let base64 = image["data"] as? String {
            image.removeValue(forKey: "data")
            envelope["data"] = image
            return ["content": [
                ["type": "image", "mimeType": "image/png", "data": base64],
                text(try jsonText(envelope))
            ], "structuredContent": envelope]
        }
        var response: [String: Any] = ["content": [text(try jsonText(result))]]
        if let object = result as? [String: Any] { response["structuredContent"] = object }
        return response
    }

    private func jsonText(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    private func text(_ value: String) -> [String: String] {
        ["type": "text", "text": value]
    }

    private func success(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func error(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }
}
