import Darwin
import Foundation
import Network
import XCTest
@testable import WalnutAgent

final class WalnutAgentTests: XCTestCase {
    func testPairingRoundTripAndPrivatePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("pairing.json")
        let expected = Pairing(version: 1, serviceName: "Walnut-Test", port: 44_333, key: Data(repeating: 13, count: 32))
        let encoded = try JSONEncoder().encode(expected).base64EncodedString()
        let token = "walnut-agent:" + encoded
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let pairing = try Pairing.fromToken(token)
        XCTAssertEqual(pairing, expected)
        try pairing.save(to: file)
        XCTAssertEqual(try Pairing.load(from: file), pairing)
        XCTAssertEqual(chmod(file.path, 0o644), 0)
        XCTAssertThrowsError(try Pairing.load(from: file))
        XCTAssertThrowsError(try Pairing.fromToken("walnut-agent:invalid"))
    }

    func testBridgeValidation() throws {
        let request = try DeviceBridge.request(id: "test", tool: "walnut_capabilities", arguments: ["key": "value\nline"])
        XCTAssertEqual(request.filter { $0 == 0x0A }.count, 1)
        XCTAssertEqual(request.last, 0x0A)
        XCTAssertThrowsError(try DeviceBridge.request(id: "test", tool: "walnut_capabilities", arguments: [
            "oversized": String(repeating: "x", count: 256 * 1024)
        ]))
        XCTAssertTrue(try DeviceBridge.result(Data(#"{"id":"test","result":null}"#.utf8), for: "test") is NSNull)
        XCTAssertThrowsError(try DeviceBridge.result(Data(#"{"id":"different","result":null}"#.utf8), for: "test"))
        XCTAssertThrowsError(try DeviceBridge.result(Data(#"{"id":"test","result":null,"error":"failed"}"#.utf8), for: "test"))
    }

    func testMCPDispatchAndScreenshotContent() async throws {
        let server = MCPServer { name, arguments in
            switch name {
            case "walnut_capabilities":
                let tool = ["name": "walnut_screenshot", "inputSchema": ["type": "object"]] as [String: Any]
                return ["data": ["tools": [tool]]]
            case "walnut_screenshot":
                XCTAssertEqual(arguments["scale"] as? Int, 2)
                return ["runId": "run", "data": ["mimeType": "image/png", "data": "aW1hZ2U=", "savedToPhotos": true]]
            default: throw AgentError("Tool unavailable")
            }
        }
        let handshake = await server.respond(to: Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#.utf8))
        XCTAssertEqual((handshake?["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-06-18")
        let notification = await server.respond(to: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8))
        XCTAssertNil(notification)
        let catalog = await server.respond(to: Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#.utf8))
        let tools = (catalog?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.first?["name"] as? String, "walnut_screenshot")
        let capture = await server.respond(to: Data(#"{"jsonrpc":"2.0","id":"img","method":"tools/call","params":{"name":"walnut_screenshot","arguments":{"scale":2}}}"#.utf8))
        let result = try XCTUnwrap(capture?["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: String]])
        XCTAssertEqual(content.first?["type"], "image")
        XCTAssertEqual(content.first?["data"], "aW1hZ2U=")
        let structured = try XCTUnwrap(result["structuredContent"] as? [String: Any])
        XCTAssertEqual(structured["runId"] as? String, "run")
        XCTAssertNil((structured["data"] as? [String: Any])?["data"])
        XCTAssertEqual((structured["data"] as? [String: Any])?["savedToPhotos"] as? Bool, true)
        let error = await server.respond(to: Data(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"walnut_unavailable"}}"#.utf8))
        XCTAssertEqual((error?["result"] as? [String: Any])?["isError"] as? Bool, true)
    }

    func testMCPForwardsAdvertisedConsoleTool() async throws {
        let server = MCPServer { name, arguments in
            if name == "walnut_capabilities" {
                let tool = ["name": "console_list", "inputSchema": ["type": "object"]] as [String: Any]
                return ["data": ["tools": [tool]]]
            }
            XCTAssertEqual(name, "console_list")
            XCTAssertEqual(arguments["limit"] as? Int, 3)
            return ["data": ["total": 7]]
        }
        let catalog = await server.respond(to: Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8))
        let tools = (catalog?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.first?["name"] as? String, "console_list")
        let reply = await server.respond(to: Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"console_list","arguments":{"limit":3}}}"#.utf8))
        let result = try XCTUnwrap(reply?["result"] as? [String: Any])
        let structured = try XCTUnwrap(result["structuredContent"] as? [String: Any])
        XCTAssertEqual((structured["data"] as? [String: Int])?["total"], 7)
    }

    func testMCPRejectsNonUTF8Requests() async throws {
        let server = MCPServer { _, _ in throw AgentError("Unexpected device call") }
        let ping = #"{"jsonrpc":"2.0","id":7,"method":"ping"}"#
        let malformed = Data(#"{"jsonrpc":"2.0","id":7,"method":"ping","value":""#.utf8)
            + Data([0xff]) + Data("\"}".utf8)
        for input in [malformed, try XCTUnwrap(ping.data(using: .utf16LittleEndian))] {
            let response = await server.respond(to: input)
            XCTAssertTrue(response?["id"] is NSNull)
            XCTAssertEqual((response?["error"] as? [String: Any])?["code"] as? Int, -32700)
        }
        let response = await server.respond(to: Data(ping.utf8))
        XCTAssertEqual(response?["id"] as? Int, 7)
        XCTAssertNotNil(response?["result"])
    }

    func testTLSRejectsWrongKeyAndKeepsOneConnectionForTwoCalls() async throws {
        let key = Data(repeating: 42, count: 32)
        let queue = DispatchQueue(label: "walnut-agent.tests")
        let parameters = DeviceBridge.parameters(key: key)
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        defer { listener.cancel() }
        let ready = expectation(description: "TLS listener ready")
        let peerClosed = expectation(description: "Peer received the graceful close frame")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            Self.respond(on: connection, count: 1, buffered: Data(), peerClosed: peerClosed)
        }
        listener.start(queue: queue)
        await fulfillment(of: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port)
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
        let payload = try DeviceBridge.request(id: "test", tool: "walnut_capabilities", arguments: [:])

        let rejected = BridgeExchange(to: endpoint, using: DeviceBridge.parameters(key: Data(repeating: 43, count: 32)))
        do {
            _ = try await rejected.run(payload, timeout: 3)
            XCTFail("TLS accepted the wrong pairing key")
        } catch {
            XCTAssertTrue(error is NWError)
        }

        let exchange = BridgeExchange(to: endpoint, using: DeviceBridge.parameters(key: key))
        let first = try await exchange.run(payload, timeout: 3)
        let second = try await exchange.run(payload, timeout: 3)
        XCTAssertEqual(try DeviceBridge.result(first, for: "test") as? Int, 1)
        XCTAssertEqual(try DeviceBridge.result(second, for: "test") as? Int, 2)
        await exchange.close()
        await fulfillment(of: [peerClosed], timeout: 3)

        do {
            _ = try await exchange.run(payload, timeout: 3, reportsBeforeSend: true)
            XCTFail("A closed cached connection should be safe to replace")
        } catch {
            XCTAssertTrue(error is BridgeExchange.BeforeSendError)
        }
    }

    func testDisconnectAfterCommandStartsCannotBeRetriedAutomatically() async throws {
        let queue = DispatchQueue(label: "walnut-agent.test.disconnect-after-command")
        let listener = try NWListener(using: .tcp)
        defer { listener.cancel() }
        let ready = expectation(description: "TCP listener ready")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                XCTAssertNotNil(data)
                connection.cancel()
            }
        }
        listener.start(queue: queue)
        await fulfillment(of: [ready], timeout: 5)
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: try XCTUnwrap(listener.port))
        let exchange = BridgeExchange(to: endpoint, using: .tcp)
        do {
            _ = try await exchange.run(Data("request\n".utf8), timeout: 3, reportsBeforeSend: true)
            XCTFail("The peer did not send a reply")
        } catch {
            XCTAssertFalse(error is BridgeExchange.BeforeSendError)
        }
    }

    private static func respond(on connection: NWConnection, count: Int, buffered: Data, peerClosed: XCTestExpectation) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, complete, error in
            if complete || error != nil {
                connection.cancel()
                return
            }
            let input = buffered + (data ?? Data())
            guard let newline = input.firstIndex(of: 0x0A) else {
                respond(on: connection, count: count, buffered: input, peerClosed: peerClosed)
                return
            }
            if newline == input.startIndex {
                if count == 3 { peerClosed.fulfill() }
                connection.cancel()
                return
            }
            let response = Data("{\"id\":\"test\",\"result\":\(count)}".utf8)
            connection.send(content: response, completion: .contentProcessed { error in
                if error != nil { connection.cancel(); return }
                connection.send(content: Data([0x0A]), completion: .contentProcessed { error in
                    if error != nil { connection.cancel(); return }
                    respond(on: connection, count: count + 1, buffered: Data(), peerClosed: peerClosed)
                })
            })
        }
    }
}
