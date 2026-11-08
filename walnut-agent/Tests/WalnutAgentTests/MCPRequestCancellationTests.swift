import Foundation
import Network
import XCTest
@testable import WalnutAgent

final class MCPRequestCancellationTests: XCTestCase {
    func testCancellationClosesActiveTLSConnectionAndKeepsNextCall() async throws {
        let key = Data(repeating: 7, count: 32)
        let parameters = DeviceBridge.parameters(key: key)
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        defer { listener.cancel() }
        let networkQueue = DispatchQueue(label: "walnut-agent.cancellation-test")
        let ready = expectation(description: "TLS listener ready")
        let started = expectation(description: "TLS request arrived")
        let disconnected = expectation(description: "Phone peer received disconnect")
        let replied = expectation(description: "Next MCP call responded")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: networkQueue)
            Self.watch(connection, started: started, disconnected: disconnected)
        }
        listener.start(queue: networkQueue)
        await fulfillment(of: [ready], timeout: 3)

        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: try XCTUnwrap(listener.port))
        let exchange = BridgeExchange(to: endpoint, using: DeviceBridge.parameters(key: key))
        let server = MCPServer { name, _ in
            if name == "settings_apply" {
                let payload = try DeviceBridge.request(id: "active", tool: name, arguments: [:])
                do {
                    _ = try await exchange.run(payload, timeout: 5)
                    XCTFail("Canceled call completed successfully")
                } catch {
                    XCTAssertTrue(error is CancellationError)
                    throw error
                }
            }
            return ["tool": name]
        }
        let input = AsyncStream<Data>.makeStream()
        let output = AsyncStream<Data>.makeStream()
        let run = Task {
            defer { output.continuation.finish() }
            try await server.run(input: input.stream) { data in
                output.continuation.yield(data)
                replied.fulfill()
            }
        }
        input.continuation.yield(Data(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"settings_apply"}}"#.utf8))
        await fulfillment(of: [started], timeout: 3)
        input.continuation.yield(Data(#"{"jsonrpc":"2.0","id":"9","method":"tools/call","params":{"name":"console_list"}}"#.utf8))
        input.continuation.yield(Data(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":9}}"#.utf8))
        await fulfillment(of: [disconnected, replied], timeout: 3)
        input.continuation.finish()
        try await run.value

        var replies: [[String: Any]] = []
        for await data in output.stream {
            replies.append(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]))
        }
        XCTAssertEqual(replies.count, 1)
        XCTAssertEqual(replies.first?["id"] as? String, "9")
        let result = replies.first?["result"] as? [String: Any]
        XCTAssertEqual((result?["structuredContent"] as? [String: String])?["tool"], "console_list")
    }

    func testEOFCancelsActiveAndQueuedToolCallsAndFlushesPing() async throws {
        let started = expectation(description: "First tool started")
        let cancelled = expectation(description: "First tool cancelled on EOF")
        let server = MCPServer { name, _ in
            guard name == "settings_apply" else {
                XCTFail("Queued tool started after EOF")
                return ["tool": name]
            }
            started.fulfill()
            do {
                try await Task.sleep(for: .seconds(3))
                XCTFail("Active tool was allowed to complete after EOF")
                return ["tool": name]
            } catch {
                XCTAssertTrue(error is CancellationError)
                cancelled.fulfill()
                throw error
            }
        }
        let input = AsyncStream<Data>.makeStream()
        let output = AsyncStream<Data>.makeStream()
        let run = Task {
            defer { output.continuation.finish() }
            try await server.run(input: input.stream) { data in output.continuation.yield(data) }
        }
        input.continuation.yield(Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"settings_apply"}}"#.utf8))
        await fulfillment(of: [started], timeout: 2)
        input.continuation.yield(Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"storage_delete"}}"#.utf8))
        input.continuation.yield(Data(#"{"jsonrpc":"2.0","id":3,"method":"ping"}"#.utf8))
        input.continuation.finish()
        await fulfillment(of: [cancelled], timeout: 2)
        try await run.value

        var ids: [Int] = []
        for await data in output.stream {
            let reply = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            ids.append(try XCTUnwrap(reply["id"] as? Int))
        }
        XCTAssertEqual(ids, [3])
    }

    private static func watch(
        _ connection: NWConnection,
        started: XCTestExpectation?,
        disconnected: XCTestExpectation
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, complete, error in
            if let data, !data.isEmpty { started?.fulfill() }
            if complete || error != nil {
                disconnected.fulfill()
                connection.cancel()
            } else {
                watch(connection, started: data?.isEmpty == false ? nil : started, disconnected: disconnected)
            }
        }
    }
}
