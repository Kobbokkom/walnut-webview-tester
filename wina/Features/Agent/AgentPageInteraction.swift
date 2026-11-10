import Foundation
import WebKit

@MainActor
extension AgentDevTools {
    static let pageInteractionTool = AgentTool.definition(
        "page_interact",
        "Observe and interact with the visible main page in WKWebView. Observe shares text near the viewport after iPhone approval. " +
            "Scroll and pass the current documentId, then observe again. Click and fill require an observed ref and iPhone approval. " +
            "After an action, observe again to verify its outcome.",
        [
            "action": options(["observe", "scroll", "fill", "click"]),
            "documentId": identifier,
            "direction": options(["up", "down"]),
            "ref": identifier,
            "text": ["type": "string", "maxLength": 1000]
        ],
        required: ["action"]
    )

    private static let interactionWorld = WKContentWorld.world(name: "WalnutPageInteraction")

    static func interactWithPage(_ input: AgentDevInput, _ context: AgentDevContext) async throws -> [String: Any] {
        let action = try input.required("action")
        if action != "observe" || input.values["documentId"] != nil {
            guard try input.uuid("documentId") == context.document else {
                throw AgentError("The interaction belongs to another document. Observe the current page first.")
            }
        }
        try checkInteractionDocument(context)
        let document = context.document.uuidString
        var request: [String: Any] = ["action": action, "documentId": document]
        switch action {
        case "observe":
            try await context.confirm("Share page text near the current viewport and visible controls with the Mac?")
            request["observationId"] = UUID().uuidString
        case "scroll":
            let direction = try input.required("direction")
            guard ["up", "down"].contains(direction) else { throw AgentError("Scroll direction must be up or down.") }
            request["direction"] = direction
        case "fill", "click":
            return try await performPageInteraction(input, context, request: request, action: action)
        default:
            throw AgentError("Invalid page interaction action.")
        }
        try checkInteractionDocument(context)
        var result = try await interactionResult(request, context)
        try context.checkDocument()
        try checkInteractionResult(result)
        result["documentId"] = document
        return result
    }

    private static func performPageInteraction(
        _ input: AgentDevInput, _ context: AgentDevContext, request: [String: Any], action: String
    ) async throws -> [String: Any] {
        var request = request
        request["ref"] = try input.required("ref", maxLength: 48)
        request["prepare"] = true
        let text = action == "fill" ? try input.required("text", maxLength: 1000, allowEmpty: true) : nil
        guard (text?.utf16.count ?? 0) <= 1000 else { throw AgentError("The fill text is too long.") }
        request["text"] = text
        let target = try await interactionResult(request, context)
        try context.checkDocument()
        try checkInteractionResult(target)
        guard let label = target["label"] as? String,
              let site = target["site"] as? String else { throw AgentError("Observe the current page first.") }
        let destination = (target["destination"] as? String).map { "\nDestination: \($0)" } ?? ""
        let question: String
        if let text {
            question = "Fill “\(label)” on \(site) with this value?\(destination)\n\n\(String(reflecting: text))"
        } else {
            question = "Click “\(label)” on \(site)?\(destination)"
        }
        try await context.confirm(question)
        try checkInteractionDocument(context)
        request["prepare"] = false

        // A click can navigate before WebKit returns its reply. Do not retry an ambiguous side effect.
        guard var result = try? await interactionResult(request, context) else {
            return ["documentId": context.document.uuidString, "outcome": "unknown", "observeAgain": true]
        }
        try checkInteractionResult(result)
        result["documentId"] = context.document.uuidString
        return result
    }

    private static func checkInteractionDocument(_ context: AgentDevContext) throws {
        try context.checkDocument()
        guard !context.navigator.agentIsLoading else { throw AgentError("Wait for the current page to finish loading.") }
    }

