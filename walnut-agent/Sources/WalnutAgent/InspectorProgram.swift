enum InspectorProgram {
    static let source = inspectorProgramSource
}

private let inspectorProgramSource = #"""
"""A single, authorized Walnut page's Web Inspector session over stdio."""

import asyncio
import base64
import contextlib
from dataclasses import dataclass
import importlib.metadata
import json
import logging
import re
import signal
import sys
import uuid


PACKAGE_VERSION = "11.51.0"
MAX_COMMAND_BYTES = 256 * 1024
MAX_OUTPUT_BYTES = 8 * 1024 * 1024
MAX_PENDING_COMMANDS = 32
RESERVED_CONTROL_COMMANDS = 4
MAX_FETCH_PAUSES = 1024
COMMAND_REPLY_TIMEOUT = 60
PAUSED_SESSION_TIMEOUT = 10 * 60
EVALUATION_COMMANDS = {"Runtime.evaluate", "Runtime.callFunctionOn"}
BUNDLES = {"com.kobbokkom.wina", "com.kobbokkom.wina.qa"}
PAGE_TYPES = {"WIRTypeWeb", "WIRTypeWebPage", "WIRTypePage"}
AUTHORIZATION_WORLD = "WalnutEngineInspection"
FETCH_ACTIONS = {
    "Fetch.continueRequest": ("url", "method", "headers", "postData"),
    "Fetch.continueResponse": (),
    "Fetch.fulfillRequest": ("responseCode", "responsePhrase", "responseHeaders", "body"),
    "Fetch.failRequest": ("errorReason",),
}
UNBLOCKING_COMMANDS = {
    "Debugger.disable", "Debugger.resume", "Debugger.stepInto", "Debugger.stepOver", "Debugger.stepOut",
    "Debugger.evaluateOnCallFrame", "Fetch.disable", "Network.disable", *FETCH_ACTIONS,
}
INTERCEPTION_COMMANDS = {
    "Network.interceptContinue", "Network.interceptWithRequest", "Network.interceptWithResponse",
    "Network.interceptRequestWithResponse", "Network.interceptRequestWithError",
}
METHODS = {
    "Debugger": (
        "enable disable pause resume stepInto stepOver stepOut setBreakpoint setBreakpointByUrl "
        "removeBreakpoint getScriptSource setPauseOnExceptions evaluateOnCallFrame"
    ),
    "Runtime": "enable disable evaluate callFunctionOn getProperties releaseObject releaseObjectGroup",
    "DOM": (
        "getDocument requestChildNodes querySelector querySelectorAll getOuterHTML setOuterHTML setAttributeValue "
        "removeAttribute removeNode resolveNode describeNode getNodeForLocation getBoxModel getContentQuads "
        "scrollIntoViewIfNeeded"
    ),
    "CSS": "enable disable getComputedStyleForNode getMatchedStylesForNode getStyleSheetText setStyleSheetText addRule",
    "Network": "enable disable getResponseBody setCacheDisabled setExtraHTTPHeaders",
    "Fetch": "enable disable continueRequest continueResponse fulfillRequest failRequest",
    "Profiler": "start stop",
    "HeapProfiler": (
        "enable disable collectGarbage takeHeapSnapshot startTrackingHeapObjects stopTrackingHeapObjects "
        "getObjectByHeapObjectId"
    ),
    "Page": "getResourceTree getFrameTree getResourceContent getLayoutMetrics captureScreenshot",
}
ALLOWED_METHODS = frozenset(f"{domain}.{name}" for domain, names in METHODS.items() for name in names.split())
REVOKED = {"event": "revoked", "reason": "The authorized Walnut document changed."}


class InspectorError(Exception):
    def __init__(self, message, code=-32600):
        super().__init__(message)
        self.code = code


def parse_object(data):
    def reject_duplicates(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate key")
            result[key] = value
        return result

    def reject_constant(_):
        raise ValueError("nonfinite number")

    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=reject_duplicates, parse_constant=reject_constant)
    except (ValueError, RecursionError) as error:
        raise InspectorError("Expected a UTF-8 JSON object.") from error
    if not isinstance(value, dict):
        raise InspectorError("Expected a JSON object.")
    return value


def startup_config(value):
    if set(value) != {"version", "udid", "bundleId", "nonce"} or type(value["version"]) is not int or value["version"] != 1:
        raise InspectorError("Invalid Walnut inspector authorization frame.")
    udid, bundle, nonce = value["udid"], value["bundleId"], value["nonce"]
    if not isinstance(udid, str) or re.fullmatch(r"[A-Fa-f0-9-]{16,64}", udid) is None:
        raise InspectorError("Specify the trusted iPhone's device identifier.")
    if not isinstance(bundle, str) or bundle not in BUNDLES:
        raise InspectorError("Only the Walnut app can be inspected through this session.")
    if not isinstance(nonce, str) or re.fullmatch(r"[A-Za-z0-9_-]{32,128}", nonce) is None:
        raise InspectorError("Invalid Walnut inspector authorization frame.")
    return udid, bundle, nonce


