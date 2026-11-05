//
//  PreloadProfileTests.swift
//  winaTests
//

import JavaScriptCore
import XCTest

@testable import wina

final class PreloadProfileTests: XCTestCase {
    func testNativeBridgeDemoPresetProvidesReusableCase() {
        let preset = WebViewPreloadProfile.nativeBridgeDemoPreset

        XCTAssertTrue(preset.isEnabled)
        XCTAssertEqual(preset.name, "Native Bridge Demo")
        XCTAssertEqual(preset.cookies.first?.name, "walnut_session")
        XCTAssertEqual(preset.bridgeChannels.first?.name, "request")
        XCTAssertTrue(preset.enabledBridgeChannelNames.contains("request"))
        XCTAssertTrue(preset.enabledBridgeChannelNames.contains("winaPostMessage"))
    }

    func testBootstrapScriptContainsWindowItemsAndPostMessageCapture() {
        let script = PreloadScriptBuilder.bootstrapScript(for: .nativeBridgeDemoPreset)

        XCTAssertTrue(script.contains("__winaPreloadSetPath"))
        XCTAssertTrue(script.contains("\"appVersion\""))
        XCTAssertTrue(script.contains("\"getAuthToken\""))
        XCTAssertTrue(script.contains("window.addEventListener('message'"))
        XCTAssertTrue(script.contains("messageHandlers.winaPostMessage"))
    }

