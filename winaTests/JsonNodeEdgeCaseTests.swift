//
//  JsonNodeEdgeCaseTests.swift
//  winaTests
//
//  Edge-case coverage for JsonNode and JsonValue helpers.
//

import Foundation
import Testing
@testable import wina

@Suite("JsonNode Edge Cases")
struct JsonNodeEdgeCaseTests {

    @Test("Root id is stable")
    func testRootId() {
        let node = JsonNode(key: nil, value: .object([:]), depth: 0)
        #expect(node.id == "root")
    }

    @Test("Path-based id joins components")
    func testPathId() {
        let node = JsonNode(key: "name", value: .string("value"), depth: 2, path: ["items", "[0]", "name"])
        #expect(node.id == "items.[0].name")
    }

    @Test("Children sorted by key")
    func testChildrenSortedByKey() {
        let node = JsonNode(key: nil, value: .object(["b": .string("b"), "a": .string("a")]), depth: 0)
        let keys = node.children?.map { $0.displayKey }
        #expect(keys == ["a", "b"])
    }

    @Test("Array element detection")
    func testArrayElementDetection() {
        let node = JsonNode(key: "[0]", value: .number(1), depth: 1, path: ["items", "[0]"])
        #expect(node.isArrayElement)
        #expect(node.parentIsArray)
    }

    @Test("Non-array element detection")
    func testNonArrayElementDetection() {
        let node = JsonNode(key: "name", value: .string("value"), depth: 1, path: ["name"])
        #expect(!node.isArrayElement)
        #expect(!node.parentIsArray)
    }

    @Test("Display value for primitives")
    func testDisplayValuePrimitives() {
        let stringNode = JsonNode(key: "s", value: .string("hello"), depth: 1)
        let intNode = JsonNode(key: "n", value: .number(42), depth: 1)
        let floatNode = JsonNode(key: "n", value: .number(3.14), depth: 1)
        let boolNode = JsonNode(key: "b", value: .bool(true), depth: 1)
        let nullNode = JsonNode(key: "n", value: .null, depth: 1)

        #expect(stringNode.displayValue == "\"hello\"")
        #expect(intNode.displayValue == "42")
        #expect(floatNode.displayValue == "3.14")
        #expect(boolNode.displayValue == "true")
        #expect(nullNode.displayValue == "null")
    }

    @Test("Display value for containers")
    func testDisplayValueContainers() {
        let objectNode = JsonNode(key: "o", value: .object(["a": .number(1), "b": .number(2)]), depth: 1)
        let arrayNode = JsonNode(key: "a", value: .array([.number(1), .number(2), .number(3)]), depth: 1)

        #expect(objectNode.displayValue == "{2 items}")
        #expect(arrayNode.displayValue == "[3 items]")
    }

    @Test("Raw value for primitives")
    func testRawValuePrimitives() {
        let stringNode = JsonNode(key: "s", value: .string("hello"), depth: 1)
        let intNode = JsonNode(key: "n", value: .number(42), depth: 1)
        let floatNode = JsonNode(key: "n", value: .number(3.14), depth: 1)
        let boolNode = JsonNode(key: "b", value: .bool(false), depth: 1)
        let nullNode = JsonNode(key: "n", value: .null, depth: 1)

        #expect(stringNode.rawValue == "hello")
        #expect(intNode.rawValue == "42")
        #expect(floatNode.rawValue == "3.14")
        #expect(boolNode.rawValue == "false")
        #expect(nullNode.rawValue == "null")
    }

    @Test("Raw value for containers contains keys")
    func testRawValueContainers() {
        let objectNode = JsonNode(key: "o", value: .object(["b": .number(2), "a": .number(1)]), depth: 1)
        let arrayNode = JsonNode(key: "a", value: .array([.number(1), .number(2)]), depth: 1)

        #expect(objectNode.rawValue.contains("\"a\""))
        #expect(objectNode.rawValue.contains("\"b\""))
        #expect(arrayNode.rawValue.contains("1"))
        #expect(arrayNode.rawValue.contains("2"))
    }

    @Test("Type color mapping")
    func testTypeColorMapping() {
        switch JsonNode(key: nil, value: .object([:]), depth: 0).typeColor {
        case .object: #expect(true)
        default: #expect(false)
        }
        switch JsonNode(key: nil, value: .array([]), depth: 0).typeColor {
        case .array: #expect(true)
        default: #expect(false)
        }
        switch JsonNode(key: nil, value: .string(""), depth: 0).typeColor {
        case .string: #expect(true)
        default: #expect(false)
        }
        switch JsonNode(key: nil, value: .number(0), depth: 0).typeColor {
        case .number: #expect(true)
        default: #expect(false)
        }
        switch JsonNode(key: nil, value: .bool(false), depth: 0).typeColor {
        case .bool: #expect(true)
        default: #expect(false)
        }
        switch JsonNode(key: nil, value: .null, depth: 0).typeColor {
        case .null: #expect(true)
        default: #expect(false)
        }
    }
}

@Suite("JsonTypeColor Edge Cases")
struct JsonTypeColorEdgeCaseTests {

    @Test("Foreground colors are non-empty")
    func testForegroundColors() {
        #expect(!JsonTypeColor.object.foreground.isEmpty)
        #expect(!JsonTypeColor.array.foreground.isEmpty)
        #expect(!JsonTypeColor.string.foreground.isEmpty)
        #expect(!JsonTypeColor.number.foreground.isEmpty)
        #expect(!JsonTypeColor.bool.foreground.isEmpty)
        #expect(!JsonTypeColor.null.foreground.isEmpty)
    }
}


@Suite("Storage JSON Explorer Type Preservation")
@MainActor
struct JsonExplorerTypeTests {
    @Test("Displaying and copying preserves zero, one and Boolean JSON types")
    func testExplorerKeepsNumberAndBooleanTypes() throws {
        let original = "[0,1,true,false]"
        let value = try JSONSerialization.jsonObject(with: Data(original.utf8))
        let node = ExplorerNode.parse(value)
        guard case .array(_, let values) = node else { Issue.record("Expected array"); return }
        for (index, element) in values.enumerated() {
            if index < 2 {
                guard case .number(_, let number) = element else { Issue.record("Number became Boolean"); return }
                #expect(number == Double(index))
            } else {
                guard case .bool(_, let flag) = element else { Issue.record("Boolean became number"); return }
                #expect(flag == (index == 2))
            }
        }
        let copied = try #require(node.toJsonString())
        #expect(JsonParser.minify(copied) == original)
    }
}