def request_id(value):
    identifier = value.get("id")
    return identifier if type(identifier) is int and 1 <= identifier <= 2_147_483_647 else None


def validate_request(value):
    method, params = value.get("method"), value.get("params", {})
    if request_id(value) is None or set(value) - {"id", "method", "params"} or not isinstance(params, dict):
        raise InspectorError("Expected a CDP command with a positive integer id and object params.")
    if not isinstance(method, str) or method not in ALLOWED_METHODS:
        raise InspectorError("This inspector method is unavailable in Walnut.", -32601)
    return {"id": value["id"], "method": method, "params": params}


async def read_frame(reader):
    try:
        data = await reader.readuntil(b"\n")
    except asyncio.IncompleteReadError as error:
        if error.partial:
            raise InspectorError("Inspector input ended before the command's newline delimiter.") from error
        return None
    except asyncio.LimitOverrunError as error:
        raise InspectorError("Inspector command exceeds 256 KiB.") from error
    data = data.removesuffix(b"\n")
    if len(data) > MAX_COMMAND_BYTES:
        raise InspectorError("Inspector command exceeds 256 KiB.")
    return data


def encode_frame(value, nonce=None):
    try:
        data = json.dumps(value, ensure_ascii=True, allow_nan=False, separators=(",", ":")).encode("utf-8")
    except (TypeError, ValueError, RecursionError) as error:
        raise InspectorError("The inspector returned an invalid protocol message.") from error
    if nonce:
        data = data.replace(nonce.encode("ascii"), b"<redacted>")
    if len(data) > MAX_OUTPUT_BYTES:
        raise InspectorError("Inspector output exceeds 8 MiB. Narrow the request.")
    return data + b"\n"


def emit(value, nonce=None):
    sys.stdout.buffer.write(encode_frame(value, nonce))
    sys.stdout.buffer.flush()


def document_changed(message, top_frame=None):
    method, params = message.get("method"), message.get("params") or {}
    if method in {"Debugger.globalObjectCleared", "Runtime.executionContextsCleared"}:
        return True
    if method == "Page.frameNavigated":
        return not (params.get("frame") or {}).get("parentId")
    if method in {"Page.frameStartedLoading", "Page.frameDetached"}:
        return top_frame is not None and params.get("frameId") == top_frame
    return False


def interception_patterns(params):
    if set(params) - {"patterns", "handleAuthRequests"} or params.get("handleAuthRequests", False) is not False:
        raise InspectorError("WebKit interception does not support authentication challenges.", -32602)
    patterns = params.get("patterns", [{}])
    if not isinstance(patterns, list) or not 1 <= len(patterns) <= 8:
        raise InspectorError("Provide one to eight interception patterns or omit patterns.", -32602)
    result = []
    for pattern in patterns:
        if not isinstance(pattern, dict) or set(pattern) - {"urlPattern", "requestStage"}:
            raise InspectorError("WebKit interception patterns support URL and stage filters.", -32602)
        url, stage = pattern.get("urlPattern", "*"), pattern.get("requestStage", "Request")
        if not isinstance(url, str) or not 1 <= len(url) <= 2048 or stage not in ("Request", "Response"):
            raise InspectorError("Invalid interception URL pattern or request stage.", -32602)
        regex = "^" + re.escape(url).replace("\\*", ".*").replace("\\?", ".") + "$"
        spec = {"url": regex, "stage": stage.lower(), "isRegex": True}
        if spec not in result:
            result.append(spec)
    return result


def validate_fetch_action(method, params):
    request_id = params.get("requestId")
    if not isinstance(request_id, str) or not request_id or set(params) - {"requestId", *FETCH_ACTIONS[method]}:
        raise InspectorError("Unsupported interception parameters. WebKit can continue a response without overrides.", -32602)
    if method == "Fetch.fulfillRequest":
        status = params.get("responseCode")
        if type(status) is not int or not 100 <= status <= 599:
            raise InspectorError("A response status from 100 to 599 is required.", -32602)
    if method == "Fetch.failRequest" and params.get("errorReason") != "Failed":
        raise InspectorError("WebKit interception supports the Failed error reason.", -32602)
    for key in ("url", "method", "responsePhrase"):
        if key in params and not isinstance(params[key], str):
            raise InspectorError("Interception URL, method and response phrase must be strings.", -32602)
    for key in ("postData", "body"):
        if key in params:
            try:
                base64.b64decode(params[key], validate=True)
            except (ValueError, TypeError) as error:
                raise InspectorError("Interception request and response bodies must be Base64 strings.", -32602) from error
    for key in ("headers", "responseHeaders"):
        if key not in params:
            continue
        headers = params[key]
        if not isinstance(headers, list) or any(
            not isinstance(header, dict) or set(header) != {"name", "value"}
            or not isinstance(header["name"], str) or not isinstance(header["value"], str)
            for header in headers
        ):
            raise InspectorError("Interception headers must be a list of name and value strings.", -32602)
        if len({header["name"].lower() for header in headers}) != len(headers):
            raise InspectorError("WebKit interception does not support duplicate header names.", -32602)