    func testTemplateRendererReplacesNestedMessageValues() {
        let message: [String: Any] = [
            "id": "req-1",
            "type": "getAuthToken",
            "payload": [
                "action": "login"
            ],
        ]

        let rendered = BridgeTemplateRenderer.render(
            #"{"id":"{{message.id}}","action":"{{message.payload.action}}"}"#,
            message: message
        )

        XCTAssertEqual(rendered, #"{"id":"req-1","action":"login"}"#)
    }

    func testTemplateRendererEscapesStringValuesInsideJSON() throws {
        let rendered = BridgeTemplateRenderer.render(
            #"{"id":"{{message.id}}"}"#,
            message: ["id": #"quote"and\slash"#]
        )
        let data = try XCTUnwrap(rendered.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(object["id"], #"quote"and\slash"#)
    }

    func testTemplateRendererPreservesBooleanAndNumberTypesInJSON() throws {
        let rendered = BridgeTemplateRenderer.render(
            #"{"ok":{{message.payload.ok}},"count":{{message.payload.count}},"one":{{message.payload.one}},"zero":{{message.payload.zero}}}"#,
            message: [
                "payload": [
                    "ok": true,
                    "count": 3,
                    "one": 1,
                    "zero": NSNumber(value: 0),
                ]
            ]
        )
        let data = try XCTUnwrap(rendered.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(rendered, #"{"ok":true,"count":3,"one":1,"zero":0}"#)
        XCTAssertEqual(object["ok"] as? Bool, true)
        XCTAssertEqual((object["count"] as? NSNumber)?.intValue, 3)
        XCTAssertEqual((object["one"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((object["zero"] as? NSNumber)?.intValue, 0)
    }

    func testTemplateRendererReplacesNullObjectAndArrayValues() throws {
        let rendered = BridgeTemplateRenderer.render(
            #"{"payload":{{message.payload}},"first":"{{message.payload.items.0.name}}","missing":{{message.payload.missing}}}"#,
            message: [
                "payload": [
                    "items": [
                        ["name": "first"],
                        ["name": "second"],
                    ],
                    "missing": NSNull(),
                ]
            ]
        )
        let data = try XCTUnwrap(rendered.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try XCTUnwrap(object["payload"] as? [String: Any])
        let items = try XCTUnwrap(payload["items"] as? [[String: String]])

        XCTAssertEqual(items.map { $0["name"] }, ["first", "second"])
        XCTAssertTrue(payload["missing"] is NSNull)
        XCTAssertEqual(object["first"] as? String, "first")
        XCTAssertTrue(object["missing"] is NSNull)
    }

    func testTemplateRendererDoesNotReExpandMessageControlledTokens() {
        let rendered = BridgeTemplateRenderer.render(
            #"{"a":"{{message.a}}","b":"{{message.b}}"}"#,
            message: [
                "a": "{{message.b}}",
                "b": "INJECTED",
            ]
        )

        XCTAssertEqual(rendered, #"{"a":"{{message.b}}","b":"INJECTED"}"#)
    }

    func testJavaScriptLiteralEscapesLineSeparators() {
        let literal = JavaScriptLiteral.quoted("first\u{2028}second\u{2029}third")

        XCTAssertEqual(literal, #""first\u2028second\u2029third""#)
    }

    func testJavaScriptLiteralEscapesScriptClosingTags() {
        let literal = JavaScriptLiteral.quoted("</script>")

        XCTAssertTrue(literal.contains(#"\u003C"#))
        XCTAssertFalse(literal.contains("</script>"))
    }

    func testTemplateRendererEscapesLineSeparatorsInsideJSONStrings() throws {
        let rendered = BridgeTemplateRenderer.render(
            #"{"value":"{{message.value}}"}"#,
            message: ["value": "first\u{2028}second\u{2029}third"]
        )
        let data = try XCTUnwrap(rendered.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(rendered, #"{"value":"first\u2028second\u2029third"}"#)
        XCTAssertEqual(object["value"], "first\u{2028}second\u{2029}third")
    }

    func testTemplateRendererEscapesLineSeparatorsInsideObjectPathJSON() throws {
        let rendered = BridgeTemplateRenderer.render(
            #"{"payload":{{message.payload}}}"#,
            message: [
                "payload": [
                    "value": "first\u{2028}second\u{2029}third"
                ]
            ]
        )
        let data = try XCTUnwrap(rendered.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try XCTUnwrap(object["payload"] as? [String: String])

        XCTAssertEqual(rendered, #"{"payload":{"value":"first\u2028second\u2029third"}}"#)
        XCTAssertEqual(payload["value"], "first\u{2028}second\u{2029}third")
    }

    func testTemplateRendererEscapesLineSeparatorsInsideRootMessageJSON() throws {
        let rendered = BridgeTemplateRenderer.render(
            #"{"message":{{message}}}"#,
            message: [
                "value": "first\u{2028}second\u{2029}third"
            ]
        )
        let data = try XCTUnwrap(rendered.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let message = try XCTUnwrap(object["message"] as? [String: String])

        XCTAssertEqual(rendered, #"{"message":{"value":"first\u2028second\u2029third"}}"#)
        XCTAssertEqual(message["value"], "first\u{2028}second\u{2029}third")
    }

    func testTemplateRendererEscapesScriptClosingTagsInsideObjectPathJSON() throws {
        let rendered = BridgeTemplateRenderer.render(
            #"{"payload":{{message.payload}}}"#,
            message: [
                "payload": [
                    "html": "</script>"
                ]
            ]
        )
        let data = try XCTUnwrap(rendered.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try XCTUnwrap(object["payload"] as? [String: String])

        XCTAssertTrue(rendered.contains(#"\u003C"#))
        XCTAssertFalse(rendered.contains("</script>"))
        XCTAssertEqual(payload["html"], "</script>")
    }

    func testBridgeRuleMatcherSupportsTypeAndJSONPath() {
        let message: [String: Any] = [
            "type": "getAuthToken",
            "payload": [
                "action": "login"
            ],
        ]

        XCTAssertTrue(BridgeRuleMatcher.matches(.typeEquals("getAuthToken"), message: message))
        XCTAssertTrue(
            BridgeRuleMatcher.matches(.jsonPathEquals(path: "payload.action", value: "login"), message: message))
        XCTAssertFalse(
            BridgeRuleMatcher.matches(.jsonPathEquals(path: "payload.action", value: "logout"), message: message))
    }

    func testBridgeRuleMatcherUsesBooleanTextValues() {
        let message: [String: Any] = [
            "payload": [
                "ok": true,
                "cached": NSNumber(value: false),
                "one": NSNumber(value: 1),
                "zero": NSNumber(value: 0),
            ]
        ]

        XCTAssertTrue(BridgeRuleMatcher.matches(.jsonPathEquals(path: "payload.ok", value: "true"), message: message))
        XCTAssertTrue(
            BridgeRuleMatcher.matches(.jsonPathEquals(path: "payload.cached", value: "false"), message: message))
        XCTAssertFalse(BridgeRuleMatcher.matches(.jsonPathEquals(path: "payload.ok", value: "1"), message: message))
        XCTAssertTrue(BridgeRuleMatcher.matches(.jsonPathEquals(path: "payload.one", value: "1"), message: message))
        XCTAssertTrue(BridgeRuleMatcher.matches(.jsonPathEquals(path: "payload.zero", value: "0"), message: message))
        XCTAssertFalse(BridgeRuleMatcher.matches(.jsonPathEquals(path: "payload.one", value: "true"), message: message))
        XCTAssertFalse(
            BridgeRuleMatcher.matches(.jsonPathEquals(path: "payload.zero", value: "false"), message: message))
    }

    func testResponseScriptPostsRenderedMessage() {
        let response = BridgeResponse(
            target: .postMessage,
            bodyTemplate: #"{"id":"{{message.id}}","ok":true}"#
        )
        let script = PreloadScriptBuilder.responseScript(
            for: response,
            message: ["id": "req-1"],
            channel: "request"
        )

        XCTAssertTrue(script.contains("window.postMessage"))
        XCTAssertTrue(script.contains(#""id":"req-1""#))
        XCTAssertTrue(script.contains(#""ok":true"#))
    }

    func testResponseScriptRejectsInvalidJSONBody() {
        let response = BridgeResponse(
            target: .postMessage,
            bodyTemplate: #"{"ok": true"#
        )

        let script = PreloadScriptBuilder.responseScript(
            for: response,
            message: [:],
            channel: "request"
        )

        XCTAssertTrue(script.isEmpty)
    }

    func testResponseScriptRejectsInvalidPlaceholderAtRuntime() {
        let response = BridgeResponse(
            target: .postMessage,
            bodyTemplate: #"{"id":{{messsage.id}}}"#
        )

        let script = PreloadScriptBuilder.responseScript(
            for: response,
            message: ["id": "req-1"],
            channel: "request"
        )

        XCTAssertTrue(script.isEmpty)
    }

    func testResponseBodyValidatorAllowsUnquotedPlaceholders() {
        XCTAssertTrue(
            BridgeResponseBodyValidator.isValidTemplate(
                #"{"ok":{{message.payload.ok}},"payload":{{message.payload}}}"#
            )
        )
        XCTAssertFalse(BridgeResponseBodyValidator.isValidTemplate(#"{"ok": true"#))
        XCTAssertFalse(BridgeResponseBodyValidator.isValidTemplate(#"{"id":{{messsage.id}}}"#))
        XCTAssertFalse(BridgeResponseBodyValidator.isValidTemplate(#"{"id":{{message.}}}"#))
        XCTAssertFalse(BridgeResponseBodyValidator.isValidTemplate(#"{"id":{{message..id}}}"#))
    }

    func testResponseScriptUsesNullForMissingPlaceholders() {
        let response = BridgeResponse(
            target: .postMessage,
            bodyTemplate: #"{"token":{{message.payload.token}}}"#
        )

        let script = PreloadScriptBuilder.responseScript(
            for: response,
            message: ["payload": [:]],
            channel: "request"
        )

        XCTAssertTrue(script.contains(#""token":null"#))
    }

    func testResponseScriptUsesNullForMissingQuotedPlaceholder() {
        let response = BridgeResponse(
            target: .postMessage,
            bodyTemplate: #"{"id":"{{message.id}}"}"#
        )

        let script = PreloadScriptBuilder.responseScript(
            for: response,
            message: [:],
            channel: "request"
        )

        XCTAssertTrue(script.contains(#""id":null"#))
        XCTAssertFalse(script.contains(#""id":"null""#))
    }

    func testResponseScriptQuotesStringForUnquotedPlaceholder() {
        let response = BridgeResponse(
            target: .postMessage,
            bodyTemplate: #"{"token":{{message.payload.token}}}"#
        )

        let script = PreloadScriptBuilder.responseScript(
            for: response,
            message: ["payload": ["token": "abc"]],
            channel: "request"
        )

        XCTAssertTrue(script.contains(#""token":"abc""#))
    }

    func testResponseScriptEscapesStructuredPlaceholderInsideString() {
        let response = BridgeResponse(
            target: .postMessage,
            bodyTemplate: #"{"debug":"payload={{message.payload}}"}"#
        )

        let script = PreloadScriptBuilder.responseScript(
            for: response,
            message: ["payload": ["a": "b"]],
            channel: "request"
        )

        XCTAssertTrue(script.contains(#""debug":"payload={\"a\":\"b\"}""#))
    }

    func testResponseScriptKeepsObjectKeyPlaceholderQuoted() {
        let response = BridgeResponse(
            target: .postMessage,
            bodyTemplate: #"{"{{message.key}}":true}"#
        )

        let script = PreloadScriptBuilder.responseScript(
            for: response,
            message: ["key": NSNumber(value: 42)],
            channel: "request"
        )

        XCTAssertTrue(script.contains(#""42":true"#))
    }

    func testResponseBodyRendererHandlesEscapedQuoteBeforePlaceholder() throws {
        let rendered = BridgeTemplateRenderer.renderResponseBody(
            #"{"debug":"literal quote: \"{{message.id}}"}"#,
            message: ["id": "abc"]
        )
        let data = try XCTUnwrap(rendered.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(object["debug"], #"literal quote: "abc"#)
    }

    func testResponseScriptSupportsTopLevelArrayPlaceholders() {
        let response = BridgeResponse(
            target: .postMessage,
            bodyTemplate: #"{"first":{{message.0}}}"#
        )

        let script = PreloadScriptBuilder.responseScript(
            for: response,
            message: ["abc"],
            channel: "request"
        )

        XCTAssertTrue(script.contains(#""first":"abc""#))
    }

    func testResponseScriptSupportsTopLevelPrimitivePlaceholder() {
        let response = BridgeResponse(
            target: .postMessage,
            bodyTemplate: #"{"value":{{message}}}"#
        )

        let script = PreloadScriptBuilder.responseScript(
            for: response,
            message: NSNumber(value: 42),
            channel: "request"
        )

        XCTAssertTrue(script.contains(#""value":42"#))
    }

    func testJavaScriptPathRejectsEmptySegments() {
        XCTAssertFalse(JavaScriptPath.isValid(".onNativeResponse"))
        XCTAssertFalse(JavaScriptPath.isValid("app..onNativeResponse"))
        XCTAssertFalse(JavaScriptPath.isValid("app."))
        XCTAssertTrue(JavaScriptPath.isValid("app.onNativeResponse"))
    }

    func testBootstrapScriptExecutesWindowItemsInJavaScriptContext() throws {
        let profile = WebViewPreloadProfile(
            isEnabled: true,
            windowItems: [
                WindowInjectionItem(name: "app.version", kind: .variable, valueKind: .string, value: "1.2.3"),
                WindowInjectionItem(name: "feature.enabled", kind: .variable, valueKind: .json, value: "true"),
                WindowInjectionItem(name: "native.token", kind: .functionReturn, valueKind: .string, value: "secret"),
                WindowInjectionItem(
                    name: "native.payload", kind: .functionBody, value: #"return { ok: true, count: 2 };"#),
            ]
        )
        let context = makeJavaScriptContext()

        context.evaluateScript("var window = this;")
        context.evaluateScript(PreloadScriptBuilder.bootstrapScript(for: profile))

        XCTAssertEqual(context.evaluateScript("window.app.version").toString(), "1.2.3")
        XCTAssertTrue(context.evaluateScript("window.feature.enabled").toBool())
        XCTAssertEqual(context.evaluateScript("window.native.token()").toString(), "secret")
        XCTAssertEqual(
            context.evaluateScript("JSON.stringify(window.native.payload())").toString(), #"{"ok":true,"count":2}"#)
    }

    func testBadFunctionBodyWindowItemDoesNotBreakSiblingInjection() {
        let profile = WebViewPreloadProfile(
            isEnabled: true,
            windowItems: [
                WindowInjectionItem(name: "good.value", kind: .variable, valueKind: .string, value: "ok"),
                // Syntax error in the body. Built via `new Function`, so it throws a catchable
                // error at runtime instead of failing to parse the whole shared bootstrap.
                WindowInjectionItem(name: "bad.fn", kind: .functionBody, value: "return ( ; }{"),
            ]
        )
        let context = makeJavaScriptContext()
        context.evaluateScript("var window = this; var console = { warn: function() {}, log: function() {} };")
        context.evaluateScript(PreloadScriptBuilder.bootstrapScript(for: profile))

        // The broken functionBody item must not take down helpers or sibling items.
        XCTAssertEqual(context.evaluateScript("window.good.value").toString(), "ok")
        XCTAssertEqual(context.evaluateScript("typeof window.__winaPreloadSetPath").toString(), "function")
    }

    func testResponseScriptExecutesPostMessageInJavaScriptContext() throws {
        let response = BridgeResponse(
            target: .postMessage,
            bodyTemplate: #"{"id":"{{message.id}}","ok":{{message.payload.ok}},"count":{{message.payload.count}}}"#
        )
        let script = PreloadScriptBuilder.responseScript(
            for: response,
            message: [
                "id": "req-1",
                "payload": [
                    "ok": NSNumber(value: true),
                    "count": NSNumber(value: 1),
                ],
            ],
            channel: "request"
        )
        let context = makeJavaScriptContext()

        context.evaluateScript(
            """
            var window = this;
            var posted = null;
            window.postMessage = function(body, target) {
                posted = { body: body, target: target };
            };
            """
        )
        context.evaluateScript(script)

        XCTAssertEqual(context.evaluateScript("posted.target").toString(), "*")
        XCTAssertEqual(
            context.evaluateScript("JSON.stringify(posted.body)").toString(), #"{"id":"req-1","ok":true,"count":1}"#)
    }

    func testPostMessageCaptureSkipsOnlyTaggedNativeBridgeResponses() throws {
        let profile = WebViewPreloadProfile(
            isEnabled: true,
            capturesWindowPostMessage: true
        )
        let response = BridgeResponse(
            target: .postMessage,
            bodyTemplate: #"{"type":"nativeResponse"}"#
        )
        let responseScript = PreloadScriptBuilder.responseScript(
            for: response,
            message: [:],
            channel: "request"
        )
        let context = makeJavaScriptContext()

        context.evaluateScript(
            """
            var window = this;
            var captured = [];
            var pageObserved = [];
            window.webkit = {
                messageHandlers: {
                    winaPostMessage: {
                        postMessage: function(body) { captured.push(body); }
                    }
                }
            };
            var listeners = [];
            window.addEventListener = function(name, listener) {
                if (name === 'message') listeners.push(listener);
            };
            var queuedMessages = [];
            window.postMessage = function(body, target) {
                queuedMessages.push({ origin: 'test://page', data: body });
            };
            function flushQueuedMessages() {
                while (queuedMessages.length > 0) {
                    var event = queuedMessages.shift();
                    listeners.forEach(function(listener) {
                        listener(event);
                    });
                }
            }
            """
        )
        context.evaluateScript(PreloadScriptBuilder.bootstrapScript(for: profile))
        context.evaluateScript(
            """
            window.addEventListener('message', function(event) {
                pageObserved.push(event.data);
            });
            """
        )
        context.evaluateScript("window.postMessage({ type: 'pageMessage' }, '*');")
        context.evaluateScript(responseScript)
        context.evaluateScript("flushQueuedMessages();")

        XCTAssertEqual(context.evaluateScript("captured.length").toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("captured[0].data.type").toString(), "pageMessage")
        XCTAssertEqual(context.evaluateScript("pageObserved.length").toInt32(), 2)
        XCTAssertEqual(context.evaluateScript("pageObserved[1].type").toString(), "nativeResponse")
        XCTAssertTrue(
            context.evaluateScript("pageObserved[1].__winaPreloadNativePostMessageToken === undefined").toBool())
    }

    func testPostMessageCaptureSkipsNativePrimitiveResponses() throws {
        let profile = WebViewPreloadProfile(
            isEnabled: true,
            capturesWindowPostMessage: true
        )
        let response = BridgeResponse(
            target: .postMessage,
            bodyTemplate: #""nativeResponse""#
        )
        let responseScript = PreloadScriptBuilder.responseScript(
            for: response,
            message: [:],
            channel: "request"
        )
        let context = makeJavaScriptContext()

        context.evaluateScript(
            """
            var window = this;
            var captured = [];
            window.webkit = {
                messageHandlers: {
                    winaPostMessage: {
                        postMessage: function(body) { captured.push(body); }
                    }
                }
            };
            var listeners = [];
            window.addEventListener = function(name, listener) {
                if (name === 'message') listeners.push(listener);
            };
            window.postMessage = function(body, target) {
                listeners.forEach(function(listener) {
                    listener({ origin: 'test://page', data: body });
                });
            };
            """
        )
        context.evaluateScript(PreloadScriptBuilder.bootstrapScript(for: profile))
        context.evaluateScript(responseScript)
        context.evaluateScript("window.postMessage({ type: 'pageMessage' }, '*');")

        XCTAssertEqual(context.evaluateScript("captured.length").toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("captured[0].data.type").toString(), "pageMessage")
    }

    func testPostMessageCaptureSkipsNativeArrayResponses() throws {
        let profile = WebViewPreloadProfile(
            isEnabled: true,
            capturesWindowPostMessage: true
        )
        let response = BridgeResponse(
            target: .postMessage,
            bodyTemplate: #"[{"type":"nativeResponse"}]"#
        )
        let responseScript = PreloadScriptBuilder.responseScript(
            for: response,
            message: [:],
            channel: "request"
        )
        let context = makeJavaScriptContext()

        context.evaluateScript(
            """
            var window = this;
            var captured = [];
            window.webkit = {
                messageHandlers: {
                    winaPostMessage: {
                        postMessage: function(body) { captured.push(body); }
                    }
                }
            };
            var listeners = [];
            window.addEventListener = function(name, listener) {
                if (name === 'message') listeners.push(listener);
            };
            window.postMessage = function(body, target) {
                listeners.forEach(function(listener) {
                    listener({ origin: 'test://page', data: body });
                });
            };
            """
        )
        context.evaluateScript(PreloadScriptBuilder.bootstrapScript(for: profile))
        context.evaluateScript(responseScript)
        context.evaluateScript("window.postMessage({ type: 'pageMessage' }, '*');")

        XCTAssertEqual(context.evaluateScript("captured.length").toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("captured[0].data.type").toString(), "pageMessage")
    }

    func testPreloadBridgeLogTruncatesLargeBodies() {
        let body = String(repeating: "a", count: PreloadBridgeLogFormatter.maxBodyLength + 10)
        let truncated = PreloadBridgeLogFormatter.truncated(body)

        XCTAssertLessThanOrEqual(truncated.count, PreloadBridgeLogFormatter.maxBodyLength)
        XCTAssertTrue(truncated.contains("truncated"))
    }

    func testPreloadSettingsStateRejectsInvalidEnabledCallbackRule() {
        let suiteName = "PreloadProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let baseline = WebViewPreloadProfile(name: "Baseline", isEnabled: true)
        PreloadProfileStore.saveActiveProfile(baseline, defaults: defaults)

        var invalid = WebViewPreloadProfile(
            name: "Invalid",
            isEnabled: true,
            bridgeChannels: [
                BridgeChannel(
                    name: "request",
                    responseRules: [
                        BridgeResponseRule(
                            response: BridgeResponse(target: .callback, callbackName: "bad-name")
                        ),
                    ]
                ),
            ]
        )
        var state = PreloadProfileSettingsState()
        state.profile = invalid

        XCTAssertNotNil(state.validationMessage)
        state.applyCurrentProfile(defaults: defaults)
        state.saveCurrentProfile(defaults: defaults)

        XCTAssertEqual(PreloadProfileStore.activeProfile(defaults: defaults).name, "Baseline")
        XCTAssertEqual(PreloadProfileStore.savedProfiles(defaults: defaults), [])

        invalid.isEnabled = false
        state.profile = invalid
        XCTAssertNil(state.validationMessage)
    }

    func testPreloadSettingsStateAllowsInvalidChannelNameWhenProfileDisabled() {
        var state = PreloadProfileSettingsState()
        state.profile = WebViewPreloadProfile(
            name: "Invalid Channel",
            isEnabled: false,
            bridgeChannels: [
                BridgeChannel(
                    isEnabled: true,
                    name: "winaPostMessage",
                    responseRules: [
                        BridgeResponseRule(response: BridgeResponse(target: .postMessage)),
                    ]
                ),
            ]
        )

        XCTAssertNil(state.validationMessage)
    }

    func testPreloadSettingsStateRejectsInvalidChannelNameWhenProfileEnabled() {
        var state = PreloadProfileSettingsState()
        state.profile = WebViewPreloadProfile(
            name: "Invalid Channel",
            isEnabled: true,
            bridgeChannels: [
                BridgeChannel(
                    isEnabled: true,
                    name: "winaPostMessage",
                    responseRules: [
                        BridgeResponseRule(response: BridgeResponse(target: .postMessage)),
                    ]
                ),
            ]
        )

        XCTAssertNotNil(state.validationMessage)
    }

    func testInvalidChannelNamesAreExcluded() {
        let profile = WebViewPreloadProfile(
            isEnabled: true,
            bridgeChannels: [
                BridgeChannel(name: "request"),
                BridgeChannel(name: "bad-name"),
                BridgeChannel(name: "consoleLog"),
                BridgeChannel(name: "winaPostMessage"),
            ]
        )

        XCTAssertEqual(profile.enabledBridgeChannelNames, ["request"])
    }

    func testSavedSetupListStartsEmptyAndDeletesStayDeleted() {
        let suiteName = "PreloadProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Saved setups exist only when the user saves one — no forced "Default" entry.
        let initialProfiles = PreloadProfileStore.savedProfiles(defaults: defaults)
        XCTAssertEqual(initialProfiles, [])

        let customProfile = WebViewPreloadProfile(name: "Custom", isEnabled: true)
        PreloadProfileStore.upsertSavedProfile(customProfile, defaults: defaults)
        let createdProfiles = PreloadProfileStore.savedProfiles(defaults: defaults)

        XCTAssertEqual(createdProfiles.map(\.name), ["Custom"])
        XCTAssertEqual(createdProfiles.first?.id, customProfile.id)

        PreloadProfileStore.saveProfiles(
            createdProfiles.filter { $0.id != customProfile.id },
            defaults: defaults
        )

        // Deleting the last saved setup leaves an empty list; "Default" never resurrects,
        // even after re-reading the store.
        XCTAssertEqual(PreloadProfileStore.savedProfiles(defaults: defaults), [])
        XCTAssertEqual(PreloadProfileStore.savedProfiles(defaults: defaults), [])
    }

    func testActiveProfileFallsBackToDefaultWithoutSeedingSavedList() {
        let suiteName = "PreloadProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let activeProfile = PreloadProfileStore.activeProfile(defaults: defaults)

        // The active profile falls back to a disabled default object, but that fallback is
        // never written into the saved list.
        XCTAssertEqual(activeProfile.id, WebViewPreloadProfile.defaultSavedSetupID)
        XCTAssertEqual(activeProfile.name, "Default")
        XCTAssertFalse(activeProfile.isEnabled)
        XCTAssertEqual(PreloadProfileStore.savedProfiles(defaults: defaults), [])
    }

    func testSavingInitialDefaultSetupDoesNotCreateDuplicateDefault() {
        let suiteName = "PreloadProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var state = PreloadProfileSettingsState()
        state.loadIfNeeded(
            activeProfile: { PreloadProfileStore.activeProfile(defaults: defaults) },
            savedProfiles: { PreloadProfileStore.savedProfiles(defaults: defaults) }
        )

        state.saveCurrentProfile(defaults: defaults)

        let savedProfiles = PreloadProfileStore.savedProfiles(defaults: defaults)
        let activeProfile = PreloadProfileStore.activeProfile(defaults: defaults)
        // Saving the initial default draft adds exactly one "Default" entry (no duplicate) and
        // does not force-enable or write the active profile — Save only touches the saved list.
        XCTAssertEqual(savedProfiles.map(\.name), ["Default"])
        XCTAssertEqual(savedProfiles.first?.id, WebViewPreloadProfile.defaultSavedSetupID)
        XCTAssertEqual(activeProfile.id, WebViewPreloadProfile.defaultSavedSetupID)
        XCTAssertFalse(activeProfile.isEnabled)
        XCTAssertFalse(savedProfiles.first?.isEnabled ?? true)
    }

    func testSaveCurrentProfileAddsToListWithoutTouchingActive() {
        let suiteName = "PreloadProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var previousActive = WebViewPreloadProfile.nativeBridgeDemoPreset
        previousActive.id = UUID()
        previousActive.name = "Native Bridge Demo Copy"
        PreloadProfileStore.saveActiveProfile(previousActive, defaults: defaults)
        PreloadProfileStore.saveProfiles([previousActive, .defaultSavedSetup], defaults: defaults)

        var state = PreloadProfileSettingsState()
        state.loadIfNeeded(
            activeProfile: { PreloadProfileStore.activeProfile(defaults: defaults) },
            savedProfiles: { PreloadProfileStore.savedProfiles(defaults: defaults) }
        )

        state.startEmptySetup()
        state.saveCurrentProfile(defaults: defaults)

        let activeProfile = PreloadProfileStore.activeProfile(defaults: defaults)
        let savedProfiles = PreloadProfileStore.savedProfiles(defaults: defaults)

        // Save only writes the saved list — the ACTIVE profile is untouched, so Apply remains
        // the single action that changes what is active (and Cancel can truly roll back).
        XCTAssertEqual(activeProfile.id, previousActive.id)
        XCTAssertEqual(activeProfile.name, "Native Bridge Demo Copy")
        XCTAssertTrue(savedProfiles.contains { $0.id == state.profile.id && $0.name == "Untitled Setup" })
        XCTAssertTrue(savedProfiles.contains { $0.name == "Native Bridge Demo Copy" })
    }

    func testRemoveLegacyGeneratedDemoCopyMigrationRunsOnce() {
        let suiteName = "PreloadProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var legacyCopy = WebViewPreloadProfile.nativeBridgeDemoPreset
        legacyCopy.id = UUID()
        legacyCopy.name = "Native Bridge Demo Copy"
        let custom = WebViewPreloadProfile(name: "Custom", isEnabled: true)
        PreloadProfileStore.saveProfiles([legacyCopy, custom], defaults: defaults)

        // First run drops the unedited legacy copy and keeps user setups.
        PreloadProfileStore.removeLegacyGeneratedDemoCopyIfNeeded(defaults: defaults)
        XCTAssertEqual(PreloadProfileStore.savedProfiles(defaults: defaults).map(\.name), ["Custom"])

        // The migration is one-time: re-adding the copy and running again leaves it in place,
        // so a user may keep their own "Native Bridge Demo Copy" going forward.
        PreloadProfileStore.saveProfiles([legacyCopy, custom], defaults: defaults)
        PreloadProfileStore.removeLegacyGeneratedDemoCopyIfNeeded(defaults: defaults)
        XCTAssertEqual(
            PreloadProfileStore.savedProfiles(defaults: defaults).map(\.name),
            ["Native Bridge Demo Copy", "Custom"]
        )
    }

    func testActiveProfileIsNeverContentFilteredForLegacyCopy() {
        let suiteName = "PreloadProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var legacyCopy = WebViewPreloadProfile.nativeBridgeDemoPreset
        legacyCopy.id = UUID()
        legacyCopy.name = "Native Bridge Demo Copy"
        PreloadProfileStore.saveActiveProfile(legacyCopy, defaults: defaults)

        // Whatever the user applied stays active and keeps its enabled flag — the active read
        // never swaps it for the default setup.
        let activeProfile = PreloadProfileStore.activeProfile(defaults: defaults)
        XCTAssertEqual(activeProfile.id, legacyCopy.id)
        XCTAssertTrue(activeProfile.isEnabled)
    }

    func testStoreKeepsEditedNativeBridgeDemoCopy() {
        let suiteName = "PreloadProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var editedCopy = WebViewPreloadProfile.nativeBridgeDemoPreset
        editedCopy.id = UUID()
        editedCopy.name = "Native Bridge Demo Copy"
        editedCopy.cookies[0].value = "user-edited-session"
        PreloadProfileStore.saveActiveProfile(editedCopy, defaults: defaults)
        PreloadProfileStore.saveProfiles([editedCopy], defaults: defaults)

        let activeProfile = PreloadProfileStore.activeProfile(defaults: defaults)
        let savedProfiles = PreloadProfileStore.savedProfiles(defaults: defaults)

        XCTAssertEqual(activeProfile.id, editedCopy.id)
        XCTAssertEqual(activeProfile.cookies.first?.value, "user-edited-session")
        XCTAssertEqual(savedProfiles.map(\.name), ["Native Bridge Demo Copy"])
        XCTAssertEqual(savedProfiles.first?.cookies.first?.value, "user-edited-session")
    }

    func testStoreCanSaveNativeBridgeDemoAsOrdinarySavedSetup() {
        let suiteName = "PreloadProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let demoProfile = WebViewPreloadProfile.nativeBridgeDemoPreset

        PreloadProfileStore.upsertSavedProfile(demoProfile, defaults: defaults)
        let profiles = PreloadProfileStore.savedProfiles(defaults: defaults)

        // No forced "Default" entry: the saved list holds only what the user saved.
        XCTAssertEqual(profiles.map(\.name), ["Native Bridge Demo"])
        XCTAssertEqual(profiles[0].id, WebViewPreloadProfile.nativeBridgeDemoPresetID)
    }

    func testSettingsStateStartsEmptySetupWithoutSaving() {
        let suiteName = "PreloadProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var state = PreloadProfileSettingsState()
        state.loadIfNeeded(
            activeProfile: { .empty },
            savedProfiles: { PreloadProfileStore.savedProfiles(defaults: defaults) }
        )

        state.startEmptySetup()

        let savedProfiles = PreloadProfileStore.savedProfiles(defaults: defaults)

        // startEmptySetup only mutates the draft; nothing is persisted, so the saved list
        // stays empty (no forced "Default").
        XCTAssertEqual(savedProfiles, [])
        XCTAssertEqual(state.profile.name, "Untitled Setup")
        XCTAssertFalse(state.profile.isEnabled)
        XCTAssertEqual(state.profile.cookies, [])
        XCTAssertEqual(state.profile.windowItems, [])
        XCTAssertEqual(state.profile.bridgeChannels, [])
        XCTAssertEqual(state.profile.customScripts, [])
    }

    func testActiveProfileRoundTripsAllPreloadCollections() {
        let suiteName = "PreloadProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let profile = WebViewPreloadProfile(
            name: "Round Trip",
            isEnabled: true,
            cookies: [PreloadCookie(name: "session", value: "abc")],
            windowItems: [WindowInjectionItem(name: "app.flag", valueKind: .json, value: "true")],
            bridgeChannels: [
                BridgeChannel(
                    name: "request",
                    responseRules: [
                        BridgeResponseRule(name: "ok", matcher: .jsonPathEquals(path: "payload.ok", value: "true"))
                    ]
                )
            ],
            capturesWindowPostMessage: true,
            customScripts: [PreloadCustomScript(name: "Boot", source: "window.ready = true;")]
        )

        PreloadProfileStore.saveActiveProfile(profile, defaults: defaults)
        let restored = PreloadProfileStore.activeProfile(defaults: defaults)

        XCTAssertEqual(restored, profile)
    }

    func testPreloadSettingsStateDoesNotReloadOverDraftAfterNavigationReturn() {
        var state = PreloadProfileSettingsState()
        var loadCount = 0
        let storedProfile = WebViewPreloadProfile(name: "Stored", isEnabled: true)

        state.loadIfNeeded(
            activeProfile: {
                loadCount += 1
                return storedProfile
            },
            savedProfiles: { [.nativeBridgeDemoPreset] }
        )

        state.profile.cookies.append(PreloadCookie(name: "session", value: "demo"))
        state.profile.windowItems.append(WindowInjectionItem(name: "appVersion", value: "1.0.0"))
        state.profile.bridgeChannels.append(
            BridgeChannel(
                name: "request",
                responseRules: [BridgeResponseRule(name: "Reply", matcher: .any)]
            )
        )
        state.profile.customScripts.append(PreloadCustomScript(name: "Boot", source: "window.ready = true;"))

        state.loadIfNeeded(
            activeProfile: {
                loadCount += 1
                return WebViewPreloadProfile(name: "Reloaded")
            },
            savedProfiles: { [] }
        )

        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(state.profile.name, "Stored")
        XCTAssertEqual(state.profile.cookies.map(\.name), ["session"])
        XCTAssertEqual(state.profile.windowItems.map(\.name), ["appVersion"])
        XCTAssertEqual(state.profile.bridgeChannels.map(\.name), ["request"])
        XCTAssertEqual(state.profile.bridgeChannels.first?.responseRules.map(\.name), ["Reply"])
        XCTAssertEqual(state.profile.customScripts.map(\.name), ["Boot"])
    }

    func testApplyCurrentProfileDoesNotOverwriteMatchingSavedSetup() {
        let suiteName = "PreloadProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let savedProfile = WebViewPreloadProfile(name: "Saved", isEnabled: true)
        PreloadProfileStore.upsertSavedProfile(savedProfile, defaults: defaults)
        var state = PreloadProfileSettingsState()
        state.loadIfNeeded(
            activeProfile: { savedProfile },
            savedProfiles: { PreloadProfileStore.savedProfiles(defaults: defaults) }
        )

        state.profile.cookies.append(PreloadCookie(name: "session", value: "updated"))
        state.applyCurrentProfile(defaults: defaults)

        let activeProfile = PreloadProfileStore.activeProfile(defaults: defaults)
        let savedProfiles = PreloadProfileStore.savedProfiles(defaults: defaults)
        let originalSavedProfile = savedProfiles.first { $0.id == savedProfile.id }

        XCTAssertEqual(activeProfile.cookies.map(\.name), ["session"])
        XCTAssertEqual(originalSavedProfile?.cookies, [])
    }

    func testApplyCurrentProfilePreservesEnabledState() {
        let suiteName = "PreloadProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Apply persists whatever the Enable toggle says — it no longer force-enables. Editing a
        // setup the user disabled from Home keeps it disabled (Home checkmark stays off).
        var offState = PreloadProfileSettingsState()
        offState.loadIfNeeded(
            activeProfile: { WebViewPreloadProfile(name: "Draft", isEnabled: false) },
            savedProfiles: { [] }
        )
        offState.applyCurrentProfile(defaults: defaults)
        XCTAssertEqual(PreloadProfileStore.activeProfile(defaults: defaults).name, "Draft")
        XCTAssertFalse(PreloadProfileStore.activeProfile(defaults: defaults).isEnabled)

        // An enabled draft (e.g. the Enable toggle on) stays enabled.
        var onState = PreloadProfileSettingsState()
        onState.loadIfNeeded(
            activeProfile: { WebViewPreloadProfile(name: "Draft", isEnabled: true) },
            savedProfiles: { [] }
        )
        onState.applyCurrentProfile(defaults: defaults)
        XCTAssertTrue(PreloadProfileStore.activeProfile(defaults: defaults).isEnabled)
    }

    func testApplyingLoadedDemoCopyKeepsHomeCheckmarkChecked() {
        // Regression: loading a saved "Native Bridge Demo Copy" enables the draft and Apply
        // persists it, making the active profile byte-identical to the demo preset. The active
        // read must NOT swap it for the disabled default setup, or the Home checkmark clears
        // even though the user just applied an enabled setup.
        let suiteName = "PreloadProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var savedDemoCopy = WebViewPreloadProfile.nativeBridgeDemoPreset
        savedDemoCopy.id = UUID()
        savedDemoCopy.name = "Native Bridge Demo Copy"
        savedDemoCopy.isEnabled = false
        PreloadProfileStore.saveProfiles([savedDemoCopy, .defaultSavedSetup], defaults: defaults)

        var state = PreloadProfileSettingsState()
        state.loadIfNeeded(
            activeProfile: { .defaultSavedSetup },
            savedProfiles: { PreloadProfileStore.savedProfiles(defaults: defaults) }
        )
        // The loader enables the draft on selection (intent to use).
        var loaded = savedDemoCopy
        loaded.isEnabled = true
        state.profile = loaded

        state.applyCurrentProfile(defaults: defaults)

        let activeProfile = PreloadProfileStore.activeProfile(defaults: defaults)
        XCTAssertEqual(activeProfile.id, savedDemoCopy.id)
        XCTAssertEqual(activeProfile.name, "Native Bridge Demo Copy")
        XCTAssertTrue(activeProfile.isEnabled)
    }

    func testApplyCurrentProfileDoesNotOverwriteSavedDemoSetup() {
        let suiteName = "PreloadProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let savedDemo = PreloadProfileStore.upsertSavedProfile(
            .nativeBridgeDemoPreset,
            defaults: defaults
        )
        var state = PreloadProfileSettingsState()
        state.loadIfNeeded(
            activeProfile: { savedDemo },
            savedProfiles: { PreloadProfileStore.savedProfiles(defaults: defaults) }
        )

        state.profile.cookies.append(PreloadCookie(name: "edited", value: "yes"))
        state.applyCurrentProfile(defaults: defaults)

        let activeProfile = PreloadProfileStore.activeProfile(defaults: defaults)
        let savedProfiles = PreloadProfileStore.savedProfiles(defaults: defaults)

        let persistedDemo = savedProfiles.first { $0.id == savedDemo.id }

        XCTAssertEqual(activeProfile.id, savedDemo.id)
        XCTAssertEqual(activeProfile.cookies.last?.name, "edited")
        XCTAssertEqual(persistedDemo?.cookies.map(\.name), savedDemo.cookies.map(\.name))
        XCTAssertFalse(persistedDemo?.cookies.contains { $0.name == "edited" } ?? true)
    }

    func testDisabledProfileInjectsNoCookies() {
        let url = URL(string: "https://example.com/path")!
        let cookie = PreloadCookie(name: "session", value: "abc")
        let disabled = WebViewPreloadProfile(isEnabled: false, cookies: [cookie])
        let enabled = WebViewPreloadProfile(isEnabled: true, cookies: [cookie])

        // Turning Page Startup Setup off must suppress cookie injection, even when individual
        // cookies are enabled — matching how scripts and bridge channels gate on isEnabled.
        XCTAssertTrue(PreloadCookieApplicator.cookies(for: disabled, url: url).isEmpty)
        XCTAssertEqual(PreloadCookieApplicator.cookies(for: enabled, url: url).map(\.name), ["session"])
    }

    func testEnabledProfileSkipsDisabledCookies() {
        let url = URL(string: "https://example.com/path")!
        let profile = WebViewPreloadProfile(
            isEnabled: true,
            cookies: [
                PreloadCookie(isEnabled: false, name: "off", value: "x"),
                PreloadCookie(isEnabled: true, name: "on", value: "y"),
            ]
        )

        XCTAssertEqual(PreloadCookieApplicator.cookies(for: profile, url: url).map(\.name), ["on"])
    }

    func testCurrentHostCookieUsesNavigationHost() {
        let cookie = PreloadCookie(name: "session", value: "abc", domainMode: .currentHost)
        let httpCookie = PreloadCookieApplicator.makeHTTPCookie(
            from: cookie,
            url: URL(string: "https://example.com/path")!
        )

        XCTAssertEqual(httpCookie?.name, "session")
        XCTAssertEqual(httpCookie?.value, "abc")
        XCTAssertEqual(httpCookie?.domain, "example.com")
        XCTAssertEqual(httpCookie?.path, "/")
    }

    func testCookieSecurePropertyIsOnlySetWhenEnabled() {
        let plainCookie = PreloadCookie(name: "plain", value: "abc", isSecure: false)
        let secureCookie = PreloadCookie(name: "secure", value: "abc", isSecure: true)

        let plainHTTPCookie = PreloadCookieApplicator.makeHTTPCookie(
            from: plainCookie,
            url: URL(string: "https://example.com/path")!
        )
        let secureHTTPCookie = PreloadCookieApplicator.makeHTTPCookie(
            from: secureCookie,
            url: URL(string: "https://example.com/path")!
        )

        XCTAssertNil(plainHTTPCookie?.properties?[.secure])
        XCTAssertEqual(plainHTTPCookie?.isSecure, false)
        XCTAssertEqual(secureHTTPCookie?.properties?[.secure] as? String, "TRUE")
        XCTAssertEqual(secureHTTPCookie?.isSecure, true)
    }

    private func makeJavaScriptContext(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> JSContext {
        let context = JSContext()!
        context.exceptionHandler = { _, exception in
            XCTFail("JavaScript exception: \(exception?.toString() ?? "unknown")", file: file, line: line)
        }
        return context
    }
}
