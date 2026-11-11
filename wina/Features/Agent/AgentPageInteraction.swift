import CoreFoundation
import Foundation
import WebKit

@MainActor
extension AgentDevTools {
    static let pageInteractionTool = AgentTool.definition(
        "page_interact",
        "Observe and interact with the visible page or a same-origin frame in WKWebView. Observe shares text near the viewport after iPhone approval. " +
            "Use move or click_at with viewport CSS coordinates from observe. Press sends a key to the focused element. " +
            "Use select with optionIndexes or unique values returned by observe. Move, click, fill, select and press require iPhone approval. " +
            "Top-level document scroll reports settled=false if WebKit did not confirm the requested offset before the timeout. " +
            "After an action, observe again to verify its outcome.",
        [
            "action": options(["observe", "scroll", "fill", "select", "click", "move", "click_at", "press"]),
            "documentId": identifier,
            "framePath": [
                "type": "array", "items": query, "maxItems": 8,
                "description": "CSS frame selectors from the main document to a same-origin frame"
            ] as [String: Any],
            "frameDocumentId": identifier,
            "optionOffset": [
                "type": "integer", "minimum": 0, "maximum": 100000,
                "description": "First select option to include in observe. Follow nextOptionOffset."
            ] as [String: Any],
            "direction": options(["up", "down"]),
            "ref": identifier,
            "text": ["type": "string", "maxLength": 1000],
            "values": ["type": "array", "items": ["type": "string", "maxLength": 1000], "maxItems": 32] as [String: Any],
            "optionIndexes": [
                "type": "array", "items": ["type": "integer", "minimum": 0, "maximum": Int32.max], "maxItems": 32,
                "description": "Zero-based option indexes returned by observe. Provide optionIndexes or values."
            ] as [String: Any],
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
        if let frames = input.values["framePath"] {
            guard let frames = frames as? [String], frames.count <= 8,
                  frames.allSatisfy({ !$0.isEmpty && $0.utf16.count <= 256 }) else {
                throw AgentError("Provide up to eight frame selectors, each at most 256 characters.")
            }
            request["framePath"] = frames
        }
        request["frameDocumentId"] = try input.string("frameDocumentId", maxLength: 48)
        switch action {
        case "observe":
            try await context.confirm("Share page text near the current viewport and visible controls with the Mac?")
            request["observationId"] = UUID().uuidString
            request["optionOffset"] = try input.int("optionOffset", default: 0, range: 0...100_000)
        case "scroll":
            let direction = try input.required("direction")
            guard ["up", "down"].contains(direction) else { throw AgentError("Scroll direction must be up or down.") }
            request["direction"] = direction
            request["ref"] = try input.string("ref", maxLength: 48)
        case "fill", "select", "click", "move", "click_at", "press":
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
        if action == "select" {
            let selection = try selectionArguments(input)
            request[selection.key] = selection.value
        }
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
        } else if action == "select" {
            guard let options = target["selectedOptions"] as? [[String: Any]] else {
                throw AgentError("Could not inspect the selected options.")
            }
            let choices = try options.map { option -> String in
                guard let index = option["index"] as? Int, let label = option["label"] as? String,
                      let value = option["value"] as? String else { throw AgentError("Could not inspect the selected option.") }
                let suffix = option["valueTruncated"] as? Bool == true ? " (value truncated)" : ""
                return "[\(index)] \(String(reflecting: label)) (value \(String(reflecting: value)))\(suffix)"
            }
            let summary = choices.isEmpty ? "Clear the selection." : choices.joined(separator: "\n")
            question = "Change the selection in “\(label)” on \(site)?\(destination)\n\n\(summary)"
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

    private static func selectionArguments(_ input: AgentDevInput) throws -> (key: String, value: Any) {
        if let rawIndexes = input.values["optionIndexes"] {
            guard input.values["values"] == nil else { throw AgentError("Use either optionIndexes or values for a selection.") }
            guard let numbers = rawIndexes as? [NSNumber], numbers.count <= 32 else {
                throw AgentError("Provide up to 32 distinct non-negative option indexes.")
            }
            let indexes = numbers.compactMap { number -> Int? in
                guard CFGetTypeID(number) != CFBooleanGetTypeID(), let index = number as? Int,
                      (0...Int(Int32.max)).contains(index) else { return nil }
                return index
            }
            guard indexes.count == numbers.count, Set(indexes).count == indexes.count else {
                throw AgentError("Provide up to 32 distinct non-negative option indexes.")
            }
            return ("optionIndexes", indexes)
        }
        guard let values = input.values["values"] as? [String], values.count <= 32,
              values.allSatisfy({ $0.utf16.count <= 1000 }), Set(values.map { Data($0.utf8) }).count == values.count else {
            throw AgentError("Provide up to 32 distinct option values, each at most 1000 characters, or use optionIndexes.")
        }
        return ("values", values)
    }

    private static func checkInteractionDocument(_ context: AgentDevContext) throws {
        try context.checkDocument()
        guard !context.navigator.agentIsLoading else { throw AgentError("Wait for the current page to finish loading.") }
    }

    private static func interactionResult(_ request: [String: Any], _ context: AgentDevContext) async throws -> [String: Any] {
        let input = try JSONSerialization.data(withJSONObject: request)
        guard let json = String(bytes: input, encoding: .utf8) else { throw AgentError("Could not encode the page interaction.") }
        let expression = "(\(interactionScript))(\(json))"
        let isDocumentScroll = request["action"] as? String == "scroll" &&
            (request["ref"] as? String)?.isEmpty != false && (request["framePath"] as? [String])?.isEmpty != false
        let value: Any?
        if isDocumentScroll {
            let runID = context.navigator.agentNavigation.runID
            value = try await context.navigator.callAsyncJavaScriptReportingErrors(
                "return JSON.stringify(await \(expression));", contentWorld: interactionWorld
            )
            try checkInteractionDocument(context)
            guard context.navigator.agentNavigation.runID == runID else {
                throw AgentError("A different navigation interrupted the scroll. Observe the current page first.")
            }
        } else {
            value = try await context.navigator.evaluateJavaScriptReportingErrors(
                "JSON.stringify(\(expression))", contentWorld: interactionWorld
            )
        }
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
            if (keyboard && ancestors.length && (!frameHasFocus() ||
                !Array.from(element.getClientRects()).some(rect => visible(element, rect)))) {
                return error('Focus a visible control in the frame before sending a key.');
            }
            const details = describe(element);
            const focusableText = details?.canFill;
            const editableWithKey = focusableText && !element.isContentEditable;
            const eligibleInput = details?.canFill || details?.canSelect || details?.canClick;
            if ((action === 'click_at' && !eligibleInput) || (keyboard && !eligibleInput &&
                (details || element.closest('input,textarea,select,[contenteditable],button,a[href],[aria-disabled="true"]')))) {
                return error('This control does not support the requested input.');
            }
            const printable = keyboard && Array.from(key).length === 1 && !/[\u0000-\u001f\u007f]/.test(key);
            if (keyboard && !printable && !['Enter', 'Escape', 'Tab', 'Backspace', 'Delete', 'Home', 'End',
                'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'PageUp', 'PageDown', 'Space'].includes(key)) {
                return error('Use a printable character or a supported navigation or editing key.');
            }
            if (editableWithKey && keyboard && (printable || ['Space', 'Backspace', 'Delete'].includes(key)) &&
                (element.selectionStart === null || element.selectionEnd === null)) {
                return error('This field does not expose its selection. Use fill to replace its value.');
            }
            if (keyboard && element.isContentEditable && (printable || ['Space', 'Backspace', 'Delete'].includes(key))) {
                return error('Use fill to replace contenteditable text. Editing keys require a native selection.');
            }
            let point = keyboard ? null : rootPoint(x, y);
            if (!keyboard && (!containsPoint(visual, x, y) || !point)) {
                return error('The coordinates are outside the visible viewport or the frame is covered.');
            }
            const signature = JSON.stringify([request.documentId, action, location.href, x, y, key, code, details?.signature]);
            if (request.prepare) {
                globalThis.walnutPendingInput = {hit, element, document, form: element.form, signature};
                return {
                    label: details?.label ?? (keyboard ? 'focused page' : clipped(element.localName, 24)),
                    destination: details?.destination,
                    site: clipped(location.origin, 200)
                };
            }
            const pending = globalThis.walnutPendingInput;
            delete globalThis.walnutPendingInput;
            if (pending?.hit !== hit || pending?.element !== element || pending?.document !== document ||
                pending?.form !== element.form || pending?.signature !== signature) {
                return error('The target changed or is no longer visible. Observe the page again.');
            }
            if (keyboard) {
                const options = {key: key === 'Space' ? ' ' : key, code: code ?? '', bubbles: true, cancelable: true, composed: true};
                const allowed = element.dispatchEvent(new KeyboardEvent('keydown', options));
                const sameFocus = () => frameHasFocus() && ancestors.every(supportsFrameTransform) &&
                    document.activeElement === element && element.isConnected && describe(element)?.signature === details?.signature;
                const edited = allowed && editableWithKey && sameFocus() ? editWithKey(element, options.key, printable, sameFocus) : false;
                element.dispatchEvent(new KeyboardEvent('keyup', options));
                return {applied: true, edited, defaultPrevented: !allowed};
            }
            if (action === 'click_at') {
                if (focusableText) element.focus({preventScroll: true});
                point = ancestors.every(supportsFrameTransform) ? rootPoint(x, y) : null;
                if (!point || document.elementFromPoint(x, y) !== hit || describe(element)?.signature !== details.signature) {
                    return {applied: false, outcome: 'targetChanged', observeAgain: true};
                }
            }
            const [rootX, rootY] = point;
            const rootVisual = visualBounds(rootWindow);
            const pointer = {x, y, unitX: (rootX - rootVisual.left) / rootVisual.width,
                unitY: (rootY - rootVisual.top) / rootVisual.height};
            const options = {clientX: x, clientY: y, view: window, bubbles: true, cancelable: true, composed: true};
            if (action === 'move') {
                hit.dispatchEvent(new PointerEvent('pointermove', {...options, pointerType: 'mouse', pointerId: 1, isPrimary: true}));
                hit.dispatchEvent(new MouseEvent('mousemove', options));
            } else {
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
        const controls = 'a[href],button,input,textarea,select,[contenteditable],[role="button"],[role="link"]';
        const error = message => ({error: message});
        const clipped = (text, size = 160) => text.slice(0, size * 2)
            .replace(/[\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/g, ' ')
            .replace(/\s+/g, ' ').trim().slice(0, size).toWellFormed();
        const rootWindow = globalThis.window;
        let document = globalThis.document;
        const ancestors = [];
        function supportsFrameTransform(frame) {
            const view = frame.ownerDocument.defaultView;
            for (let node = frame; node; node = node.assignedSlot ?? node.parentElement ?? node.getRootNode().host) {
                const style = view.getComputedStyle(node);
                if (style.perspective !== 'none' || (style.offsetPath && style.offsetPath !== 'none')) return false;
                if (style.rotate && style.rotate !== 'none' && Number.parseFloat(style.rotate.trim().split(/\s+/).at(-1)) !== 0) {
                    return false;
                }
                if (style.scale && style.scale !== 'none' && !style.scale.trim().split(/\s+/).every(axis => Number.parseFloat(axis) > 0)) {
                    return false;
                }
                if (style.transform === 'none') continue;
                const matrix = new view.DOMMatrixReadOnly(style.transform);
                if (!matrix.is2D || matrix.b !== 0 || matrix.c !== 0 || matrix.a <= 0 || matrix.d <= 0) return false;
            }
            return true;
        }
        for (const selector of request.framePath ?? []) {
            let frame;
            try { frame = document.querySelector(selector); }
            catch { return error('The frame selector is invalid.'); }
            if (!frame || !['iframe', 'frame'].includes(frame.localName)) return error('The frame selector did not match a frame.');
            let next;
            try { next = frame.contentDocument; }
            catch { return error('This frame is not same-origin and cannot be inspected.'); }
            if (!next?.defaultView || next.readyState !== 'complete') return error('The frame is inaccessible or still loading.');
            if (!supportsFrameTransform(frame)) {
                return error('The frame or an ancestor uses a transform that cannot be mapped to viewport coordinates.');
            }
            ancestors.push(frame);
            document = next;
        }
        const window = document.defaultView;
        const location = window.location;
        const {HTMLElement, HTMLInputElement, HTMLButtonElement, HTMLTextAreaElement, HTMLSelectElement,
            Element, NodeFilter, KeyboardEvent, MouseEvent, PointerEvent, InputEvent, Event} = window;
        const frameIds = globalThis.walnutFrameIds ??= new WeakMap();
        if (request.action === 'observe' && !frameIds.has(document)) frameIds.set(document, request.observationId);
        const frameDocumentId = frameIds.get(document) ?? request.documentId;
        if (ancestors.length && request.action !== 'observe' && (!frameIds.has(document) || request.frameDocumentId !== frameDocumentId)) {
            return error('The frame document changed. Observe the frame again and use its frameDocumentId.');
        }
        function visualBounds(view) {
            return {
                left: view.visualViewport?.offsetLeft ?? 0,
                top: view.visualViewport?.offsetTop ?? 0,
                width: view.visualViewport?.width ?? view.innerWidth,
                height: view.visualViewport?.height ?? view.innerHeight
            };
        }
        const visual = visualBounds(window);
        function containsPoint(bounds, x, y) {
            return x >= bounds.left && x < bounds.left + bounds.width &&
                y >= bounds.top && y < bounds.top + bounds.height;
        }
        function frameHasFocus() {
            return ancestors.every(frame => frame.ownerDocument.activeElement === frame);
        }
        const viewport = () => {
            const {scrollX: x, scrollY: y, innerWidth: width, innerHeight: height} = window;
            const end = document.scrollingElement?.scrollHeight ?? height;
            return {x, y, width, height, visual: visualBounds(window), atTop: y <= 1, atBottom: y + height >= end - 1};
        };
        function inView(rect) {
            const left = Math.max(visual.left, rect.left), right = Math.min(visual.left + visual.width, rect.right);
            const top = Math.max(visual.top, rect.top), bottom = Math.min(visual.top + visual.height, rect.bottom);
            return right > left && bottom > top ? [(left + right) / 2, (top + bottom) / 2] : null;
        }
        function visible(element, rect) {
            const point = inView(rect);
            if (!point || !element.checkVisibility({checkOpacity: true, checkVisibilityCSS: true})) return false;
            return element.contains(document.elementFromPoint(...point)) && rootPoint(...point) !== null;
        }
        function frameBox(frame, view) {
            const style = view.getComputedStyle(frame);
            const pixels = value => value.endsWith('px') ? Number(value.slice(0, -2)) : NaN;
            const left = pixels(style.borderLeftWidth) + pixels(style.paddingLeft);
            const right = pixels(style.borderRightWidth) + pixels(style.paddingRight);
            const top = pixels(style.borderTopWidth) + pixels(style.paddingTop);
            const bottom = pixels(style.borderBottomWidth) + pixels(style.paddingBottom);
            const borderBox = style.boxSizing === 'border-box';
            const width = pixels(style.width) + (borderBox ? 0 : left + right);
            const height = pixels(style.height) + (borderBox ? 0 : top + bottom);
            if (![left, right, top, bottom, width, height].every(Number.isFinite) || width <= 0 || height <= 0) return null;
            return {left, top, width, height};
        }
        function rootPoint(x, y) {
            for (let index = ancestors.length - 1; index >= 0; index--) {
                const frame = ancestors[index];
                const parent = frame.ownerDocument;
                const bounds = frame.getBoundingClientRect();
                const box = frameBox(frame, parent.defaultView);
                if (!box || bounds.width <= 0 || bounds.height <= 0) return null;
                x = bounds.left + (box.left + x) * bounds.width / box.width;
                y = bounds.top + (box.top + y) * bounds.height / box.height;
                if (!containsPoint(visualBounds(parent.defaultView), x, y) || parent.elementFromPoint(x, y) !== frame ||
                    !frame.checkVisibility({checkOpacity: true, checkVisibilityCSS: true})) return null;
            }
            return [x, y];
        }
        const disabledOption = option => option.disabled || option.parentElement?.disabled === true;
        function describe(element) {
            if (!(element instanceof HTMLElement) || !element.isConnected || element.ownerDocument !== document ||
                element.closest('[inert],[aria-disabled="true"]') || element.matches(':disabled') ||
                !Array.from(element.getClientRects()).some(rect => visible(element, rect))) return null;
            const tag = element.localName;
            const type = element instanceof HTMLInputElement || element instanceof HTMLButtonElement ? element.type : '';
            const autocomplete = (element.getAttribute('autocomplete') ?? '').toLowerCase().split(/\s+/);
            const sensitive = autocomplete.some(value => value === 'one-time-code' || value.endsWith('-password') || value.startsWith('cc-'));
            const editable = element.isContentEditable && !element.parentElement?.isContentEditable &&
                !element.querySelector('input,textarea,select,button,iframe,frame,[contenteditable="false"]');
            const canFill = !sensitive && !element.readOnly && (editable || tag === 'textarea' ||
                (tag === 'input' && ['text', 'search', 'email', 'url', 'tel'].includes(type)));
            const canSelect = !sensitive && tag === 'select';
            const style = window.getComputedStyle(element);
            const canScroll = ['auto', 'scroll'].includes(style.overflowY) && element.scrollHeight > element.clientHeight + 1;
            const explicitRole = element.getAttribute('role');
            const role = explicitRole || (tag === 'a' ? 'link' : canFill ? 'textbox' : canSelect ? 'combobox' : canScroll ? 'region' : 'button');
            const canClick = !sensitive && (tag === 'button' || tag === 'a' ||
                (tag === 'input' && ['button', 'submit', 'reset', 'checkbox', 'radio'].includes(type)) ||
                (tag !== 'input' && tag !== 'textarea' && ['button', 'link'].includes(explicitRole)));
            if (!canFill && !canClick && !canSelect && !canScroll) return null;
            const linkedLabel = (element.getAttribute('aria-labelledby') ?? '').slice(0, 512).trim().split(/\s+/)
                .map(id => document.getElementById(id)?.textContent).filter(Boolean).join(' ');
            let visibleLabel = element.innerText;
            if (tag === 'input' || tag === 'textarea' || canSelect) {
                visibleLabel = ['button', 'submit', 'reset'].includes(type) ? element.value :
                    Array.from(element.labels ?? [], label => label.innerText).join(' ');
            } else if (editable || (canScroll && !canClick)) {
                visibleLabel = '';
            }
            const label = clipped(visibleLabel || linkedLabel || element.getAttribute('aria-label') ||
                (canFill ? element.placeholder : '') ||
                element.title || (canFill ? 'Text field' : canScroll ? 'Scroll region' : role));
            const form = canFill || canSelect || type === 'submit' ? element.form : null;
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
            const optionOffset = request.optionOffset ?? 0;
            const choices = canSelect ? Array.from(element.options).slice(optionOffset, optionOffset + 100).map(option => ({
                index: option.index, value: option.value.length <= 1000 ? option.value : null,
                label: clipped(option.label), disabled: disabledOption(option)
            })) : undefined;
            return {
                label, role: clipped(role, 24), canFill, canClick, canSelect, canScroll,
                ...(canSelect ? {options: choices, multiple: element.multiple, optionCount: element.options.length,
                    ...(optionOffset + 100 < element.options.length ? {nextOptionOffset: optionOffset + 100} : {})} : {}),
                destination: destination ? clipped(destination.origin + destination.pathname, 200) : null,
                signature: JSON.stringify([location.href, tag, type, label, role, canFill, canClick, canSelect, canScroll,
                    element.maxLength, element.multiple, url, method, target,
                    canSelect ? Array.from(element.options, option => [option.value, option.label, option.disabled,
                        option.parentElement?.disabled === true, option.selected]) : null])
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
            const candidates = new Set(document.querySelectorAll(controls));
            for (const element of Array.from(document.querySelectorAll('body *')).slice(0, 4000)) {
                if (element.scrollHeight > element.clientHeight + 1 && ['auto', 'scroll'].includes(window.getComputedStyle(element).overflowY)) {
                    candidates.add(element);
                }
            }
            for (const element of candidates) {
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
            const frames = [];
            for (const frame of document.querySelectorAll('iframe,frame')) {
                if (!Array.from(frame.getClientRects()).some(rect => visible(frame, rect))) continue;
                const path = [];
                for (let node = frame; node instanceof Element; node = node.parentElement) {
                    if (node.id && document.querySelectorAll('#' + window.CSS.escape(node.id)).length === 1) {
                        path.unshift('#' + window.CSS.escape(node.id));
                        break;
                    }
                    const index = Array.from(node.parentElement?.children ?? []).indexOf(node) + 1;
                    path.unshift(node.localName + (index ? ':nth-child(' + index + ')' : ''));
                }
                let accessible = false;
                try { accessible = !!frame.contentDocument?.defaultView; } catch {}
                frames.push({selector: path.join(' > '), title: clipped(frame.title), accessible});
                if (frames.length === 32) break;
            }
            globalThis.walnutInteraction = {documentId: request.documentId, document, refs};
            return {viewport: viewport(), framePath: request.framePath ?? [], frameDocumentId, text: visibleText(), elements, frames};
        }
        if (request.action === 'scroll') {
            if (request.ref) {
                const state = globalThis.walnutInteraction;
                const record = state?.documentId === request.documentId && state.document === document ? state.refs.get(request.ref) : null;
                const data = record ? describe(record.element) : null;
                if (!data?.canScroll || data.signature !== record.signature) return error('The scroll region changed. Observe the page again.');
                const element = record.element;
                const before = {x: element.scrollLeft, y: element.scrollTop, width: element.clientWidth, height: element.clientHeight};
                element.scrollBy({top: Math.max(1, Math.floor(before.height * 0.8)) * (request.direction === 'up' ? -1 : 1), behavior: 'instant'});
                const after = {x: element.scrollLeft, y: element.scrollTop, width: element.clientWidth, height: element.clientHeight};
                return {before, after, moved: before.y !== after.y};
            }
            const before = viewport();
            const step = Math.max(1, Math.floor(before.height * 0.8)) * (request.direction === 'up' ? -1 : 1);
            if (ancestors.length) {
                window.scrollBy({top: step, behavior: 'instant'});
                const after = viewport();
                return {before, after, moved: before.y !== after.y};
            }
            const end = document.scrollingElement?.scrollHeight ?? before.height;
            const target = Math.max(0, Math.min(end - before.height, before.y + step));
            if (target === before.y) return {before, after: before, moved: false, settled: true};
            window.scrollBy({top: target - before.y, behavior: 'instant'});
            // WebKit can briefly report the requested offset before the viewport adopts it.
            return new Promise(resolve => {
                let frame;
                let stable = 0;
                function finish(settled) {
                    window.clearTimeout(timeout);
                    window.cancelAnimationFrame(frame);
                    const after = viewport();
                    resolve({before, after, moved: before.y !== after.y, settled});
                }
                const timeout = window.setTimeout(() => finish(false), 250);
                function sample() {
                    stable = Math.abs(window.scrollY - target) < 1 ? stable + 1 : 0;
                    if (stable >= 2) finish(true);
                    else frame = window.requestAnimationFrame(sample);
                }
                frame = window.requestAnimationFrame(sample);
            });
        }
        \#(pointerKeyboardScript)
        const state = globalThis.walnutInteraction;
        const record = state?.documentId === request.documentId && state.document === document ? state.refs.get(request.ref) : null;
        const data = record ? describe(record.element) : null;
        if (!data || data.signature !== record.signature || record.element.form !== record.form) {
            return error('The control changed or is no longer visible. Observe the page again.');
        }
        if (!(request.action === 'fill' ? data.canFill : request.action === 'select' ? data.canSelect : data.canClick)) {
            return error('The observed control does not support this action.');
        }
        const element = record.element;
        const text = request.text;
        if (request.action === 'fill' && !element.isContentEditable) {
            if (element.maxLength >= 0 && text.length > element.maxLength) return error('The value exceeds the field length limit.');
            const probe = document.createElement(element.localName);
            if (element instanceof HTMLInputElement) {
                probe.type = element.type;
                probe.multiple = element.multiple;
            }
            probe.value = text;
            if (probe.value !== text) return error('The field would alter this value. Use text supported by this field.');
        }
        let selectedOptions;
        if (request.action === 'select') {
            const indexes = request.optionIndexes;
            const requested = indexes ?? request.values;
            if (!element.multiple && requested.length !== 1) return error('A single-select control requires exactly one option.');
            if (indexes) {
                selectedOptions = indexes.map(index => element.options[index]);
            } else {
                const options = Array.from(element.options);
                selectedOptions = [];
                for (const value of requested) {
                    const matches = options.filter(option => option.value === value);
                    if (matches.length > 1) return error('More than one option has this value. Use optionIndexes.');
                    selectedOptions.push(matches[0]);
                }
            }
            if (selectedOptions.some(option => !option || disabledOption(option))) {
                return error('An option is missing or disabled. Observe the select again.');
            }
            if (request.prepare) record.selectedOptions = selectedOptions;
            else if (record.selectedOptions?.length !== selectedOptions.length ||
                selectedOptions.some((option, index) => option !== record.selectedOptions[index])) {
                return error('The selected options changed. Observe the select again.');
            }
        }
        if (request.prepare) {
            return {
                label: data.label, destination: data.destination, site: clipped(location.origin, 200),
                selectedOptions: selectedOptions?.map(option => ({
                    index: option.index, label: clipped(option.label), value: option.value.slice(0, 1000).toWellFormed(),
                    valueTruncated: option.value.length > 1000
                }))
            };
        }

        state.refs.delete(request.ref);
        if (request.action === 'click') {
            HTMLElement.prototype.click.call(element);
        } else if (request.action === 'select') {
            const page = location.href;
            for (const option of element.options) option.selected = selectedOptions.includes(option);
            element.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
            element.dispatchEvent(new Event('change', {bubbles: true}));
            if (!element.isConnected || element.ownerDocument !== document || location.href !== page) {
                return {outcome: 'unknown', observeAgain: true};
            }
            const current = Array.from(element.selectedOptions);
            if (current.length !== selectedOptions.length || selectedOptions.some(option => !current.includes(option))) {
                return {applied: false, outcome: 'pageChangedValue', observeAgain: true};
            }
        } else if (element.isContentEditable) {
            const page = location.href;
            const previous = element.textContent;
            if (!element.dispatchEvent(new InputEvent('beforeinput', {
                bubbles: true, composed: true, cancelable: true, inputType: 'insertReplacementText', data: text
            }))) return {applied: false, outcome: 'defaultPrevented', observeAgain: true};
            if (element.textContent !== previous || !ancestors.every(supportsFrameTransform) || describe(element)?.signature !== data.signature) {
                return {applied: false, outcome: 'targetChanged', observeAgain: true};
            }
            element.textContent = text;
            element.dispatchEvent(new InputEvent('input', {bubbles: true, composed: true, inputType: 'insertReplacementText', data: text}));
            element.dispatchEvent(new Event('change', {bubbles: true}));
            if (!element.isConnected || element.ownerDocument !== document || location.href !== page) {
                return {outcome: 'unknown', observeAgain: true};
            }
            if (element.textContent !== text) return {applied: false, outcome: 'pageChangedValue', observeAgain: true};
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