def scoped_target_type(base):
    # The pinned bridge normally follows WebKit's new targets and replays debugger setup on them.
    # An authorization here ends with the original document, before any new-target data is sent.
    class ScopedTarget(base):
        revoked = False

        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self.authorization_contexts = set()
            self.document_resource = None
            self.interception_patterns = []
            self.response_interceptions = set()
            for method in ("Fetch.enable", "Fetch.disable", *FETCH_ACTIONS, "Network.disable"):
                self.from_cdp_special_messages_methods[method] = self._acknowledged_interception
            self.from_cdp_special_messages_methods["Page.getResourceContent"] = self._page_get_document_resource

        async def revoke(self, reason=REVOKED["reason"]):
            if not self.revoked:
                self.revoked = True
                await self.output_queue.put({"event": "revoked", "reason": reason})

        def wire_document_changed(self, message, include_nested=False):
            method, params = message.get("method"), message.get("params") or {}
            if method == "Target.targetCreated":
                info = params.get("targetInfo") or {}
                return info.get("type", "page") == "page" and info.get("targetId") != self.target_id
            if method == "Target.didCommitProvisionalTarget":
                return True
            if method == "Target.targetDestroyed":
                return params.get("targetId") == self.target_id
            if include_nested and method == "Target.dispatchMessageFromTarget" and params.get("targetId") in {None, self.target_id}:
                raw = params.get("message")
                if not isinstance(raw, str):
                    return True
                try:
                    decoded = json.loads(raw)
                except ValueError:
                    return True
                return not isinstance(decoded, dict) or document_changed(decoded, self._webkit_frame_id)
            return False

        async def _to_output_queue(self, message):
            if self.wire_document_changed(message):
                await self.revoke()
                return
            params = message.get("params") or {}
            if message.get("method") == "Target.dispatchMessageFromTarget" and params.get("targetId") not in {None, self.target_id}:
                return
            await super()._to_output_queue(message)

        async def _dispatch_target_message(self, message):
            if document_changed(message, self._webkit_frame_id):
                await self.revoke()
                return
            method, params = message.get("method"), message.get("params") or {}
            if method == "Runtime.executionContextCreated":
                context = params.get("context") or {}
                identifier = context.get("id")
                if (
                    context.get("type") == "user" and context.get("name") == AUTHORIZATION_WORLD
                    and self._webkit_frame_id is not None and context.get("frameId") == self._webkit_frame_id
                    and type(identifier) is int and identifier > 0
                ):
                    self.authorization_contexts.add(identifier)
                    if len(self.authorization_contexts) > 1:
                        await self.revoke("More than one authorization context was reported for the Walnut page.")
                    return
            if method == "Network.responseIntercepted" and self._fetch_enabled and isinstance(params.get("requestId"), str):
                if len(self.response_interceptions) >= MAX_FETCH_PAUSES:
                    await self.revoke("The inspector detached after too many intercepted responses were left pending.")
                    return
                self.response_interceptions.add(params["requestId"])
            if not self.revoked or "id" in message:
                await super()._dispatch_target_message(message)

        async def scope_is_current(self):
            # The bridge pauses its receive loop while waiting for internal replies. A navigation
            # can be queued before a command or response even if the dispatcher has not seen it.
            if self.revoked:
                return False
            queued = self.protocol.inspector.session_events(self.session_id)
            if len(queued) > 2048:
                await self.revoke("The inspector detached after too many device messages were queued.")
            elif any(self.wire_document_changed(message, include_nested=True) for message in queued):
                await self.revoke()
            return not self.revoked

        async def wait_for_event_id(self, *args, **kwargs):
            result = await super().wait_for_event_id(*args, **kwargs)
            return result if await self.scope_is_current() else None

        async def _page_get_document_resource(self, message):
            params = message.get("params", {})
            if not isinstance(params, dict) or set(params) != {"frameId", "url"} or not all(isinstance(value, str) for value in params.values()):
                await self._error_response(message, {"code": -32602, "message": "Supply the top-frame id and URL from Page.getResourceTree."})
                return
            if not await self.scope_is_current():
                return
            if params["frameId"] != self._webkit_frame_id or self.document_resource is None or params["url"] != self.document_resource[1]:
                await self._error_response(message, {"code": -32602, "message": "Only the authorized top-frame HTTP(S) document resource can be read."})
                return
            current = await self._document_resource_is_current()
            if self.revoked:
                return
            if not current:
                await self._error_response(message, {"code": -32000, "message": "The top-frame document resource changed. Start a new inspector session."})
                return
            reply = await self.send_message_with_result("Page.getResourceContent", params)
            if not await self.scope_is_current():
                return
            if "error" in reply:
                await self._error_response(message, reply["error"])
                return
            resource = reply.get("result", {})
            content, encoded = resource.get("content"), resource.get("base64Encoded")
            # WebKit can report empty success when it no longer has a resource buffer.
            if not isinstance(content, str) or not content or type(encoded) is not bool:
                await self._error_response(message, {"code": -32000, "message": "WebKit did not return content for the authorized document resource."})
                return
            current = await self._document_resource_is_current()
            if self.revoked:
                return
            if not current:
                await self._error_response(message, {"code": -32000, "message": "The top-frame document resource changed. Start a new inspector session."})
                return
            result = {"content": content, "base64Encoded": encoded, "retrieval": "webkit-resource"}
            try:
                encode_frame({"id": message["id"], "result": result})
            except InspectorError as error:
                await self._error_response(message, {"code": error.code, "message": str(error)})
                return
            await self._result_response(message, result)

        async def _document_resource_is_current(self):
            tree = await self.send_message_with_result("Page.getResourceTree", {})
            if not await self.scope_is_current():
                return False
            frame = tree.get("result", {}).get("frameTree", {}).get("frame", {})
            return frame.get("id") == self._webkit_frame_id and (frame.get("loaderId"), frame.get("url")) == self.document_resource

        async def _send_message_to_target(self, message, target_id=None, record=True):
            if not await self.scope_is_current():
                raise InspectorError("The authorized Walnut document changed.")
            if message.get("method") in INTERCEPTION_COMMANDS and message.get("id", 0) < 0:
                method, params = message["method"], message["params"]
                request_id = params["requestId"]
                if method == "Network.interceptRequestWithResponse":
                    content_type = next((value for name, value in params["headers"].items() if name.lower() == "content-type"), None)
                    mime_type = "text/plain" if content_type is None else content_type.partition(";")[0].strip().lower()
                    if re.fullmatch(r"[!#$%&'+.^_`|~a-z0-9-]+/[!#$%&'+.^_`|~a-z0-9-]+", mime_type) is None or (
                        content_type is not None and any(character in content_type for character in "\r\n\0")
                    ):
                        raise InspectorError("The intercepted response needs a valid Content-Type media type.", -32602)
                    params = {**params, "mimeType": mime_type}
                if request_id in self.response_interceptions:
                    if method == "Network.interceptRequestWithResponse":
                        method = "Network.interceptWithResponse"
                    elif method == "Network.interceptRequestWithError":
                        raise InspectorError("WebKit can fail a request before its response arrives.", -32602)
                await self._interception_ack(method, params)
                self.response_interceptions.discard(request_id)
                return
            return await super()._send_message_to_target(message, target_id=target_id, record=record)

        async def _interception_ack(self, method, params, already=None):
            # The pinned Fetch translator sends negative-id requests and drops their replies.
            # Wait for this one under its internal id and forward the actual engine result.
            if not await self.scope_is_current():
                raise InspectorError("The authorized Walnut document changed.")
            identifier = self.next_internal_id()
            self._waiting_for_id += 1
            try:
                await super()._send_message_to_target({"id": identifier, "method": method, "params": params}, record=False)
                reply = await self.wait_for_event_id(identifier, self.target_id, timeout=4)
            finally:
                self._waiting_for_id -= 1
                self._pending_requests.pop(identifier, None)
            reply = reply or {}
            error = reply.get("error") or {}
            if not error and "result" in reply:
                return
            message = error.get("message")
            if already and isinstance(message, str) and message.endswith(already):
                return
            code = error.get("code")
            raise InspectorError(
                message[:1024] if isinstance(message, str) else "WebKit did not acknowledge the interception command.",
                code if type(code) is int else -32000,
            )

        async def _disable_interception(self):
            await self._interception_ack("Network.setInterceptionEnabled", {"enabled": False}, already="Interception already disabled")
            self._fetch_enabled = False
            self.response_interceptions.clear()
            while self.interception_patterns:
                pattern = self.interception_patterns[-1]
                await self._interception_ack("Network.removeInterception", pattern, already="Missing intercept for given url, given isRegex, and given stage")
                self.interception_patterns.pop()

        async def _enable_interception(self, params):
            patterns = interception_patterns(params)
            if self._fetch_enabled:
                if patterns == self.interception_patterns:
                    return
                raise InspectorError("Disable interception before changing its patterns.", -32602)
            try:
                await self._interception_ack("Network.enable", {}, already="domain already enabled")
                for pattern in patterns:
                    self.interception_patterns.append(pattern)
                    await self._interception_ack("Network.addInterception", pattern)
                await self._interception_ack("Network.setInterceptionEnabled", {"enabled": True})
                self._fetch_enabled = True
            except InspectorError:
                if not self.revoked:
                    try:
                        await self._disable_interception()
                    except InspectorError:
                        await self.revoke("The inspector detached to release requests after interception setup failed.")
                raise

        async def _acknowledged_interception(self, message):
            method, params = message["method"], message.get("params", {})
            try:
                if method == "Fetch.enable":
                    await self._enable_interception(params)
                elif method == "Fetch.disable":
                    if params:
                        raise InspectorError("Fetch.disable does not take parameters.", -32602)
                    await self._disable_interception()
                elif method == "Network.disable":
                    if params:
                        raise InspectorError("Network.disable does not take parameters.", -32602)
                    await self._interception_ack("Network.disable", {})
                    self._fetch_enabled = False
                    self.interception_patterns.clear()
                    self.response_interceptions.clear()
                else:
                    validate_fetch_action(method, params)
                    if method == "Fetch.fulfillRequest" and params["requestId"] in self.response_interceptions and "body" not in params:
                        raise InspectorError("Replacing an intercepted response requires an explicit body. Use Fetch.continueResponse to preserve it.", -32602)
                    translators = {
                        "Fetch.continueRequest": super()._fetch_continue_request,
                        "Fetch.continueResponse": super()._fetch_continue_response,
                        "Fetch.fulfillRequest": super()._fetch_fulfill_request,
                        "Fetch.failRequest": super()._fetch_fail_request,
                    }
                    await translators[method](message)
                    return
            except InspectorError as error:
                await self._error_response(message, {"code": error.code, "message": str(error)})
                return
            await self._simple_response(message, None)

    return ScopedTarget


