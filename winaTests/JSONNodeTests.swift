//
//  JSONNodeTests.swift
//  winaTests
//

import XCTest
@testable import wina

final class JSONNodeTests: XCTestCase {

    func testStableIdsAreDeterministic() throws {
        let jsonString = """
        {
            "name": "example",
            "items": [1, 2],
            "meta": { "enabled": true }
        }
        """
        let data = try XCTUnwrap(jsonString.data(using: .utf8))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let first = JSONNode.parse(json)
        let second = JSONNode.parse(json)

        XCTAssertEqual(collectIDs(from: first), collectIDs(from: second))
    }

    func testIdsContainPathComponents() throws {
        let jsonString = """
        { "items": [ { "name": "one" } ] }
        """
        let data = try XCTUnwrap(jsonString.data(using: .utf8))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let root = JSONNode.parse(json)
        let ids = collectIDs(from: root)

        XCTAssertTrue(ids.contains("root.items.[0].name"))
    }

    func testNumbersZeroAndOneRemainNumbers() throws {
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: Data("[0,1,true,false]".utf8)) as? [Any])
        for (index, value) in values.enumerated() {
            let node = JSONNode.parse(value)
            if index < 2 {
                guard case .number(_, let number, _) = node else {
                    return XCTFail("JSON number became Boolean")
                }
                XCTAssertEqual(number, Double(index))
            } else {
                guard case .bool(_, let flag, _) = node else {
                    return XCTFail("JSON Boolean became number")
                }
                XCTAssertEqual(flag, index == 2)
            }
        }
    }

    private func collectIDs(from node: JSONNode) -> [String] {
        var result = [node.id]
        switch node {
        case .array(_, let values, _):
            values.forEach { result.append(contentsOf: collectIDs(from: $0)) }
        case .object(_, let pairs, _):
            pairs.forEach { result.append(contentsOf: collectIDs(from: $0.1)) }
        default:
            break
        }
        return result
    }
}
