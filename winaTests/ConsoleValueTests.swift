import XCTest
import SwiftUI
@testable import wina

final class ConsoleValueTests: XCTestCase {

    // MARK: - Primitive Values

    func testStringValue() {
        let value = ConsoleValue.string("Hello, World!")
        XCTAssertEqual(value.preview, "\"Hello, World!\"")
        XCTAssertEqual(value.typeColor, .green)
        XCTAssertFalse(value.isExpandable)
    }

    func testNumberValue() {
        let intValue = ConsoleValue.number(42)
        XCTAssertEqual(intValue.preview, "42")

        let floatValue = ConsoleValue.number(3.14)
        XCTAssertEqual(floatValue.preview, "3.14")

        XCTAssertEqual(intValue.typeColor, .cyan)
        XCTAssertFalse(intValue.isExpandable)
    }

    func testNumberPreviewAndCopyHandleNonrepresentableIntegers() {
        let values: [Double] = [1e30, -1e30, Double(Int.max), .infinity, -.infinity, .nan]
        for number in values {
            let value = ConsoleValue.number(number)
            XCTAssertEqual(value.preview, String(number))
            let nested = ConsoleValue.array(ConsoleArray(elements: [value]))
            XCTAssertEqual(nested.copyableString, "[\n  \(number)\n]")
        }
    }

    func testBooleanValue() {
        let trueValue = ConsoleValue.boolean(true)
        XCTAssertEqual(trueValue.preview, "true")

        let falseValue = ConsoleValue.boolean(false)
        XCTAssertEqual(falseValue.preview, "false")

        XCTAssertEqual(trueValue.typeColor, .yellow)
        XCTAssertFalse(trueValue.isExpandable)
    }

    func testNullValue() {
        let value = ConsoleValue.null
        XCTAssertEqual(value.preview, "null")
        XCTAssertEqual(value.typeColor, .gray)
        XCTAssertFalse(value.isExpandable)
    }

    func testUndefinedValue() {
        let value = ConsoleValue.undefined
        XCTAssertEqual(value.preview, "undefined")
        XCTAssertEqual(value.typeColor, .gray)
        XCTAssertFalse(value.isExpandable)
    }

    // MARK: - Objects

    func testEmptyObject() {
        let obj = ConsoleObject(properties: [:])
        let value = ConsoleValue.object(obj)

        XCTAssertEqual(value.preview, "{}")
        XCTAssertTrue(value.isExpandable)
        XCTAssertEqual(value.typeColor, .blue)
    }

    func testObjectWithProperties() {
        let props: [String: ConsoleValue] = [
            "name": .string("John"),
            "age": .number(30),
            "active": .boolean(true)
        ]
        let obj = ConsoleObject(properties: props)
        let value = ConsoleValue.object(obj)

        XCTAssertEqual(value.preview, "{ 3 properties }")
        XCTAssertTrue(value.isExpandable)
    }

    func testNestedObject() {
        let innerProps: [String: ConsoleValue] = [
            "street": .string("123 Main St"),
            "city": .string("Springfield")
        ]
        let innerObj = ConsoleObject(properties: innerProps, depth: 1)

        let outerProps: [String: ConsoleValue] = [
            "name": .string("John"),
            "address": .object(innerObj)
        ]
        let outerObj = ConsoleObject(properties: outerProps, depth: 0)

        XCTAssertTrue(outerObj.shouldAutoExpand)
        XCTAssertTrue(innerObj.shouldAutoExpand)
    }

    func testObjectDepthExceeded() {
        let obj = ConsoleObject(properties: ["key": .string("value")], depth: 10)
        XCTAssertFalse(obj.shouldAutoExpand)
    }

    // MARK: - Arrays

    func testEmptyArray() {
        let arr = ConsoleArray(elements: [])
        let value = ConsoleValue.array(arr)

        XCTAssertEqual(value.preview, "[]")
        XCTAssertTrue(value.isExpandable)
    }