def owns_page(inspector, candidate, bundle):
    application, page = candidate.application, candidate.page
    host = inspector.connected_application.get(application.host) if application.proxy else application
    return host is not None and host.bundle == bundle and page.type_.value in PAGE_TYPES


async def startup_call(target, method, params):
    await target.send({"id": 0, "method": method, "params": params})
    clock = asyncio.get_running_loop().time
    deadline = clock() + 5
    while not target.revoked:
        message = await asyncio.wait_for(target.receive(), timeout=deadline - clock())
        if message.get("id") == 0:
            return message
    raise InspectorError("The authorized Walnut document changed before the debugger attached.")


async def marker_matches(target, nonce):
    enabled = await startup_call(target, "Runtime.enable", {})
    if "error" in enabled or len(target.authorization_contexts) != 1:
        return False
    context_id = next(iter(target.authorization_contexts))
    reply = await startup_call(target, "Runtime.evaluate", {
        "expression": f"globalThis.__walnutInspectorNonce === {json.dumps(nonce)}",
        "contextId": context_id,
        "returnByValue": True,
        "silent": True,
    })
    if target.revoked or reply.get("result", {}).get("result", {}).get("value") is not True:
        return False
    disabled = await startup_call(target, "Runtime.disable", {})
    # The client must receive its own initial context events when it enables Runtime.
    target._emitted_context_unique_ids.clear()
    return not target.revoked and "error" not in disabled and target.authorization_contexts == {context_id}


