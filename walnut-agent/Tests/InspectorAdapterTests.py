import asyncio
from collections import defaultdict, deque
from importlib.metadata import PackageNotFoundError, version
import json
import os
from pathlib import Path
import signal
from types import SimpleNamespace
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1] / "Sources" / "WalnutAgent" / "InspectorProgram.swift"
PROGRAM = SOURCE.read_text(encoding="utf-8").split('#"""\n', 1)[1].rsplit('\n"""#', 1)[0]
INSPECTOR = SimpleNamespace(__name__="walnut_inspector_test")
exec(compile(PROGRAM, str(SOURCE), "exec"), INSPECTOR.__dict__)
NONCE = "a" * 32
UDID = "00008120-0011111111111111"
BUNDLE = "com.kobbokkom.wina.qa"
try:
    HAS_PINNED_PACKAGE = version("pymobiledevice3") == INSPECTOR.PACKAGE_VERSION
except PackageNotFoundError:
    HAS_PINNED_PACKAGE = False


class FakeTarget:
    def __init__(self):
        self.output_queue = asyncio.Queue()
        self.sent = []
        self.revoked = False
        self.closed = False
        self.authorization_contexts = {17}
        self._emitted_context_unique_ids = set()
        self.from_cdp_special_messages_methods = {}

    async def send(self, request):
        self.sent.append(request["method"])
        await self.output_queue.put({"id": request["id"], "result": {}})

    async def receive(self):
        return await self.output_queue.get()

    async def close(self):
        self.closed = True


