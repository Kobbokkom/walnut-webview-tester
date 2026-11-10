import CoreFoundation
import Foundation
import WebKit

@MainActor
extension AgentDevTools {
    static let pageInteractionTool = AgentTool.definition(
        "page_interact",
        "Observe and interact with the visible main page in WKWebView. Observe shares text near the viewport after iPhone approval. " +
            "Use move or click_at with viewport CSS coordinates from observe. Press sends a key to the focused element. " +
            "Move, click, fill and press require iPhone approval. After an action, observe again to verify its outcome.",
        [
            "action": options(["observe", "scroll", "fill", "click", "move", "click_at", "press"]),
            "documentId": identifier,
            "direction": options(["up", "down"]),
            "ref": identifier,
            "text": ["type": "string", "maxLength": 1000],
            "x": ["type": "number", "minimum": 0, "description": "Viewport client X in CSS pixels"],
            "y": ["type": "number", "minimum": 0, "description": "Viewport client Y in CSS pixels"],
            "key": ["type": "string", "maxLength": 24, "description": "KeyboardEvent key, e.g. Enter, Escape or a printable character"],
            "code": ["type": "string", "maxLength": 24, "description": "Optional KeyboardEvent physical key code"]
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
        case "fill", "click", "move", "click_at", "press":
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
        request["prepare"] = true
        let text = action == "fill" ? try input.required("text", maxLength: 1000, allowEmpty: true) : nil
        guard (text?.utf16.count ?? 0) <= 1000 else { throw AgentError("The fill text is too long.") }
        request["text"] = text
        switch action {
        case "move", "click_at":
            for axis in ["x", "y"] {
                guard let number = input.values[axis] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, number.doubleValue >= 0 else {
                    throw AgentError("Provide a finite, non-negative viewport \(axis) coordinate.")
                }
                request[axis] = number.doubleValue
            }
        case "press":
            request["key"] = try input.required("key", maxLength: 24)
            request["code"] = try input.string("code", maxLength: 24)
        default:
            request["ref"] = try input.required("ref", maxLength: 48)
        }
        let target = try await interactionResult(request, context)
        try context.checkDocument()
        try checkInteractionResult(target)
        guard let label = target["label"] as? String,
              let site = target["site"] as? String else { throw AgentError("Observe the current page first.") }
        let destination = (target["destination"] as? String).map { "\nDestination: \($0)" } ?? ""
        let question: String
        if let text {
            question = "Fill “\(label)” on \(site) with this value?\(destination)\n\n\(String(reflecting: text))"
        } else if action == "press" {
            question = "Press \(String(reflecting: request["key"] as? String ?? "")) on “\(label)” at \(site)?\(destination)"
        } else if action == "move" {
            question = "Move the pointer over “\(label)” on \(site)?"
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
        try Task.checkCancellation()
        try checkInteractionResult(result)
        if context.navigator.documentID == context.document,
           let point = result["pointer"] as? [String: Double], let x = point["unitX"], let y = point["unitY"] {
            context.navigator.showAgentPointer(x: x, y: y)
        }
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

    private static let pointerKeyboardScript = #"""
        if (['move', 'click_at', 'press'].includes(request.action)) {
            const {action, x, y, key, code} = request;
            const keyboard = action === 'press';
            const hit = keyboard ? document.activeElement ?? document.body : document.elementFromPoint(x, y);
            if (!(hit instanceof Element) || hit.closest('iframe,frame,[inert]')) {
                return error('The action needs a target inside the current viewport.');
            }
            const element = keyboard ? hit : hit.closest(controls) ?? hit;
            const details = describe(element);
            const focusableText = details?.canFill;
            if ((action === 'click_at' && !details) || (keyboard && !details &&
                element.closest('input,textarea,select,[contenteditable],button,a[href],[aria-disabled="true"]'))) {
                return error('This control does not support the requested input.');
            }
            const printable = keyboard && Array.from(key).length === 1 && !/[\u0000-\u001f\u007f]/.test(key);
            if (keyboard && !printable && !['Enter', 'Escape', 'Tab', 'Backspace', 'Delete', 'Home', 'End',
                'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'PageUp', 'PageDown', 'Space'].includes(key)) {
                return error('Use a printable character or a supported navigation or editing key.');
            }
            if (focusableText && keyboard && (printable || ['Space', 'Backspace', 'Delete'].includes(key)) &&
                (element.selectionStart === null || element.selectionEnd === null)) {
                return error('This field does not expose its selection. Use fill to replace its value.');
            }
            const unitX = (x - visual.left) / visual.width;
            const unitY = (y - visual.top) / visual.height;
            if (!keyboard && (unitX < 0 || unitX >= 1 || unitY < 0 || unitY >= 1)) {
                return error('The coordinates are outside the visible viewport.');
            }
            const signature = JSON.stringify([request.documentId, action, location.href, x, y, key, code, details?.signature]);
            if (request.prepare) {
                globalThis.walnutPendingInput = {hit, element, form: element.form, signature};
                return {
                    label: details?.label ?? (keyboard ? 'focused page' : clipped(element.localName, 24)),
                    destination: details?.destination,
                    site: clipped(location.origin, 200)
                };
            }
            const pending = globalThis.walnutPendingInput;
            delete globalThis.walnutPendingInput;
            if (pending?.hit !== hit || pending?.element !== element || pending?.form !== element.form || pending?.signature !== signature) {
                return error('The target changed or is no longer visible. Observe the page again.');
            }
            if (keyboard) {
                const options = {key: key === 'Space' ? ' ' : key, code: code ?? '', bubbles: true, cancelable: true, composed: true};
                const allowed = element.dispatchEvent(new KeyboardEvent('keydown', options));
                const sameFocus = () => document.activeElement === element && element.isConnected &&
                    describe(element)?.signature === details?.signature;
                const edited = allowed && focusableText && sameFocus() ? editWithKey(element, options.key, printable, sameFocus) : false;
                element.dispatchEvent(new KeyboardEvent('keyup', options));
                return {applied: true, edited, defaultPrevented: !allowed};
            }
            const pointer = {x, y, unitX, unitY};
            const options = {clientX: x, clientY: y, view: window, bubbles: true, cancelable: true, composed: true};
            if (action === 'move') {
                hit.dispatchEvent(new PointerEvent('pointermove', {...options, pointerType: 'mouse', pointerId: 1, isPrimary: true}));
                hit.dispatchEvent(new MouseEvent('mousemove', options));
            } else {
                if (focusableText) element.focus({preventScroll: true});
                if (document.elementFromPoint(x, y) !== hit || describe(element)?.signature !== details.signature) {
                    return {applied: false, outcome: 'targetChanged', observeAgain: true, pointer};
                }
                hit.dispatchEvent(new MouseEvent('click', {...options, button: 0, detail: 1}));
            }
            return {applied: true, pointer};
        }

        function editWithKey(element, key, printable, sameFocus) {
            const prototype = element instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
            const value = Object.getOwnPropertyDescriptor(prototype, 'value');
            const previous = value.get.call(element);
            let start = element.selectionStart;
            let end = element.selectionEnd;
            if (start === null || end === null) return false;
            let insert = printable || key === ' ' ? key : '';
            let inputType = 'insertText';
            if (key === 'Backspace' || key === 'Delete') {
                const backwards = key === 'Backspace';
                inputType = backwards ? 'deleteContentBackward' : 'deleteContentForward';
                if (start === end) {
                    if (backwards) start -= Array.from(previous.slice(0, start)).pop()?.length ?? 0;
                    else end += Array.from(previous.slice(end))[0]?.length ?? 0;
                }
            } else if (key === 'Enter' && element instanceof HTMLTextAreaElement) {
                insert = '\n';
                inputType = 'insertLineBreak';
            } else if (!insert) {
                return false;
            }
            const next = previous.slice(0, start) + insert + previous.slice(end);
            if (next === previous || (element.maxLength >= 0 && next.length > element.maxLength)) return false;
            const probe = element.cloneNode(false);
            value.set.call(probe, next);
            if (value.get.call(probe) !== next) return false;
            const options = {data: insert || null, inputType, bubbles: true, composed: true};
            if (!element.dispatchEvent(new InputEvent('beforeinput', {...options, cancelable: true})) ||
                !sameFocus() || value.get.call(element) !== previous) return false;
            value.set.call(element, next);
            if (element.selectionStart !== null) element.setSelectionRange(start + insert.length, start + insert.length);
            element.dispatchEvent(new InputEvent('input', options));
            return value.get.call(element) === next;
        }
    """#

    private static let interactionScript = #"""
    function(request) {
        const controls = 'a[href],button,input,textarea,[role="button"],[role="link"]';
        const error = message => ({error: message});
        const clipped = (text, size = 160) => text.slice(0, size * 2)
            .replace(/[\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/g, ' ')
            .replace(/\s+/g, ' ').trim().slice(0, size).toWellFormed();
        const visual = {
            left: window.visualViewport?.offsetLeft ?? 0,
            top: window.visualViewport?.offsetTop ?? 0,
            width: window.visualViewport?.width ?? innerWidth,
            height: window.visualViewport?.height ?? innerHeight
        };
        const viewport = () => {
            const {scrollX: x, scrollY: y, innerWidth: width, innerHeight: height} = window;
            const end = document.scrollingElement?.scrollHeight ?? height;
            return {x, y, width, height, visual, atTop: y <= 1, atBottom: y + height >= end - 1};
        };
        function inView(rect) {
            const left = Math.max(visual.left, rect.left), right = Math.min(visual.left + visual.width, rect.right);
            const top = Math.max(visual.top, rect.top), bottom = Math.min(visual.top + visual.height, rect.bottom);
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
            const explicitRole = element.getAttribute('role');
            const role = explicitRole || (tag === 'a' ? 'link' : (canFill ? 'textbox' : 'button'));
            const canClick = !sensitive && (tag === 'button' || tag === 'a' ||
                (tag === 'input' && ['button', 'submit', 'reset', 'checkbox', 'radio'].includes(type)) ||
                (tag !== 'input' && tag !== 'textarea' && ['button', 'link'].includes(explicitRole)));
            if (!canFill && !canClick) return null;
            const linkedLabel = (element.getAttribute('aria-labelledby') ?? '').slice(0, 512).trim().split(/\s+/)
                .map(id => document.getElementById(id)?.textContent).filter(Boolean).join(' ');
            let visibleLabel = element.innerText;
            if (tag === 'input' || tag === 'textarea') {
                visibleLabel = ['button', 'submit', 'reset'].includes(type) ? element.value :
                    Array.from(element.labels ?? [], label => label.innerText).join(' ');
            }
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
                const point = Array.from(element.getClientRects())
                    .find(rect => visible(element, rect));
                const [x, y] = inView(point);
                elements.push({ref, ...summary, point: {x, y}});
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
        \#(pointerKeyboardScript)
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