async def attach(inspector, bundle, nonce, target_type, protocol_type, stop=None):
    pages = await inspector.get_open_application_pages(timeout=1)
    candidates = [candidate for candidate in pages if owns_page(inspector, candidate, bundle)]
    if len(candidates) > 16:
        raise InspectorError("Too many inspectable Walnut pages. Close unused Walnut windows and retry.")
    matches = []
    selected = None
    try:
        for candidate in candidates:
            if stop is not None and stop.is_set():
                raise asyncio.CancelledError
            application, page = candidate.application, candidate.page
            protocol = protocol_type(inspector, str(uuid.uuid4()).upper(), application, page, method_prefix="")
            target = None
            matched = False
            opening = False

            async def create_target():
                nonlocal target, opening
                if stop is not None and stop.is_set():
                    raise asyncio.CancelledError
                opening = True
                target = await target_type.create(protocol)

            try:
                await asyncio.wait_for(create_target(), timeout=5)
                frame = await startup_call(target, "Page.getFrameTree", {})
                events = await startup_call(target, "Page.enable", {})
                if "error" in frame or "error" in events:
                    continue
                matched = await marker_matches(target, nonce)
                if matched:
                    top = frame.get("result", {}).get("frameTree", {}).get("frame", {})
                    loader, url = top.get("loaderId"), top.get("url")
                    if isinstance(loader, str) and loader and isinstance(url, str) and url.startswith(("http://", "https://")):
                        target.document_resource = (loader, url)
                    matches.append(target)
                    if len(matches) > 1:
                        break
            except (asyncio.TimeoutError, InspectorError):
                pass
            finally:
                if not matched:
                    with contextlib.suppress(Exception):
                        if target is not None:
                            await asyncio.wait_for(target.close(), timeout=3)
                        elif opening:
                            await asyncio.wait_for(inspector.teardown_inspector_socket(protocol.id_, application.id_, page.id_), timeout=3)
        if len(matches) > 1:
            raise InspectorError("More than one Walnut page matched the authorization. Close unused windows and retry.")
        if not matches or matches[0].revoked:
            raise InspectorError("The authorized Walnut page was not found. Keep Walnut open with the approved page visible.")
        selected = matches[0]
        return selected
    finally:
        for target in matches:
            if target is not selected:
                with contextlib.suppress(Exception):
                    await asyncio.wait_for(target.close(), timeout=3)


