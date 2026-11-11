import Foundation
import Security
import WebKit

struct AgentInspectorGrant {
    let id: UUID
    let document: UUID
    let nonce: String
    var authorized = false
}

@MainActor
enum AgentEngineInspection {
    static let contentWorld = WKContentWorld.world(name: "WalnutEngineInspection")
    static let tool = AgentTool.definition(
        "agent_engine_inspection",
        "Authorize and validate the Mac's WebKit inspector for the current WKWebView document. Requires confirmation on the iPhone.",
        [
            "action": AgentDevTools.options(["authorize", "validate", "end"]),
            "grantId": AgentDevTools.identifier,
            "method": AgentDevTools.options(allowedMethods.sorted()),
            "params": ["type": "object"]
        ], required: ["action"]
    )

    static func call(input: AgentDevInput, context: AgentDevContext) async throws -> [String: Any] {
        switch try input.required("action") {
        case "authorize":
            guard input.values["grantId"] == nil, input.values["method"] == nil, input.values["params"] == nil else {
                throw AgentError("Authorize does not take a grant ID, method, or parameters.")
            }
            return try await authorize(context)
        case "validate":
            return try await validate(input, context)
        case "end":
            guard input.values["method"] == nil, input.values["params"] == nil else {
                throw AgentError("End does not take a method or parameters.")
            }
            let id = try input.uuid("grantId")
            if let grant = context.navigator.agentInspectorGrant {
                guard grant.id == id else { throw inactiveGrant }
                revoke(context.navigator)
            }
            return ["ended": true]
        default:
            throw AgentError("Invalid engine inspector action.")
        }
    }

    static func revoke(_ navigator: WebViewNavigator) {
        guard let grant = navigator.agentInspectorGrant else { return }
        navigator.agentInspectorGrant = nil
        removeMarker(grant, from: navigator)
    }

    private static func authorize(_ context: AgentDevContext) async throws -> [String: Any] {
        try context.checkDocument()
        let navigator = context.navigator
        guard navigator.agentInspectorGrant == nil else {
            throw AgentError("End the existing WebKit inspector grant first.")
        }
        guard let bundleId = Bundle.main.bundleIdentifier else {
            throw AgentError("Could not identify the Walnut app for engine inspection.")
        }
        let grant = AgentInspectorGrant(id: UUID(), document: context.document, nonce: try secureNonce())
        navigator.agentInspectorGrant = grant
        var attemptedMarker = false
        var authorized = false
        defer {
            if !authorized {
                if navigator.agentInspectorGrant?.id == grant.id { navigator.agentInspectorGrant = nil }
                if attemptedMarker { removeMarker(grant, from: navigator) }
            }
        }
        try await context.confirm("""
        Allow the connected Mac's WebKit debugger to inspect this test page?

        It can read unredacted page data, scripts, network headers and bodies, and runtime values. Debugger actions can pause JavaScript or change the page. Sensitive commands need a separate confirmation.

        This access ends when the document or connection ends. Shared data may reach the Mac's AI service.
        """)
        guard navigator.agentInspectorGrant?.id == grant.id else { throw inactiveGrant }
        let nonce = JavaScriptLiteral.quoted(grant.nonce)
        attemptedMarker = true
        let result = try await navigator.evaluateJavaScriptReportingErrors("""
        Object.defineProperty(globalThis, '__walnutInspectorNonce', {value: \(nonce), configurable: true});
        globalThis.__walnutInspectorNonce === \(nonce);
        """, contentWorld: contentWorld)
        try context.checkDocument()
        guard result as? Bool == true, navigator.agentInspectorGrant?.id == grant.id else { throw inactiveGrant }
        navigator.agentInspectorGrant?.authorized = true
        authorized = true
        return ["grantId": grant.id.uuidString, "documentId": grant.document.uuidString, "nonce": grant.nonce, "bundleId": bundleId]
    }

    private static func validate(_ input: AgentDevInput, _ context: AgentDevContext) async throws -> [String: Any] {
        let id = try input.uuid("grantId")
        let grant = try currentGrant(id, context)
        if let method = try input.string("method") {
            guard allowedMethods.contains(method) else { throw AgentError("Engine inspector method is unavailable: \(method).") }
            let rawParams = input.values["params"] ?? [:] as [String: Any]
            guard let params = rawParams as? [String: Any], JSONSerialization.isValidJSONObject(params) else {
                throw AgentError("Inspector parameters must be a JSON object.")
            }
            if confirmedMethods.contains(method) {
                try await context.confirm(approvalPrompt(method, params))
                _ = try currentGrant(id, context)
            }
        } else if input.values["params"] != nil {
            throw AgentError("Inspector parameters require a method.")
        }
        return ["valid": true, "grantId": id.uuidString, "documentId": grant.document.uuidString]
    }

