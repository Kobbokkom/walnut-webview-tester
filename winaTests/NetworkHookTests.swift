//
//  NetworkHookTests.swift
//  winaTests
//
//  Tests for NetworkHook stack trace capture and fetch/XHR interception.
//

import Foundation
import JavaScriptCore
import SwiftUI
import WebKit
import XCTest
@testable import wina

final class NetworkHookTests: XCTestCase {

    @MainActor
    func testNetworkBridgeRetainsBoundedStackThroughCompletion() async throws {
        let navigator = WebViewNavigator()
        let coordinator = WKWebViewCoordinator(isLoading: .constant(false), navigator: navigator)
        let configuration = WKWebViewConfiguration()
        let controller = configuration.userContentController
        controller.add(coordinator, name: "networkRequest")
        defer { controller.removeScriptMessageHandler(forName: "networkRequest") }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        await webView.loadHTMLStringAsync("<p>Network stack fixture</p>", baseURL: nil)
        navigator.attach(to: webView)
        let id = UUID()

        _ = try await webView.evaluateJavaScript("""
            (() => {
                const bridge = window.webkit.messageHandlers.networkRequest;
                const frame = {functionName: 'submitOrder', fileName: 'https://example.invalid/app.js', lineNumber: 14, columnNumber: 9};
                const longFrame = {...frame, functionName: '🧪'.repeat(260), fileName: 'x'.repeat(3000)};
                const id = '\(id.uuidString)';
                bridge.postMessage({action: 'start', id, method: 'POST', url: 'https://example.invalid/order', type: 'fetch',
                    stackFrames: [frame, {...frame, lineNumber: true}, {...frame, columnNumber: 1.5}, ...Array(60).fill(longFrame)],
                    initiatorFunction: 'submitOrder'});
                bridge.postMessage({action: 'complete', id, status: 201, statusText: 'Created'});
                return true;
            })()
            """)
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            navigator.networkManager.requests.contains { $0.id == id && $0.status == 201 }
        }, object: nil)
        await fulfillment(of: [completed], timeout: 3)
        let request = try XCTUnwrap(navigator.networkManager.requests.first { $0.id == id })
        let frames = try XCTUnwrap(request.stackFrames)
        XCTAssertEqual(request.initiatorFunction, "submitOrder")
        XCTAssertEqual(frames.count, 8)
        XCTAssertEqual(frames.first?.lineNumber, 14)
        XCTAssertEqual(frames.first?.columnNumber, 9)
        XCTAssertEqual(frames.last?.functionName.utf16.count, 256)
        XCTAssertEqual(frames.last?.fileName.utf16.count, 2048)

        let result = try await AgentDevTools.call(
            "network_detail", arguments: ["id": id.uuidString, "section": "overview", "raw": true], navigator: navigator,
            storage: StorageManager(), console: ConsoleSession(), authorize: { _ in true }
        )
        let details = try XCTUnwrap(result as? [String: Any])
        XCTAssertNotNil(details["durationMs"] as? Double)
        XCTAssertEqual((details["stack"] as? [[String: Any]])?.first?["functionName"] as? String, "submitOrder")
        withExtendedLifetime(webView) {}
    }

    // MARK: - Helper Functions

    /// Helper to access the network hook script
    private func getNetworkHookScript() -> String {
        return WebViewScripts.networkHook
    }

    /// Normalize escaped JS sequences for easier regex matching.
    private func normalizedScript() -> String {
        getNetworkHookScript()
            .replacingOccurrences(of: "\\\\n", with: "\n")
            .replacingOccurrences(of: "\\\\r", with: "\r")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private func assertScriptMatches(
        _ pattern: String,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let script = normalizedScript()
        let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]
        )
        let range = NSRange(location: 0, length: script.utf16.count)
        let match = regex?.firstMatch(in: script, options: [], range: range)
        XCTAssertNotNil(match, message, file: file, line: line)
    }

    // MARK: - Script Structure Tests

    func testNetworkHookScriptExists() {
        let script = getNetworkHookScript()
        XCTAssertFalse(script.isEmpty, "Network hook script should not be empty")
    }

    func testNetworkHookContainsIIFE() {
        assertScriptMatches(#"\(\s*function\s*\(\)\s*\{"#, message: "Network hook should be an IIFE")
        assertScriptMatches(#"\}\s*\)\s*\(\s*\)"#, message: "Network hook should be a closed IIFE")
    }

    func testNetworkHookPreventsDoubleHooking() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("window.__networkHooked"), "Script should check for previous hooking")
    }

    // MARK: - Stack Trace Capture Tests

    func testNetworkHookContainsCaptureStackTraceFunction() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("function captureStackTrace()"), "Script should have captureStackTrace function")
    }

    func testCaptureStackTraceUsesErrorStack() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("new Error().stack"), "Stack trace should use Error().stack")
    }

    func testStackTraceParsingHandlesNamedFunctions() {
        // Look for regex that matches "at functionName (fileName:line:col)"
        let script = normalizedScript()
        XCTAssertTrue(
            script.contains("line.match(/^at\\s+(.*?)\\s+\\((.+):(\\d+):(\\d+)\\)$/)"),
            "Script should parse named function stack format"
        )
    }

    func testStackTraceParsingHandlesAnonymousFunctions() {
        // Should handle "at https://url:line:col" format
        let script = normalizedScript()
        XCTAssertTrue(
            script.contains("line.match(/^at\\s+(.+):(\\d+):(\\d+)$/)"),
            "Script should parse anonymous function format"
        )
    }

    func testStackTraceExtractsFileName() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("fileName:"), "Script should extract fileName from stack")
    }

    func testStackTraceExtractsFunctionName() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("functionName:"), "Script should extract functionName from stack")
    }

    func testStackTraceExtractsLineNumber() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("lineNumber:"), "Script should extract lineNumber from stack")
    }

    func testStackTraceExtractsColumnNumber() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("columnNumber:"), "Script should extract columnNumber from stack")
    }

    func testStackTraceFrameLimitIs10() {
        assertScriptMatches(#"frames\.length\s*<\s*10"#, message: "Stack trace should be limited to 10 frames")
    }

    func testStackTraceReturnsEmptyArrayOnError() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("return []"), "Stack trace should return empty array on error")
        XCTAssertTrue(script.contains("catch"), "Script should have try-catch for stack parsing")
    }

    // MARK: - Fetch Hook Tests

    func testNetworkHookOverridesFetch() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("window.fetch"), "Script should override window.fetch")
        XCTAssertTrue(script.contains("originalFetch"), "Script should store original fetch")
    }

    func testFetchHookCapturesStackFrames() {
        let script = normalizedScript()
        XCTAssertTrue(
            script.contains("var stackFrames = captureStackTrace()"),
            "Fetch hook should capture stack traces"
        )
        XCTAssertTrue(
            script.contains("stackFrames: stackFrames"),
            "Fetch hook should include captured stack frames in payload"
        )
    }

    func testFetchHookCapturesInitiatorFunction() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("initiatorFunction: stackFrames.length > 0 ? stackFrames[0].functionName : null"),
                     "Fetch hook should capture initiator function")
    }

    func testFetchHookExtractsURL() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("rawUrl") || script.contains("input.url"), "Fetch hook should extract URL")
    }

    func testFetchHookExtractsMethod() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("method") && script.contains("init.method"), "Fetch hook should extract HTTP method")
    }

    func testFetchHookExtractsHeaders() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("init.headers") || script.contains("input.headers"), "Fetch hook should extract headers")
    }

    func testFetchHookExtractsBody() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("init.body") || script.contains("body:"), "Fetch hook should extract request body")
    }

    func testFetchHookDetectsInitBodyWithOwnProperty() {
        let script = getNetworkHookScript()
        XCTAssertTrue(
            script.contains("Object.prototype.hasOwnProperty.call(init, 'body')"),
            "Fetch hook should distinguish explicit init.body from missing body"
        )
    }

    func testFetchHookReadsRequestBodyFromRequestObject() {
        let script = getNetworkHookScript()
        XCTAssertTrue(
            script.contains("input instanceof Request") && script.contains("input.clone()"),
            "Fetch hook should read body when fetch is called with Request input"
        )
    }

    func testFetchHookHandlesAlreadyConsumedRequestBody() {
        let script = getNetworkHookScript()
        XCTAssertTrue(
            script.contains("input.bodyUsed") && script.contains("[Body already consumed]"),
            "Fetch hook should handle Request with already-consumed body safely"
        )
    }

    func testFetchHookParsesMultipartRequestAsFormDataWhenPossible() {
        let script = getNetworkHookScript()
        XCTAssertTrue(
            script.contains("contentType.indexOf('multipart/form-data')") && script.contains("input.clone().formData()"),
            "Fetch hook should try formData parsing for multipart requests"
        )
    }

    func testFetchHookParsesUrlEncodedRequestAsFormDataWhenPossible() {
        let script = getNetworkHookScript()
        XCTAssertTrue(
            script.contains("contentType.indexOf('application/x-www-form-urlencoded')") && script.contains("input.clone().formData()"),
            "Fetch hook should try formData parsing for urlencoded requests"
        )
    }

    func testFetchHookGeneratesRequestID() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("generateId()"), "Fetch hook should generate request ID")
    }

    func testFetchHookSendStartMessage() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("action: 'start'"), "Fetch hook should send start message")
    }

    func testFetchHookSendCompleteMessage() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("action: 'complete'"), "Fetch hook should send complete message")
    }

    func testFetchHookSendErrorMessage() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("action: 'error'"), "Fetch hook should send error message")
    }

    func testFetchHookCapturesResponseStatus() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("response.status"), "Fetch hook should capture response status")
    }

    func testFetchHookCapturesResponseHeaders() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("response.headers"), "Fetch hook should capture response headers")
    }

    func testFetchHookCapturesResponseBody() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("responseText") || script.contains("response.text()"), "Fetch hook should capture response body")
    }

    func testFetchHookUsesWebKitMessageHandler() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("webkit.messageHandlers.networkRequest"), "Fetch hook should use webkit message handler")
    }

    // MARK: - XHR Hook Tests

    func testNetworkHookOverridesXHROpen() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("XHR.prototype.open"), "Script should override XHR.prototype.open")
    }

    func testNetworkHookOverridesXHRSend() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("XHR.prototype.send"), "Script should override XHR.prototype.send")
    }

    func testNetworkHookOverridesXHRSetRequestHeader() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("XHR.prototype.setRequestHeader"), "Script should override XHR.prototype.setRequestHeader")
    }

    func testXHRHookStoresRequestInfo() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("__networkRequestId"), "XHR hook should store request ID")
        XCTAssertTrue(script.contains("__networkMethod"), "XHR hook should store method")
        XCTAssertTrue(script.contains("__networkUrl"), "XHR hook should store URL")
        XCTAssertTrue(script.contains("__networkHeaders"), "XHR hook should store headers")
    }

    func testXHRHookCapturesStackFrames() {
        let script = getNetworkHookScript()
        let sendContent = script.components(separatedBy: "XHR.prototype.send").last ?? ""
        XCTAssertTrue(sendContent.contains("stackFrames:") && sendContent.contains("captureStackTrace()"), "XHR send hook should capture stack traces")
    }

    func testXHRHookCapturesInitiatorFunction() {
        let script = getNetworkHookScript()
        let sendContent = script.components(separatedBy: "XHR.prototype.send").last ?? ""
        XCTAssertTrue(sendContent.contains("initiatorFunction:"), "XHR send hook should capture initiator function")
    }

    func testXHRHookAttachesLoadListener() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("addEventListener('load'"), "XHR hook should attach load listener")
    }

    func testXHRHookAttachesErrorListener() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("addEventListener('error'"), "XHR hook should attach error listener")
    }

    func testXHRHookAttachesAbortListener() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("addEventListener('abort'"), "XHR hook should attach abort listener")
    }

    func testXHRHookAttachesTimeoutListener() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("addEventListener('timeout'"), "XHR hook should attach timeout listener")
    }

    func testXHRHookCapturesResponseHeaders() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("getAllResponseHeaders"), "XHR hook should capture response headers")
    }

    func testXHRHookCapturesResponseStatus() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("xhr.status"), "XHR hook should capture status")
    }

    func testXHRHookCapturesResponseBody() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("xhr.responseText"), "XHR hook should capture response body")
    }

    // MARK: - URL Resolution Tests

    func testNetworkHookContainsResolveURLFunction() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("function resolveURL"), "Script should have URL resolution function")
    }

    func testResolveURLConvertsRelativeToAbsolute() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("new URL("), "Script should use URL constructor for resolution")
        XCTAssertTrue(script.contains("document.baseURI"), "Script should resolve against document.baseURI")
    }

    // MARK: - Header Processing Tests

    func testNetworkHookContainsHeadersToObjectFunction() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("function headersToObject"), "Script should have headers conversion function")
    }

    func testHeadersConversionHandlesHeadersInterface() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("headers.forEach"), "Script should handle Headers interface with forEach")
    }

    func testHeadersConversionHandlesPlainObject() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("typeof headers === 'object'"), "Script should handle plain object headers")
    }

    // MARK: - Body Truncation Tests

    func testNetworkHookContainsTruncateBodyFunction() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("function truncateBody"), "Script should have body truncation function")
    }

    func testBodyTruncationLimit() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("maxLen || 10000") || script.contains("10000"), "Body should be truncated at 10000 characters")
    }

    func testBodyTruncationHandlesStringBody() {
        let script = getNetworkHookScript()
        XCTAssertTrue(
            script.contains("typeof body === 'string'") && script.contains("return body"),
            "Script should keep plain string body without conversion"
        )
    }

    func testBodyTruncationAddsEllipsis() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("... (truncated)"), "Truncated body should indicate truncation")
    }

    func testSerializeBodyHandlesFormData() {
        let script = getNetworkHookScript()
        XCTAssertTrue(
            script.contains("body instanceof FormData") && script.contains("formatFormData(body)"),
            "FormData body should be converted to readable key-value text"
        )
    }

    func testSerializeBodyHandlesReadableStream() {
        let script = getNetworkHookScript()
        XCTAssertTrue(
            script.contains("body instanceof ReadableStream") && script.contains("return 'ReadableStream'"),
            "ReadableStream body should be represented with a safe placeholder"
        )
    }

    func testSerializeBodyHandlesFileBody() {
        let script = getNetworkHookScript()
        XCTAssertTrue(
            script.contains("body instanceof File") && script.contains("[File:"),
            "File body should include lightweight metadata"
        )
    }

    func testFetchCompleteMessageIncludesImmediateRequestBody() {
        let script = getNetworkHookScript()
        XCTAssertTrue(
            script.contains("requestBody: immediateBody"),
            "Complete payload should include immediate request body when available"
        )
    }

    func testFetchHookSendsRequestBodyBackfillEvent() {
        let script = getNetworkHookScript()
        XCTAssertTrue(
            script.contains("action: 'requestBody'") && script.contains("body: resolvedBody"),
            "Fetch hook should send requestBody backfill event after async extraction"
        )
    }

    func testFetchCompleteDoesNotWaitForRequestBodyPromise() {
        let script = getNetworkHookScript()
        XCTAssertFalse(
            script.contains("Promise.all([responseBodyPromise, requestBodyPromise])"),
            "Complete event should not be blocked by request body extraction"
        )
    }

    // MARK: - UUID Generation Tests

    func testNetworkHookContainsGenerateIdFunction() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("function generateId()"), "Script should have UUID generation function")
    }

    func testUUIDGenerationUsesMathRandom() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("Math.random()"), "UUID generation should use Math.random()")
    }

    func testUUIDGenerationFollowsStandardFormat() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"), "UUID should follow standard UUID v4 format")
    }

    // MARK: - Error Handling Tests

    func testNetworkHookHasTryCatchInFetchHook() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("try") && script.contains("catch"), "Fetch hook should have error handling")
    }

    func testNetworkHookHasTryCatchInXHRHook() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("catch"), "XHR hook should have error handling")
    }

    func testNetworkHookMissingWebKitHandlerDoesNotCrash() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("try"), "Script should wrap webkit message calls in try-catch")
    }

    // MARK: - Data Structure Tests

    func testFetchHookSendsMappedRequestObject() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("action:") && script.contains("id:") && script.contains("method:"),
                     "Fetch hook should send well-formed request object")
    }

    func testXHRHookSendsMappedRequestObject() {
        let script = getNetworkHookScript()
        let xhrPart = script.components(separatedBy: "XHR.prototype.send").last?.components(separatedBy: "addEventListener").first ?? ""
        XCTAssertTrue(xhrPart.contains("action:"), "XHR hook should send well-formed request object")
    }

    func testResponseObjectIncludesStatusAndHeaders() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("status:") && script.contains("statusText:") && script.contains("headers:"),
                     "Response should include status, statusText, and headers")
    }

    // MARK: - Clone and Read Body Tests

    func testFetchHookClonesResponseBeforeReading() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("response.clone()"), "Fetch hook should clone response before reading")
    }

    func testFetchHookReadsBodyAsText() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains(".text()"), "Fetch hook should read body as text")
    }

    func testFetchHookHandlesBodyReadFailure() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("catch"), "Fetch hook should handle text() failure gracefully")
    }

    // MARK: - Integration Tests

    func testNetworkHookDoesNotHookTwice() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("if (window.__networkHooked) return"),
                     "Script should prevent double-hooking to avoid overhead")
    }

    func testNetworkHookPreservesOriginalMethods() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("originalFetch"), "Script should preserve original fetch")
        XCTAssertTrue(script.contains("originalOpen"), "Script should preserve original XHR.open")
        XCTAssertTrue(script.contains("originalSend"), "Script should preserve original XHR.send")
        XCTAssertTrue(script.contains("originalSetRequestHeader"), "Script should preserve original setRequestHeader")
    }

    func testNetworkHookCallsOriginalMethods() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("originalFetch.apply") || script.contains("originalFetch.call"),
                     "Script should call original fetch")
        XCTAssertTrue(script.contains("originalOpen.apply") || script.contains("originalOpen.call"),
                     "Script should call original open")
        XCTAssertTrue(script.contains("originalSend.apply") || script.contains("originalSend.call"),
                     "Script should call original send")
    }

    // MARK: - Stack Trace Edge Cases

    func testStackTraceHandlesEmptyStack() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("|| ''"), "Script should handle undefined stack")
    }

    func testStackTraceStartsAtIndexOne() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("i = 1"), "Stack trace iteration should skip first line (Error constructor)")
    }

    func testStackTraceParsesMultipleFormats() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("match") && script.contains("||"), "Script should try multiple regex patterns")
    }

    // MARK: - Request Type Classification

    func testFetchHookSetsTypeToFetch() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("type: 'fetch'"), "Fetch hook should set request type to 'fetch'")
    }

    func testXHRHookSetsTypeToXHR() {
        let script = getNetworkHookScript()
        XCTAssertTrue(script.contains("type: 'xhr'"), "XHR hook should set request type to 'xhr'")
    }
}