    func testArrayWithElements() {
        let elements = [
            ConsoleValue.number(1),
            ConsoleValue.number(2),
            ConsoleValue.number(3)
        ]
        let arr = ConsoleArray(elements: elements)
        let value = ConsoleValue.array(arr)

        XCTAssertEqual(value.preview, "[ 3 items ]")
        XCTAssertTrue(value.isExpandable)
    }

    // MARK: - Functions & Dates

    func testFunctionValue() {
        let value = ConsoleValue.function(name: "handleClick")
        XCTAssertEqual(value.preview, "ƒ handleClick()")
        XCTAssertEqual(value.typeColor, .orange)
        XCTAssertFalse(value.isExpandable)
    }

    func testDateValue() {
        let date = Date(timeIntervalSince1970: 0)  // Unix epoch
        let value = ConsoleValue.date(date)

        XCTAssertTrue(value.preview.contains("Date"))
        XCTAssertEqual(value.typeColor, .purple)
        XCTAssertFalse(value.isExpandable)
    }

    // MARK: - DOM Elements

    func testDOMElement() {
        let attrs = ["class": "container", "id": "main"]
        let value = ConsoleValue.domElement(tag: "div", attributes: attrs)

        XCTAssertEqual(value.preview, "<div#main.container>")
        XCTAssertEqual(value.typeColor, .red)
        XCTAssertTrue(value.isExpandable)
    }

    func testDOMElementPreviewWithMultipleClasses() {
        let attrs = ["class": "test primary", "id": "root"]
        let value = ConsoleValue.domElement(tag: "div", attributes: attrs)

        XCTAssertEqual(value.preview, "<div#root.test.primary>")
    }

    func testSerializedDOMPayloadParses() {
        let payload: [String: Any] = [
            "type": "dom",
            "tag": "div",
            "attributes": [
                "class": "test",
                "id": ""
            ]
        ]

        let parsed = ConsoleValue.fromSerializedAny(payload)
        guard case let .domElement(tag, attributes)? = parsed else {
            XCTFail("Expected domElement payload to parse")
            return
        }
        XCTAssertEqual(tag, "div")
        XCTAssertEqual(attributes["class"], "test")
        XCTAssertEqual(attributes["id"], "")
    }

    // MARK: - Collections

    func testMapValue() {
        let entries = [
            (key: "user", value: ConsoleValue.string("John")),
            (key: "id", value: ConsoleValue.number(123))
        ]
        let value = ConsoleValue.map(entries: entries)

        XCTAssertEqual(value.preview, "Map(2) { ... }")
        XCTAssertTrue(value.isExpandable)
    }

    func testSetValue() {
        let values = [
            ConsoleValue.string("apple"),
            ConsoleValue.string("banana"),
            ConsoleValue.string("cherry")
        ]
        let value = ConsoleValue.set(values: values)

        XCTAssertEqual(value.preview, "Set(3) { ... }")
        XCTAssertTrue(value.isExpandable)
    }

    // MARK: - Special Cases

    func testCircularReference() {
        let value = ConsoleValue.circularReference("parent.child")
        XCTAssertEqual(value.preview, "[Circular parent.child]")
        XCTAssertEqual(value.typeColor, .gray)
        XCTAssertFalse(value.isExpandable)
    }

    func testErrorValue() {
        let value = ConsoleValue.error(message: "Something went wrong")
        XCTAssertEqual(value.preview, "Error: Something went wrong")
        XCTAssertEqual(value.typeColor, .red)
        XCTAssertFalse(value.isExpandable)
    }

    // MARK: - RegExp Serialization

    func testSerializedRegExpPayloadParses() {
        let payload: [String: Any] = [
            "type": "regexp",
            "value": "/test/gi"
        ]

        let parsed = ConsoleValue.fromSerializedAny(payload)
        guard case let .string(regexpString)? = parsed else {
            XCTFail("Expected regexp payload to parse as string")
            return
        }
        XCTAssertEqual(regexpString, "/test/gi")
    }