class InspectorAdapterTests(unittest.IsolatedAsyncioTestCase):
    def test_requires_explicit_walnut_grant_and_rejects_unsafe_commands(self):
        value = {"version": 1, "udid": UDID, "bundleId": BUNDLE, "nonce": NONCE}
        self.assertEqual(INSPECTOR.startup_config(value), (UDID, BUNDLE, NONCE))
        for invalid in (dict(value, bundleId="com.apple.mobilesafari"), dict(value, udid=""), dict(value, nonce="x")):
            with self.assertRaises(INSPECTOR.InspectorError):
                INSPECTOR.startup_config(invalid)

        self.assertEqual(INSPECTOR.validate_request({"id": 1, "method": "Debugger.stepOver"})["params"], {})
        for method in ("Target.attachToTarget", "Browser.close", "IO.read", "Network.setBlockedURLs", "HeapProfiler.stopSampling", "Tracing.start"):
            with self.assertRaises(INSPECTOR.InspectorError):
                INSPECTOR.validate_request({"id": 1, "method": method})
        with self.assertRaises(INSPECTOR.InspectorError):
            INSPECTOR.validate_request({"id": 1, "method": "Runtime.evaluate", "sessionId": "other-target"})
        with self.assertRaises(INSPECTOR.InspectorError):
            INSPECTOR.parse_object(b'{"id":1,"id":2}')

    async def test_bounds_frames_and_redacts_nonce(self):
        reader = asyncio.StreamReader(limit=8)
        reader.feed_data(b"1234567890\n")
        with self.assertRaises(INSPECTOR.InspectorError):
            await INSPECTOR.read_frame(reader)
        self.assertEqual(json.loads(INSPECTOR.encode_frame({"value": NONCE}, NONCE)), {"value": "<redacted>"})
        with patch.dict(INSPECTOR.encode_frame.__globals__, MAX_OUTPUT_BYTES=16):
            with self.assertRaises(INSPECTOR.InspectorError):
                INSPECTOR.encode_frame({"value": "x" * 32})

    async def test_attaches_only_to_matching_walnut_document(self):
        selected = []

        class TestTarget(FakeTarget):
            @classmethod
            async def create(cls, protocol):
                target = cls()
                target.page = protocol.page
                selected.append(target)
                return target

            async def send(self, request):
                if request["method"] == "Runtime.evaluate":
                    assert request["params"]["contextId"] == 17
                result = {"result": {"value": self.page.matches}} if request["method"] == "Runtime.evaluate" else {}
                await self.output_queue.put({"id": request["id"], "result": result})

        def protocol(_, identifier, app, page, method_prefix):
            self.assertEqual(method_prefix, "")
            return SimpleNamespace(id_=identifier, app=app, page=page)

        def page(identifier, bundle, matches):
            return SimpleNamespace(
                application=SimpleNamespace(id_=bundle, bundle=bundle, proxy=False),
                page=SimpleNamespace(id_=identifier, matches=matches, type_=SimpleNamespace(value="WIRTypeWebPage")),
            )

        class Inspector:
            async def get_open_application_pages(self, timeout):
                return [page(1, "com.apple.mobilesafari", True), page(2, BUNDLE, False), page(3, BUNDLE, True)]

        target = await INSPECTOR.attach(Inspector(), BUNDLE, NONCE, TestTarget, protocol)
        self.assertEqual([attempt.page.id_ for attempt in selected], [2, 3])
        self.assertTrue(selected[0].closed)
        self.assertIs(target, selected[1])

        class AmbiguousInspector:
            async def get_open_application_pages(self, timeout):
                return [page(4, BUNDLE, True), page(5, BUNDLE, True)]

        with self.assertRaisesRegex(INSPECTOR.InspectorError, "More than one Walnut page"):
            await INSPECTOR.attach(AmbiguousInspector(), BUNDLE, NONCE, TestTarget, protocol)
        self.assertTrue(all(attempt.closed for attempt in selected[-2:]))

    async def test_revokes_main_document_before_forwarding_new_target(self):
        class BridgeTarget(FakeTarget):
            target_id = "original"
            _webkit_frame_id = "main"

            async def _to_output_queue(self, message):
                await self.output_queue.put(message)

            async def _dispatch_target_message(self, message):
                await self.output_queue.put(message)

        scope = INSPECTOR.scoped_target_type(BridgeTarget)()
        child = {"method": "Page.frameNavigated", "params": {"frame": {"id": "child", "parentId": "main"}}}
        await scope._dispatch_target_message(child)
        self.assertEqual(await scope.receive(), child)
        await scope._to_output_queue({
            "method": "Target.targetCreated", "params": {"targetInfo": {"type": "page", "targetId": "replacement"}},
        })
        self.assertTrue(scope.revoked)
        self.assertEqual(await scope.receive(), INSPECTOR.REVOKED)
        await scope._dispatch_target_message({"method": "Debugger.scriptParsed", "params": {"url": "private"}})
        self.assertTrue(scope.output_queue.empty())

        same_process = INSPECTOR.scoped_target_type(BridgeTarget)()
        await same_process._dispatch_target_message({"method": "Page.frameNavigated", "params": {"frame": {"id": "main"}}})
        self.assertTrue(same_process.revoked)
        self.assertEqual(await same_process.receive(), INSPECTOR.REVOKED)

    async def test_queued_navigation_blocks_internal_response(self):
        queued = [{"method": "Target.dispatchMessageFromTarget", "params": {
            "targetId": "original",
            "message": json.dumps({"method": "Page.frameNavigated", "params": {"frame": {"id": "main"}}}),
        }}]

        class BridgeTarget(FakeTarget):
            target_id = "original"
            _webkit_frame_id = "main"
            session_id = "session"
            protocol = SimpleNamespace(inspector=SimpleNamespace(session_events=lambda _: queued))

            async def wait_for_event_id(self, identifier):
                return {"id": identifier, "result": {"source": "after-navigation"}}

        scope = INSPECTOR.scoped_target_type(BridgeTarget)()
        self.assertIsNone(await scope.wait_for_event_id(-1))
        self.assertTrue(scope.revoked)
        self.assertEqual(await scope.receive(), INSPECTOR.REVOKED)

        pending_scope = INSPECTOR.scoped_target_type(BridgeTarget)()
        with self.assertRaisesRegex(INSPECTOR.InspectorError, "document changed"):
            await pending_scope._send_message_to_target({"id": 1, "method": "Runtime.evaluate"})
        self.assertEqual(await pending_scope.receive(), INSPECTOR.REVOKED)

    async def test_eof_resumes_debugger_releases_interception_and_detaches(self):
        target = FakeTarget()
        reader = asyncio.StreamReader()
        reader.feed_data(b'{"id":1,"method":"Debugger.pause"}\n')
        reader.feed_eof()
        outputs = []
        await INSPECTOR.relay(reader, target, asyncio.Event(), outputs.append)
        self.assertEqual(outputs, [{"id": 1, "result": {}}])
        self.assertEqual(target.sent, ["Debugger.pause", "Debugger.resume", "Fetch.disable", "Debugger.disable"])
        self.assertTrue(target.closed)

    async def test_eof_without_newline_discards_valid_json(self):
        startup = asyncio.StreamReader()
        startup.feed_data(json.dumps({"version": 1, "udid": UDID, "bundleId": BUNDLE, "nonce": NONCE}).encode())
        startup.feed_eof()
        with self.assertRaisesRegex(INSPECTOR.InspectorError, "newline delimiter"):
            await INSPECTOR.read_frame(startup)

        target = FakeTarget()
        reader = asyncio.StreamReader()
        reader.feed_data(b'{"id":1,"method":"Runtime.disable"}\n{"id":2,"method":"Debugger.pause"}')
        reader.feed_eof()
        outputs = []
        with self.assertRaisesRegex(INSPECTOR.InspectorError, "newline delimiter"):
            await INSPECTOR.relay(reader, target, asyncio.Event(), outputs.append)
        self.assertEqual(outputs, [{"id": 1, "result": {}}])
        self.assertEqual(target.sent, ["Runtime.disable", "Debugger.resume", "Fetch.disable", "Debugger.disable"])
        self.assertTrue(target.closed)

    def test_fetch_options_reject_unimplemented_behavior(self):
        with self.assertRaises(INSPECTOR.InspectorError):
            INSPECTOR.interception_patterns({"patterns": [{"resourceType": "XHR"}]})
        with self.assertRaises(INSPECTOR.InspectorError):
            INSPECTOR.validate_fetch_action("Fetch.continueResponse", {"requestId": "r", "responseCode": 302})
        with self.assertRaises(INSPECTOR.InspectorError):
            INSPECTOR.validate_fetch_action("Fetch.failRequest", {"requestId": "r", "errorReason": "TimedOut"})
        self.assertEqual(INSPECTOR.interception_patterns({"patterns": [{"urlPattern": "*/a?", "requestStage": "Response"}]}), [
            {"url": "^.*/a.$", "stage": "response", "isRegex": True},
        ])

    @unittest.skipUnless(HAS_PINNED_PACKAGE, "requires the pinned pymobiledevice3 package")
    async def test_pinned_target_isolated_context_fetch_ack_and_revoked_detach(self):
        from pymobiledevice3.services.web_protocol.cdp_target import CdpTarget
        from pymobiledevice3.services.web_protocol.session_protocol import SessionProtocol
        from pymobiledevice3.services.webinspector import WirTypes

        class Wire:
            def __init__(self):
                self.events = defaultdict(deque)
                self.app = SimpleNamespace(id_="PID:17", bundle=BUNDLE, proxy=False)
                self.page = SimpleNamespace(id_=1, type_=WirTypes.WEB_PAGE, web_url="https://example.invalid/")
                self.commands = []
                self.closed = []
                self.resource_content = "<!doctype html><title>retained fixture</title>"
                self.navigate_during_resource_read = False
                self.change_route_during_resource_read = False

            async def get_open_application_pages(self, timeout):
                return [SimpleNamespace(application=self.app, page=self.page)]

            def session_events(self, session):
                return self.events[session]

            async def setup_inspector_socket(self, session, app, page, automatically_pause=False):
                self.events[session].append({
                    "method": "Target.targetCreated", "params": {"targetInfo": {"type": "page", "targetId": "original"}},
                })

            async def teardown_inspector_socket(self, session, app, page):
                self.closed.append((session, app, page))

            def event(self, session, message):
                self.events[session].append({
                    "method": "Target.dispatchMessageFromTarget",
                    "params": {"targetId": "original", "message": json.dumps(message)},
                })

            async def send_socket_data(self, session, app, page, data):
                command = json.loads(data["params"]["message"])
                self.commands.append(command)
                method = command["method"]
                reply = {"id": command["id"], "result": {}}
                if method == "Page.getResourceTree":
                    reply["result"] = {"frameTree": {
                        "frame": {"id": "main", "loaderId": "loader", "url": self.page.web_url}, "resources": [],
                    }}
                if method == "Page.getResourceContent":
                    reply["result"] = {"content": self.resource_content, "base64Encoded": False}
                    if self.navigate_during_resource_read:
                        self.event(session, {"method": "Page.frameNavigated", "params": {"frame": {"id": "main"}}})
                    if self.change_route_during_resource_read:
                        self.page.web_url += "new-route"
                if method == "Runtime.enable":
                    for identifier, context_type, frame in ((2, "normal", "main"), (9, "user", "child"), (17, "user", "main")):
                        self.event(session, {"method": "Runtime.executionContextCreated", "params": {"context": {
                            "id": identifier, "type": context_type, "name": INSPECTOR.AUTHORIZATION_WORLD, "frameId": frame,
                        }}})
                if method == "Runtime.evaluate":
                    reply["result"] = {"result": {"type": "boolean", "value": command["params"].get("contextId") == 17}}
                if method == "Network.interceptContinue":
                    reply = {"id": command["id"], "error": {"code": -32042, "message": "Missing pending intercept request"}}
                self.event(session, reply)

        wire = Wire()
        target = await INSPECTOR.attach(wire, BUNDLE, NONCE, INSPECTOR.scoped_target_type(CdpTarget), SessionProtocol)
        self.assertEqual(target.authorization_contexts, {17})
        tree = await INSPECTOR.startup_call(target, "Page.getResourceTree", {})
        frame = tree["result"]["frameTree"]["frame"]
        source = {"frameId": frame["id"], "url": frame["url"]}
        for invalid in (dict(source, frameId="child"), dict(source, url=frame["url"] + "other")):
            before = len(wire.commands)
            rejected_source = await INSPECTOR.startup_call(target, "Page.getResourceContent", invalid)
            self.assertEqual(rejected_source["error"]["code"], -32602)
            self.assertNotIn("Page.getResourceContent", [command["method"] for command in wire.commands[before:]])
        retained = await INSPECTOR.startup_call(target, "Page.getResourceContent", source)
        self.assertEqual(retained["result"], {
            "content": wire.resource_content, "base64Encoded": False, "retrieval": "webkit-resource",
        })
        read_command = next(command for command in reversed(wire.commands) if command["method"] == "Page.getResourceContent")
        self.assertEqual(read_command["params"], {"frameId": "main", "url": frame["url"]})
        wire.change_route_during_resource_read = True
        replaced_route = await INSPECTOR.startup_call(target, "Page.getResourceContent", source)
        self.assertEqual(replaced_route["error"]["code"], -32000)
        self.assertNotIn("result", replaced_route)
        wire.change_route_during_resource_read = False
        wire.page.web_url = frame["url"]
        wire.resource_content = ""
        unavailable = await INSPECTOR.startup_call(target, "Page.getResourceContent", source)
        self.assertEqual(unavailable["error"]["code"], -32000)
        before = len(wire.commands)
        ignored_option = await INSPECTOR.startup_call(target, "Fetch.enable", {"patterns": [{"resourceType": "XHR"}]})
        self.assertEqual(ignored_option["error"]["code"], -32602)
        self.assertEqual(len(wire.commands), before)
        enabled = await INSPECTOR.startup_call(target, "Fetch.enable", {})
        self.assertIn("result", enabled)
        rejected = await INSPECTOR.startup_call(target, "Fetch.continueRequest", {"requestId": "missing"})
        self.assertEqual(rejected["error"], {"code": -32042, "message": "Missing pending intercept request"})
        with patch.object(target, "wait_for_event_id", return_value=None):
            unacknowledged = await INSPECTOR.startup_call(target, "Fetch.continueRequest", {"requestId": "missing"})
        self.assertEqual(unacknowledged["error"]["code"], -32000)
        self.assertIn("did not acknowledge", unacknowledged["error"]["message"])
        wire.event(target.session_id, {"method": "Network.responseIntercepted", "params": {
            "requestId": "response", "response": {"status": 200},
        }})
        self.assertEqual((await asyncio.wait_for(target.receive(), timeout=1))["method"], "Fetch.requestPaused")
        before = len(wire.commands)
        omitted_body = await INSPECTOR.startup_call(target, "Fetch.fulfillRequest", {"requestId": "response", "responseCode": 201})
        self.assertEqual(omitted_body["error"]["code"], -32602)
        self.assertEqual(len(wire.commands), before)
        fulfilled = await INSPECTOR.startup_call(target, "Fetch.fulfillRequest", {
            "requestId": "response", "responseCode": 201, "body": "",
            "responseHeaders": [{"name": "CONTENT-TYPE", "value": "application/json"}],
        })
        self.assertIn("result", fulfilled)
        self.assertEqual(wire.commands[-1]["method"], "Network.interceptWithResponse")
        self.assertEqual(wire.commands[-1]["params"]["mimeType"], "application/json")
        content_type = "  TEXT/CSS; charset=utf-8 "
        request_replacement = await INSPECTOR.startup_call(target, "Fetch.fulfillRequest", {
            "requestId": "request", "responseCode": 200, "body": "Ym9keXt9",
            "responseHeaders": [{"name": "CONTENT-TYPE", "value": content_type}],
        })
        self.assertIn("result", request_replacement)
        self.assertEqual(wire.commands[-1]["method"], "Network.interceptRequestWithResponse")
        self.assertEqual(wire.commands[-1]["params"]["mimeType"], "text/css")
        self.assertEqual(wire.commands[-1]["params"]["headers"]["CONTENT-TYPE"], content_type)
        before = len(wire.commands)
        invalid_type = await INSPECTOR.startup_call(target, "Fetch.fulfillRequest", {
            "requestId": "request", "responseCode": 200,
            "responseHeaders": [{"name": "CONTENT-TYPE", "value": "broken type; charset=utf-8"}],
        })
        self.assertEqual(invalid_type["error"]["code"], -32602)
        self.assertEqual(len(wire.commands), before)
        wire.resource_content = "content from a replacement document"
        wire.navigate_during_resource_read = True
        with self.assertRaisesRegex(INSPECTOR.InspectorError, "document changed"):
            await INSPECTOR.startup_call(target, "Page.getResourceContent", source)
        self.assertTrue(target.revoked)
        before = len(wire.commands)
        with self.assertRaisesRegex(INSPECTOR.InspectorError, "document changed"):
            await target._send_message_to_target({"id": 1, "method": "Runtime.evaluate", "params": {"expression": "0"}})

        async def unexpected_command(*args, **kwargs):
            self.fail("revoked inspector must detach without targeting the replacement page")

        await INSPECTOR.cleanup_target(target, unexpected_command)
        self.assertEqual(len(wire.commands), before)
        self.assertEqual(wire.closed, [(target.session_id, wire.app.id_, wire.page.id_)])

    @unittest.skipUnless(HAS_PINNED_PACKAGE, "requires the pinned pymobiledevice3 package")
    async def test_startup_stop_cancels_and_closes_acquired_resources(self):
        from pymobiledevice3.services import webinspector

        for stage, stop_by, expected in (
            ("lockdown", "signal", ["lockdown"]),
            ("service", "eof", ["service", "lockdown"]),
            ("attach", "signal", ["target", "service", "lockdown"]),
            ("ready", "eof", ["target", "service", "lockdown"]),
        ):
            with self.subTest(stage=stage, stop_by=stop_by):
                entered = asyncio.Event()
                closed = []
                attach_started = []
                packets = []

                async def block_until_cancelled():
                    entered.set()
                    try:
                        await asyncio.Future()
                    except asyncio.CancelledError:
                        # Return the acquired resource during cancellation to exercise the ownership race.
                        pass

                class Lockdown:
                    async def close(self):
                        closed.append("lockdown")

                class Inspector:
                    def __init__(self, lockdown):
                        pass

                    async def connect(self):
                        if stage == "service":
                            await block_until_cancelled()

                    async def close(self):
                        closed.append("service")

                class Target(FakeTarget):
                    async def close(self):
                        closed.append("target")

                async def connect_device(udid, mobdev2):
                    if stage == "lockdown":
                        await block_until_cancelled()
                    return Lockdown()

                async def attach(*args, **kwargs):
                    attach_started.append(True)
                    if stage == "attach":
                        await block_until_cancelled()
                    return Target()

                def emit(value, nonce=None):
                    packets.append(value)
                    if value.get("event") == "ready":
                        entered.set()

                read_fd, write_fd = os.pipe()
                with os.fdopen(read_fd, "rb", buffering=0) as input_pipe, os.fdopen(write_fd, "wb", buffering=0) as output_pipe:
                    with patch.object(webinspector, "WebinspectorService", Inspector), patch.dict(
                        INSPECTOR.run.__globals__, sys=SimpleNamespace(stdin=SimpleNamespace(buffer=input_pipe)),
                        connect_device=connect_device, attach=attach, emit=emit,
                    ):
                        task = asyncio.create_task(INSPECTOR.run(False))
                        try:
                            config = {"version": 1, "udid": UDID, "bundleId": BUNDLE, "nonce": NONCE}
                            output_pipe.write((json.dumps(config) + "\n").encode())
                            await asyncio.wait_for(entered.wait(), timeout=2)
                            if stop_by == "signal":
                                os.kill(os.getpid(), signal.SIGTERM)
                            else:
                                output_pipe.write(b'{"id":1,"method":"Debugger.pause"}\n')
                                output_pipe.close()
                            await asyncio.wait_for(task, timeout=2)
                        finally:
                            if not task.done():
                                task.cancel()
                                await asyncio.gather(task, return_exceptions=True)

                self.assertEqual(closed, expected)
                if stage == "ready":
                    self.assertEqual(packets[0]["event"], "ready")
                    self.assertEqual(packets[1], {"id": 1, "result": {}})
                else:
                    self.assertEqual(packets, [])
                    self.assertEqual(attach_started, [True] if stage == "attach" else [])


if __name__ == "__main__":
    unittest.main()