final class XHRCompletionRegressionTests: XCTestCase {
    func testTypedResponsesAlwaysCompleteMetadata() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        var messages = [];
        var window = {fetch: function(){}, webkit:{messageHandlers:{networkRequest:{postMessage:function(m){messages.push(m);}}}}};
        var document = {baseURI:'https://example.com'};
        function XMLHttpRequest(){this.listeners={};this.status=200;this.statusText='OK';this.responseType='';this.response={ok:true};}
        XMLHttpRequest.prototype.open=function(){};
        XMLHttpRequest.prototype.send=function(){};
        XMLHttpRequest.prototype.setRequestHeader=function(){};
        XMLHttpRequest.prototype.getAllResponseHeaders=function(){return 'content-type: application/json';};
        XMLHttpRequest.prototype.addEventListener=function(n,f){(this.listeners[n]||(this.listeners[n]=[])).push(f);};
        XMLHttpRequest.prototype.removeEventListener=function(n,f){
          this.listeners[n]=(this.listeners[n]||[]).filter(function(listener){return listener!==f;});
        };
        Object.defineProperty(XMLHttpRequest.prototype,'responseText',{get:function(){
          if(this.responseType && this.responseType!=='text') throw new Error('InvalidStateError');
          return '{"ok":true}';
        }});
        """)
        context.evaluateScript(WebViewScripts.networkHook)
        XCTAssertNil(context.exception)
        context.evaluateScript("var xhr=new XMLHttpRequest();")
        for type in ["text", "json", "blob", "arraybuffer", "document"] {
            context.evaluateScript("""
            messages=[];
            xhr.open('GET','/data');xhr.responseType='\(type)';xhr.send();
            xhr.listeners.load.forEach(function(listener){listener();});
            """)
            XCTAssertNil(context.exception)
            let completed = context.evaluateScript("messages.filter(function(m){return m.action==='complete' && m.status===200;}).length")?.toInt32()
            XCTAssertEqual(completed, 1, "Expected one completion for \(type)")
            XCTAssertTrue(context.evaluateScript("messages[0].id === messages[1].id")?.toBool() == true)
            XCTAssertTrue(context.evaluateScript("Object.values(xhr.listeners).every(function(list){return list.length===0;})")?.toBool() == true)
        }
    }
}