    func testSerializedRegExpWithComplexPattern() {
        let payload: [String: Any] = [
            "type": "regexp",
            "value": "/^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\\.[a-zA-Z0-9-.]+$/i"
        ]

        let parsed = ConsoleValue.fromSerializedAny(payload)
        guard case let .string(regexpString)? = parsed else {
            XCTFail("Expected regexp payload to parse as string")
            return
        }
        XCTAssertTrue(regexpString.hasPrefix("/"))
        XCTAssertTrue(regexpString.hasSuffix("/i"))
    }

    func testSerializedRegExpWithoutValue() {
        let payload: [String: Any] = [
            "type": "regexp"
        ]

        let parsed = ConsoleValue.fromSerializedAny(payload)
        guard case let .string(regexpString)? = parsed else {
            XCTFail("Expected regexp payload to parse as string with default")
            return
        }
        XCTAssertEqual(regexpString, "/(?:)/")
    }

    // MARK: - Factory Methods

    func testFromObjectDictionary() {
        let dict: [String: Any] = [
            "name": "Alice",
            "age": 25,
            "active": true
        ]
        var seen: Set<String> = []
        let value = ConsoleValue.fromObject(dict, depth: 0, seenObjects: &seen)

        guard case let .object(obj) = value else {
            XCTFail("Expected object type")
            return
        }

        XCTAssertEqual(obj.properties.count, 3)
        XCTAssertEqual(obj.depth, 0)
        XCTAssertTrue(obj.shouldAutoExpand)
    }

    func testFromArray() {
        let arr: [Any] = [1, "two", true, NSNull()]
        var seen: Set<String> = []
        let value = ConsoleValue.fromArray(arr, depth: 0, seenObjects: &seen)

        guard case let .array(arr) = value else {
            XCTFail("Expected array type")
            return
        }

        XCTAssertEqual(arr.elements.count, 4)
        XCTAssertTrue(arr.shouldAutoExpand)
    }

    func testFromAnyVariousTypes() {
        var seen: Set<String> = []

        let stringVal = ConsoleValue.fromAny("hello", seenObjects: &seen)
        guard case .string(let str) = stringVal else { XCTFail(); return }
        XCTAssertEqual(str, "hello")

        let numVal = ConsoleValue.fromAny(42 as NSNumber, seenObjects: &seen)
        guard case .number(let num) = numVal else { XCTFail(); return }
        XCTAssertEqual(num, 42)

        let boolVal = ConsoleValue.fromAny(true as NSNumber, seenObjects: &seen)
        guard case .boolean(let bool) = boolVal else { XCTFail(); return }
        XCTAssertEqual(bool, true)

        let nullVal = ConsoleValue.fromAny(NSNull(), seenObjects: &seen)
        guard case .null = nullVal else { XCTFail(); return }
    }

    // MARK: - Object Sorting

    func testObjectPropertiesSorted() {
        let props: [String: ConsoleValue] = [
            "zebra": .string("z"),
            "apple": .string("a"),
            "mango": .string("m")
        ]
        let obj = ConsoleObject(properties: props)
        let sorted = obj.sortedProperties

        XCTAssertEqual(sorted[0].key, "apple")
        XCTAssertEqual(sorted[1].key, "mango")
        XCTAssertEqual(sorted[2].key, "zebra")
    }

    // MARK: - Equatable Conformance

    func testEquatable() {
        let val1 = ConsoleValue.string("hello")
        let val2 = ConsoleValue.string("hello")
        let val3 = ConsoleValue.string("world")

        XCTAssertEqual(val1, val2)
        XCTAssertNotEqual(val1, val3)

        let num1 = ConsoleValue.number(42)
        let num2 = ConsoleValue.number(42)
        XCTAssertEqual(num1, num2)
    }
}