    private static func interactionResult(_ request: [String: Any], _ context: AgentDevContext) async throws -> [String: Any] {
        let input = try JSONSerialization.data(withJSONObject: request)
        guard let json = String(bytes: input, encoding: .utf8) else { throw AgentError("Could not encode the page interaction.") }
        let script = "JSON.stringify((\(interactionScript))(\(json)))"
        let value = try await context.navigator.evaluateJavaScriptReportingErrors(script, contentWorld: interactionWorld)
        guard let result = try parseJSON(value) as? [String: Any] else {
            throw AgentError("Invalid response from the page.")
        }
        return result
    }

    private static func checkInteractionResult(_ result: [String: Any]) throws {
        if let error = result["error"] as? String { throw AgentError(error) }
    }

    private static let interactionScript = #"""
    function(request) {
        const controls = 'a[href],button,input,textarea,[role="button"],[role="link"]';
        const error = message => ({error: message});
        const clipped = (text, size = 160) => text.slice(0, size * 2)
            .replace(/[\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/g, ' ')
            .replace(/\s+/g, ' ').trim().slice(0, size).toWellFormed();
        const viewport = () => {
            const {scrollX: x, scrollY: y, innerWidth: width, innerHeight: height} = window;
            const end = document.scrollingElement?.scrollHeight ?? height;
            return {x, y, width, height, atTop: y <= 1, atBottom: y + height >= end - 1};
        };
        function inView(rect) {
            const left = Math.max(0, rect.left), right = Math.min(innerWidth, rect.right);
            const top = Math.max(0, rect.top), bottom = Math.min(innerHeight, rect.bottom);
            return right > left && bottom > top ? [(left + right) / 2, (top + bottom) / 2] : null;
        }
        function visible(element, rect) {
            const point = inView(rect);
            if (!point || !element.checkVisibility({checkOpacity: true, checkVisibilityCSS: true})) return false;
            return element.contains(document.elementFromPoint(...point));
        }
        function describe(element) {
            if (!(element instanceof HTMLElement) || !element.isConnected || element.ownerDocument !== document ||
                element.closest('[inert],[aria-disabled="true"],[contenteditable]') || element.matches(':disabled') ||
                !Array.from(element.getClientRects()).some(rect => visible(element, rect))) return null;
            const tag = element.localName;
            const type = element instanceof HTMLInputElement || element instanceof HTMLButtonElement ? element.type : '';
            const autocomplete = (element.getAttribute('autocomplete') ?? '').toLowerCase().split(/\s+/);
            const sensitive = autocomplete.some(value => value === 'one-time-code' || value.endsWith('-password') || value.startsWith('cc-'));
            const canFill = !sensitive && !element.readOnly && (tag === 'textarea' ||
                (tag === 'input' && ['text', 'search', 'email', 'url', 'tel'].includes(type)));
            const role = element.getAttribute('role') || (tag === 'a' ? 'link' : (canFill ? 'textbox' : 'button'));
            const canClick = !sensitive && (tag === 'button' || tag === 'a' ||
                (tag === 'input' && ['button', 'submit', 'reset', 'checkbox', 'radio'].includes(type)) ||
                (tag !== 'input' && tag !== 'textarea' && ['button', 'link'].includes(role)));
            if (!canFill && !canClick) return null;
            const linkedLabel = (element.getAttribute('aria-labelledby') ?? '').slice(0, 512).trim().split(/\s+/)
                .map(id => document.getElementById(id)?.textContent).filter(Boolean).join(' ');
            const visibleLabel = canClick ? (tag === 'input' ? element.value : element.innerText) :
                Array.from(element.labels ?? []).map(item => item.innerText).join(' ');
            const label = clipped(visibleLabel || linkedLabel || element.getAttribute('aria-label') ||
                (canFill ? element.placeholder : '') ||
                element.title || (canFill ? 'Text field' : role));
            const form = canFill || type === 'submit' ? element.form : null;
            const url = tag === 'a' ? element.href : form ?
                (element.hasAttribute('formaction') ? element.formAction : form.action) : '';
            const method = form ? (element.getAttribute('formmethod') || form.method) : '';
            const target = tag === 'a' ? element.target : form ?
                (element.hasAttribute('formtarget') ? element.formTarget : form.target) : '';
            let destination = null;
            if (url) {
                try { destination = new URL(url, document.baseURI); }
                catch { return null; }
            }
            if (destination && !['http:', 'https:'].includes(destination.protocol)) return null;
            return {
                label, role: clipped(role, 24), canFill, canClick,
                destination: destination ? clipped(destination.origin + destination.pathname, 200) : null,
                signature: JSON.stringify([location.href, tag, type, label, role, canFill, canClick,
                    element.maxLength, element.multiple, url, method, target])
            };
        }
        function visibleText() {
            if (!document.body) return '';
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            const range = document.createRange();
            const chunks = [];
            let length = 0;
            for (let scanned = 0, node; scanned < 4000 && length < 1600 && (node = walker.nextNode()); scanned++) {
                const parent = node.parentElement;
                if (!parent || parent.closest('script,style,textarea,select,[contenteditable]')) continue;
                const value = clipped(node.textContent, Math.min(160, 1600 - length));
                if (!value) continue;
                range.selectNodeContents(node);
                if (!Array.from(range.getClientRects()).some(rect => visible(parent, rect))) continue;
                chunks.push(value);
                length += value.length + 1;
            }
            return chunks.join(' ');
        }

        if (request.action === 'observe') {
            const refs = new Map(), elements = [];
            for (const element of document.querySelectorAll(controls)) {
                const data = describe(element);
                if (!data) continue;
                const ref = request.observationId + ':' + elements.length;
                const {signature, ...summary} = data;
                refs.set(ref, {element, signature, form: element.form});
                elements.push({ref, ...summary});
                if (elements.length === 32) break;
            }
            globalThis.walnutInteraction = {documentId: request.documentId, refs};
            return {viewport: viewport(), text: visibleText(), elements};
        }
        if (request.action === 'scroll') {
            const before = viewport();
            // shortcut: scroll the main document only, add nested scroll regions when needed.
            window.scrollBy({top: Math.max(1, Math.floor(before.height * 0.8)) * (request.direction === 'up' ? -1 : 1),
                behavior: 'instant'});
            const after = viewport();
            return {before, after, moved: before.y !== after.y};
        }
        const state = globalThis.walnutInteraction;
        const record = state?.documentId === request.documentId ? state.refs.get(request.ref) : null;
        const data = record ? describe(record.element) : null;
        if (!data || data.signature !== record.signature || record.element.form !== record.form) {
            return error('The control changed or is no longer visible. Observe the page again.');
        }
        if (!(request.action === 'fill' ? data.canFill : data.canClick)) return error('The observed control does not support this action.');
        const element = record.element;
        const text = request.text;
        if (request.action === 'fill') {
            if (element.maxLength >= 0 && text.length > element.maxLength) return error('The value exceeds the field length limit.');
            const probe = document.createElement(element.localName);
            if (element instanceof HTMLInputElement) {
                probe.type = element.type;
                probe.multiple = element.multiple;
            }
            probe.value = text;
            if (probe.value !== text) return error('The field would alter this value. Use text supported by this field.');
        }
        if (request.prepare) return {label: data.label, destination: data.destination, site: clipped(location.origin, 200)};

        state.refs.delete(request.ref);
        if (request.action === 'click') {
            HTMLElement.prototype.click.call(element);
        } else {
            const page = location.href;
            const prototype = element instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
            const value = Object.getOwnPropertyDescriptor(prototype, 'value');
            const previous = value.get.call(element);
            value.set.call(element, text);
            if (value.get.call(element) !== text) {
                value.set.call(element, previous);
                return error('The field did not accept this value.');
            }
            element.dispatchEvent(new InputEvent('input', {bubbles: true, composed: true, inputType: 'insertReplacementText'}));
            element.dispatchEvent(new Event('change', {bubbles: true}));
            if (!element.isConnected || element.ownerDocument !== document || location.href !== page) {
                return {outcome: 'unknown', observeAgain: true};
            }
            if (value.get.call(element) !== text) {
                return {applied: false, outcome: 'pageChangedValue', observeAgain: true};
            }
        }
        return {applied: true};
    }
    """#
}