async def cleanup_target(target, call):
    # A revoked target can already belong to a replacement document. Detach its original WIR
    # socket without sending commands. WebKit's detach disables the debugger and Network agent.
    for method in ("Debugger.resume", "Fetch.disable", "Debugger.disable"):
        if target.revoked:
            break
        with contextlib.suppress(Exception):
            await call({"id": 0, "method": method, "params": {}}, timeout=1)
    with contextlib.suppress(Exception):
        await asyncio.wait_for(target.close(), timeout=3)


@dataclass
class PendingInspectorCommand:
    method: str
    started: float
    continued_fetch: tuple[str, object] | None = None
    timer: asyncio.TimerHandle | None = None
    pause_extended: bool = False


async def relay(reader, target, stop, write):
    loop = asyncio.get_running_loop()
    pending = {}
    drained = asyncio.Event()
    drained.set()
    expired = loop.create_future()
    cleanup_reply = None
    input_closed = False
    debugger_paused = False
    fetch_pauses = {}
    pause_timer = None

    def expire(message):
        if not expired.done():
            expired.set_result(message)

    def arm_reply_timeout(command):
        if command.timer is not None:
            command.timer.cancel()
        deadline = command.started + COMMAND_REPLY_TIMEOUT
        message = "The inspector command timed out. Reconnect to the current page."
        if command.method in EVALUATION_COMMANDS:
            # A paused page may wait through several separate iPhone approvals. The
            # evaluation still has an absolute limit even if it repeatedly pauses.
            limit = command.started + PAUSED_SESSION_TIMEOUT
            if input_closed:
                if command.pause_extended:
                    deadline = min(loop.time() + COMMAND_REPLY_TIMEOUT, limit)
            elif pause_timer is not None:
                command.pause_extended = True
                deadline = limit
                message = "The inspector evaluation stayed pending too long during pauses. Reconnect to the current page."
            else:
                deadline = min(loop.time() + COMMAND_REPLY_TIMEOUT, limit)
        command.timer = loop.call_at(deadline, expire, message)

    def update_pause_timeout():
        nonlocal pause_timer
        paused = debugger_paused or bool(fetch_pauses)
        if input_closed or paused == (pause_timer is not None):
            return
        if paused:
            pause_timer = loop.call_later(
                PAUSED_SESSION_TIMEOUT, expire,
                "The inspector page stayed paused too long. Reconnect to the current page.",
            )
        else:
            pause_timer.cancel()
            pause_timer = None
        for command in pending.values():
            if command.method in EVALUATION_COMMANDS:
                arm_reply_timeout(command)

    async def drain_input():
        nonlocal input_closed
        input_closed = True
        # Give already queued resume/continue commands a short chance to finish an
        # evaluation whose ordinary deadline elapsed while WebKit was paused.
        for command in pending.values():
            if command.method in EVALUATION_COMMANDS:
                arm_reply_timeout(command)
        await drained.wait()

    def observe_event(message):
        nonlocal debugger_paused
        method = message.get("method")
        if method == "Debugger.paused":
            debugger_paused = True
        elif method == "Debugger.resumed":
            debugger_paused = False
        elif method in {"Fetch.requestPaused", "Network.loadingFinished", "Network.loadingFailed"}:
            params = message.get("params")
            identifier = params.get("requestId") if isinstance(params, dict) else None
            if not isinstance(identifier, str) or not identifier:
                return
            if method == "Fetch.requestPaused":
                if identifier not in fetch_pauses and len(fetch_pauses) >= MAX_FETCH_PAUSES:
                    expire("The inspector detached after too many intercepted requests were left pending.")
                    return
                fetch_pauses[identifier] = object()
            else:
                fetch_pauses.pop(identifier, None)
        else:
            return
        update_pause_timeout()

    def observe_success(command):
        nonlocal debugger_paused
        if command.method == "Debugger.disable":
            debugger_paused = False
        elif command.method in {"Fetch.disable", "Network.disable"}:
            fetch_pauses.clear()
        elif command.continued_fetch is not None:
            identifier, pause = command.continued_fetch
            if fetch_pauses.get(identifier) is pause:
                del fetch_pauses[identifier]
        else:
            return
        update_pause_timeout()

    async def cleanup_call(request, timeout):
        nonlocal cleanup_reply
        cleanup_reply = loop.create_future()
        try:
            await target.send(request)
            return await asyncio.wait_for(cleanup_reply, timeout)
        finally:
            cleanup_reply = None

    async def inputs():
        while not stop.is_set() and not target.revoked:
            try:
                data = await read_frame(reader)
            except InspectorError:
                await drain_input()
                raise
            if data is None:
                await drain_input()
                return
            if stop.is_set() or target.revoked:
                return
            identifier = None
            try:
                value = parse_object(data)
                identifier = request_id(value)
                if identifier in pending:
                    identifier = None
                    raise InspectorError("This inspector command id is already pending.")
                command = validate_request(value)
                if command["method"] in EVALUATION_COMMANDS:
                    params = command["params"]
                    if any(type(params.get(key)) is int and params[key] in target.authorization_contexts
                           for key in ("contextId", "executionContextId")):
                        raise InspectorError("The inspector authorization context is private.", -32602)
                limit = MAX_PENDING_COMMANDS
                if command["method"] in UNBLOCKING_COMMANDS:
                    limit += RESERVED_CONTROL_COMMANDS
                if len(pending) >= limit:
                    raise InspectorError("Too many inspector commands are pending. Retry after a reply.", -32000)
            except InspectorError as error:
                write({"id": identifier, "error": {"code": error.code, "message": str(error)}})
                continue
            # CdpTarget sends in FIFO order. Waiting for a reply here would prevent a
            # later debugger or Fetch command from unblocking an evaluation.
            entry = PendingInspectorCommand(command["method"], loop.time())
            if entry.method in FETCH_ACTIONS:
                request = command["params"].get("requestId")
                if isinstance(request, str) and request in fetch_pauses:
                    entry.continued_fetch = (request, fetch_pauses[request])
            arm_reply_timeout(entry)
            pending[identifier] = entry
            drained.clear()
            await target.send(command)

    async def outputs():
        while True:
            message = await target.receive()
            if message.get("event") == "revoked":
                write(message)
                stop.set()
                continue
            if "id" in message:
                identifier = message["id"]
                if type(identifier) is not int:
                    continue
                if identifier == 0:
                    if cleanup_reply is not None and not cleanup_reply.done():
                        cleanup_reply.set_result(message)
                    continue
                command = pending.pop(identifier, None)
                if command is None:
                    continue
                command.timer.cancel()
                if not pending:
                    drained.set()
                if not target.revoked:
                    if "result" in message:
                        observe_success(command)
                    write(message)
            elif not target.revoked and message.get("method", "").split(".", 1)[0] in METHODS:
                observe_event(message)
                write(message)

    reader_task = asyncio.create_task(inputs())
    writer_task = asyncio.create_task(outputs())
    stop_task = asyncio.create_task(stop.wait())
    try:
        done, _ = await asyncio.wait((reader_task, writer_task, stop_task, expired), return_when=asyncio.FIRST_COMPLETED)
        for task in done:
            task.result()
        if expired in done:
            raise InspectorError(expired.result())
    finally:
        reader_task.cancel()
        stop_task.cancel()
        await asyncio.gather(reader_task, stop_task, return_exceptions=True)
        input_closed = True
        expired.cancel()
        if pause_timer is not None:
            pause_timer.cancel()
        for command in pending.values():
            command.timer.cancel()
        pending.clear()
        await cleanup_target(target, cleanup_call)
        writer_task.cancel()
        await asyncio.gather(writer_task, return_exceptions=True)