    private static func currentGrant(_ id: UUID, _ context: AgentDevContext) throws -> AgentInspectorGrant {
        try context.checkDocument()
        guard let grant = context.navigator.agentInspectorGrant, grant.id == id,
              grant.authorized, grant.document == context.document else { throw inactiveGrant }
        return grant
    }

    private static func removeMarker(_ grant: AgentInspectorGrant, from navigator: WebViewNavigator) {
        Task { @MainActor [weak navigator] in
            guard let navigator, navigator.documentID == grant.document, navigator.isAttached else { return }
            let nonce = JavaScriptLiteral.quoted(grant.nonce)
            _ = try? await navigator.evaluateJavaScriptReportingErrors("""
            if (globalThis.__walnutInspectorNonce === \(nonce)) delete globalThis.__walnutInspectorNonce;
            void 0;
            """, contentWorld: contentWorld)
        }
    }

    private static func secureNonce() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AgentError("Could not create an engine inspector grant.")
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return NSUUID(uuidBytes: bytes).uuidString
    }

    private static func approvalPrompt(_ method: String, _ params: [String: Any]) throws -> String {
        let fields = [
            "Runtime.evaluate": "expression", "Debugger.evaluateOnCallFrame": "expression",
            "Runtime.callFunctionOn": "functionDeclaration", "Debugger.setBreakpoint": "condition",
            "Debugger.setBreakpointByUrl": "condition", "DOM.setOuterHTML": "outerHTML",
            "CSS.setStyleSheetText": "text", "CSS.addRule": "ruleText"
        ]
        var prompt = "Allow the Mac's WebKit debugger to run \(method) in this test page?"
        var arguments = params
        if let field = fields[method], let code = params[field] as? String {
            arguments.removeValue(forKey: field)
            prompt += "\n\n\(field):\n\(code)"
        }
        if !arguments.isEmpty {
            let data = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys, .withoutEscapingSlashes])
            guard let text = String(bytes: data, encoding: .utf8) else {
                throw AgentError("Could not display the inspector parameters for approval.")
            }
            prompt += "\n\n" + text
        }
        return prompt
    }

    private static let inactiveGrant = AgentError("The WebKit inspector grant is no longer active for this document.")

    // Keep this CDP allowlist aligned with the Mac adapter. No browser-level or target-switch commands.
    private static let readMethods: Set<String> = [
        "Debugger.enable", "Debugger.getScriptSource",
        "Runtime.enable", "Runtime.disable", "Runtime.getProperties", "Runtime.releaseObject", "Runtime.releaseObjectGroup",
        "DOM.getDocument", "DOM.requestChildNodes", "DOM.querySelector", "DOM.querySelectorAll", "DOM.getOuterHTML",
        "DOM.resolveNode", "DOM.describeNode", "DOM.getNodeForLocation", "DOM.getBoxModel", "DOM.getContentQuads",
        "CSS.enable", "CSS.disable", "CSS.getComputedStyleForNode", "CSS.getMatchedStylesForNode", "CSS.getStyleSheetText",
        "Network.enable", "Network.getResponseBody",
        "HeapProfiler.enable", "HeapProfiler.disable", "HeapProfiler.getObjectByHeapObjectId",
        "Page.getResourceTree", "Page.getFrameTree", "Page.getResourceContent", "Page.getLayoutMetrics"
    ]

    private static let confirmedMethods: Set<String> = [
        "Debugger.disable", "Debugger.pause", "Debugger.resume", "Debugger.stepInto", "Debugger.stepOver", "Debugger.stepOut",
        "Debugger.setBreakpoint", "Debugger.setBreakpointByUrl", "Debugger.removeBreakpoint",
        "Debugger.setPauseOnExceptions", "Debugger.evaluateOnCallFrame", "Runtime.evaluate", "Runtime.callFunctionOn",
        "DOM.setOuterHTML", "DOM.setAttributeValue", "DOM.removeAttribute", "DOM.removeNode", "DOM.scrollIntoViewIfNeeded",
        "CSS.setStyleSheetText", "CSS.addRule", "Network.disable", "Network.setCacheDisabled", "Network.setExtraHTTPHeaders",
        "Fetch.enable", "Fetch.disable", "Fetch.continueRequest", "Fetch.continueResponse", "Fetch.fulfillRequest", "Fetch.failRequest",
        "Profiler.start", "Profiler.stop", "HeapProfiler.collectGarbage", "HeapProfiler.takeHeapSnapshot",
        "HeapProfiler.startTrackingHeapObjects", "HeapProfiler.stopTrackingHeapObjects",
        "Page.captureScreenshot"
    ]

    private static let allowedMethods = readMethods.union(confirmedMethods)
}