async def connect_device(udid, mobdev2):
    from pymobiledevice3.lockdown import create_using_usbmux, get_mobdev2_lockdowns

    if mobdev2:
        devices = get_mobdev2_lockdowns(udid=udid, only_paired=True)
        lockdown = None
        try:
            async for _, lockdown in devices:
                break
        finally:
            try:
                await devices.aclose()
            except (asyncio.CancelledError, Exception):
                if lockdown is not None:
                    await close_startup_resource(lockdown)
                raise
        if lockdown is not None:
            return lockdown
        raise InspectorError("No trusted iPhone with that identifier is reachable over Wi-Fi.")
    lockdown = await create_using_usbmux(serial=udid, connection_type="USB", autopair=False)
    if not lockdown.paired or (lockdown.udid or "").lower() != udid.lower():
        await lockdown.close()
        raise InspectorError("Unlock and trust the selected iPhone on this Mac before opening the inspector.")
    return lockdown


async def close_startup_resource(resource):
    if resource is not None:
        with contextlib.suppress(Exception):
            await asyncio.wait_for(resource.close(), timeout=1)


async def run(mobdev2):
    if importlib.metadata.version("pymobiledevice3") != PACKAGE_VERSION:
        raise InspectorError(f"Walnut requires pymobiledevice3 {PACKAGE_VERSION} for engine inspection.")
    from pymobiledevice3.services.web_protocol.cdp_target import CdpTarget
    from pymobiledevice3.services.web_protocol.session_protocol import SessionProtocol
    from pymobiledevice3.services.webinspector import WebinspectorService

    loop = asyncio.get_running_loop()
    stop = asyncio.Event()
    ready = asyncio.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)
    reader = asyncio.StreamReader(limit=MAX_COMMAND_BYTES + 1)

    class StartupInputProtocol(asyncio.StreamReaderProtocol):
        def eof_received(self):
            if not ready.is_set():
                stop.set()
            return super().eof_received()

        def connection_lost(self, error):
            if not ready.is_set():
                stop.set()
            super().connection_lost(error)

    async def session():
        lockdown = None
        inspector = None
        target = None

        async def open_lockdown():
            nonlocal lockdown
            if not stop.is_set():
                lockdown = await connect_device(udid, mobdev2)

        async def connect_inspector():
            if not stop.is_set():
                await inspector.connect()

        async def open_target():
            nonlocal target
            if not stop.is_set():
                target = await attach(inspector, bundle, nonce, scoped_target_type(CdpTarget), SessionProtocol, stop=stop)

        try:
            frame = await asyncio.wait_for(read_frame(reader), timeout=10)
            if stop.is_set():
                return
            udid, bundle, nonce = startup_config(parse_object(frame or b""))
            await asyncio.wait_for(open_lockdown(), timeout=15)
            if stop.is_set():
                return
            inspector = WebinspectorService(lockdown=lockdown)
            inspector.on_connection_lost = stop.set
            await asyncio.wait_for(connect_inspector(), timeout=25)
            if stop.is_set():
                return
            await asyncio.wait_for(open_target(), timeout=35)
            if stop.is_set():
                return
            emit({"event": "ready", "protocol": "cdp", "bundleId": bundle, "acceptedMethods": sorted(ALLOWED_METHODS)})
            ready.set()
            await relay(reader, target, stop, lambda value: emit(value, nonce))
        finally:
            if not ready.is_set():
                await close_startup_resource(target)
            await close_startup_resource(inspector)
            await close_startup_resource(lockdown)

    transport = None
    try:
        transport, _ = await loop.connect_read_pipe(lambda: StartupInputProtocol(reader), sys.stdin.buffer)
        session_task = asyncio.create_task(session())
        stop_task = asyncio.create_task(stop.wait())
        try:
            await asyncio.wait((session_task, stop_task), return_when=asyncio.FIRST_COMPLETED)
            if ready.is_set() or not stop.is_set():
                await session_task
        finally:
            stop_task.cancel()
            if not session_task.done():
                session_task.cancel()
            await asyncio.gather(session_task, stop_task, return_exceptions=True)
    finally:
        if transport is not None:
            transport.close()
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.remove_signal_handler(sig)


def main():
    logging.disable(logging.CRITICAL)
    try:
        if sys.argv[1:] not in ([], ["--mobdev2"]):
            raise InspectorError("Invalid inspector launch options.")
        asyncio.run(run(sys.argv[1:] == ["--mobdev2"]))
        return 0
    except BrokenPipeError:
        return 1
    except InspectorError as error:
        message = str(error)
    except Exception as error:
        known = {
            "NoDeviceConnectedError": "Connect and unlock the selected iPhone before opening the inspector.",
            "NotPairedError": "Trust the selected iPhone on this Mac before opening the inspector.",
            "PackageNotFoundError": f"Walnut requires pymobiledevice3 {PACKAGE_VERSION} for engine inspection.",
            "TimeoutError": "The iPhone inspector did not respond. Check the connection and Web Inspector setting.",
            "WebInspectorNotEnabledError": "Enable Web Inspector in iPhone Settings for Safari, then retry.",
        }
        message = known.get(type(error).__name__, "Could not open the authorized Walnut Web Inspector session.")
    with contextlib.suppress(BrokenPipeError):
        emit({"event": "error", "error": message})
    return 1


if __name__ == "__main__":
    sys.exit(main())
"""#
