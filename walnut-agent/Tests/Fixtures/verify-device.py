"""Exercise a paired Walnut QA device against the synthetic checkout server."""

import argparse
import asyncio
import base64
import contextlib
import json
import os
import signal
import subprocess
import time
from pathlib import Path
from urllib.parse import urlsplit
from uuid import uuid4


def require(condition, description):
    if not condition:
        raise RuntimeError(description)


def verify_page_png(path):
    require(Path(path).read_bytes()[:8] == b"\x89PNG\r\n\x1a\n", "Screenshot is not a PNG")
    recognized = subprocess.run(["swift", "-e", """
        import Foundation
        import Vision
        let request = VNRecognizeTextRequest()
        let image = URL(fileURLWithPath: CommandLine.arguments[1])
        try VNImageRequestHandler(url: image).perform([request])
        print(request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") ?? "")
    """, path], check=True, capture_output=True, text=True, timeout=30).stdout
    require("walnut developer tools verification" in " ".join(recognized.lower().split()),
            "The captured image does not show the fixture page")


class Verification:
    def __init__(self, process, origin, alternate_origin=None):
        self.process = process
        self.origin = origin
        self.alternate_origin = alternate_origin
        self.tools = set()
        self.exercised = set()

    def request(self, request):
        self.process.stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
        self.process.stdin.flush()
        line = self.process.stdout.readline()
        require(line, "Walnut CLI closed before replying")
        reply = json.loads(line)
        require(reply["ok"], reply.get("error", "Walnut returned an error"))
        return reply["result"]

    def call(self, name, **arguments):
        action = arguments.get("action", arguments.get("section"))
        print(json.dumps({"call": name, "action": action}), flush=True)
        result = self.request({"op": "call", "name": name, "arguments": arguments})
        self.exercised.add(name)
        require("runId" in result and "navigation" in result, "Missing execution evidence")
        return result

    def data(self, name, **arguments):
        return self.call(name, **arguments)["data"]

    def open(self, path, status=200, mode="wkwebview", origin=None):
        result = self.call("walnut_browser", action="open", mode=mode, url=(origin or self.origin) + path, recordHistory=False)
        if mode == "wkwebview":
            require(result["navigation"].get("httpStatus") == status, "Unexpected HTTP status")
            require(result.get("documentId"), "No document committed")
        return result

    def verify(self, suites):
        catalog = self.request({"op": "tools"})["data"]
        self.tools = {entry["name"] for entry in catalog["tools"]}
        self.exercised.add("walnut_capabilities")
        print(json.dumps({"catalogCount": len(self.tools), "mode": catalog["mode"]}), flush=True)
        self.data("settings_apply", settings={"privateBrowsing": True, "cleanStart": False})
        failures = []
        try:
            for suite in suites:
                try:
                    getattr(self, f"verify_{suite}")()
                except (KeyError, RuntimeError, StopIteration, subprocess.SubprocessError) as error:
                    failures.append(suite)
                    print(json.dumps({"failed": suite, "error": str(error)}), flush=True)
        finally:
            self.data("settings_reset")
        require(not failures, f"Device verification failed for: {', '.join(failures)}")

    def verify_diagnostics(self):
        self.open("/agent-e2e")
        console = self.data("console_configure", capture=True, preserveOnReload=True, clearStrategy="keep", regex=True)
        network = self.data("network_configure", capture=True, preserveOnReload=True, clearStrategy="keep")
        require(console["capture"] and console["regex"] and console["preserveOnReload"], "Console config was not applied")
        require(network["capture"] and network["preserveOnReload"], "Network config was not applied")
        self.data("settings_apply", settings={"customUserAgent": "Walnut iPhone E2E"})
        mobile = self.open("/checkout-a", status=403)
        self.data("settings_apply", settings={"customUserAgent": "Walnut Desktop E2E"})
        desktop = self.open("/checkout-a")
        require(mobile["documentId"] != desktop["documentId"], "UA retry did not commit another document")
        broken = self.open("/checkout-b")
        errors = self.data("console_list", type="error", raw=True, query="TypeError|renderer unavailable", regex=True,
                           documentId=broken["documentId"])
        require(errors["total"] > 0, "The 200 page's JavaScript error was not captured")
        self.data("console_detail", id=errors["records"][0]["id"])
        exported = self.data("console_list", documentId=broken["documentId"], format="json")
        require(json.loads(exported["records"]), "Console export was empty")
        print(json.dumps({"passed": "HTTP 403 vs 200 with JavaScript exception"}), flush=True)

    def log_counts(self, document):
        console = self.data("console_list", documentId=document, limit=1)
        network = self.data("network_list", documentId=document, limit=1)
        return console["total"], network["requestCount"], network["resourceCount"]

    def require_log_capture(self, document):
        for _ in range(20):
            if all(self.log_counts(document)):
                return
            time.sleep(0.25)
        raise RuntimeError("Console, Network and Resources did not all capture the fixture")

    def verify_log_options(self):
        self.open("/agent-e2e")
        initial = self.data("console_configure", capture=True, preserveOnReload=True, clearStrategy="keep")
        levels = ["log", "info", "warn", "error", "group"]
        self.data("console_configure", types=levels)
        try:
            self.verify_retained_logs(levels, initial["regex"])
        finally:
            self.data("console_configure", types=initial["types"], regex=initial["regex"])

    def verify_retained_logs(self, levels, initial_regex):
        self.data("network_configure", capture=True, preserveOnReload=True, clearStrategy="keep")
        first = self.call("walnut_browser", action="reload")["documentId"]
        self.require_log_capture(first)

        all_console = self.data("console_list", documentId=first)["records"]
        group = next(row for row in all_console if row["type"] == "group" and row.get("groupId"))
        warn = next(row for row in all_console if row["type"] == "warn" and row.get("groupId") == group["groupId"])
        try:
            self.data("console_group", id=group["groupId"], collapsed=True)
            visible = self.data("console_list", documentId=first, includeCollapsed=False)["records"]
            require(warn["id"] not in {row["id"] for row in visible}, "Collapsed child remained visible")
        finally:
            self.data("console_group", id=group["groupId"], collapsed=False)
        self.data("console_configure", types=["warn"], regex=True)
        try:
            filtered = self.data("console_list", documentId=first, query="Walnut E2E w.rning", raw=True)["records"]
            require([row["id"] for row in filtered] == [warn["id"]], "Console Regex or level filter did not match the fixture")
            literal = self.data("console_list", documentId=first, query="Walnut E2E w.rning", regex=False)["records"]
            require(not literal, "Literal Console search matched a Regex-only expression")
        finally:
            self.data("console_configure", types=levels, regex=initial_regex)

        for category, key in (("doc", "requests"), ("fetchXhr", "requests"), ("js", "resources"), ("css", "resources")):
            result = self.data("network_list", documentId=first, category=category)
            other_key = "resources" if key == "requests" else "requests"
            require(result[key] and not result[other_key], f"Network category {category} selected the wrong records")
        self.data("console_configure", capture=False)
        self.data("network_configure", capture=False)
        quiet = self.call("walnut_browser", action="reload")["documentId"]
        time.sleep(0.5)
        require(self.log_counts(quiet) == (0, 0, 0), "Disabled capture retained records from the new document")
        require(all(self.log_counts(first)), "Reload with Preserve Log enabled dropped earlier records")

        self.data("console_configure", capture=True, preserveOnReload=False)
        self.data("network_configure", capture=True, preserveOnReload=False)
        recent = self.call("walnut_browser", action="reload")["documentId"]
        self.require_log_capture(recent)
        require(self.log_counts(first) == (0, 0, 0), "Reload with Preserve Log disabled retained earlier records")

        self.data("console_configure", clearStrategy="page")
        self.data("network_configure", clearStrategy="origin")
        self.open("/checkout-b")
        logs, requests, resources = self.log_counts(recent)
        require(not logs and requests and resources, "Clear on every page and keep same-origin were not independent")

        self.data("console_configure", clearStrategy="origin")
        self.data("network_configure", clearStrategy="page")
        same_origin = self.open("/agent-e2e")["documentId"]
        self.require_log_capture(same_origin)
        require(self.log_counts(recent) == (0, 0, 0), "Page strategy kept old Network or Resources records")
        broken = self.open("/checkout-b")["documentId"]
        logs, requests, resources = self.log_counts(same_origin)
        require(logs and not requests and not resources, "Same-origin navigation did not preserve Console alone")
        errors = self.data("console_list", documentId=broken, type="error")
        require(errors["total"], "Fixture script error was not captured")

        self.data("network_configure", clearStrategy="origin")
        before_origin_change = self.open("/agent-e2e")["documentId"]
        self.require_log_capture(before_origin_change)
        after_origin_change = self.open("/agent-e2e", origin=self.alternate_origin)["documentId"]
        self.require_log_capture(after_origin_change)
        require(self.log_counts(before_origin_change) == (0, 0, 0), "Cross-origin navigation retained the old logs")
        print(json.dumps({"passed": "Console, Network and Resources capture, filters, reload preservation and clear strategies"}), flush=True)

    def verify_settings(self):
        self.open("/agent-e2e")
        second = self.open("/checkout-b")
        require(second["data"]["canGoBack"], "Fixture navigation did not create back history")
        baseline = self.data("diagnostics", section="accessibility")["data"]
        scheme = "light" if baseline["colorScheme"] == "Dark" else "dark"
        emulation = {
            "emulationColorScheme": scheme,
            "emulationReducedMotion": True,
            "emulationHighContrast": True,
            "emulationReducedTransparency": True,
        }
        applied = self.call("settings_apply", settings=emulation)
        require(applied["data"]["browserReloadRequested"] and not applied["data"]["browserRecreationRequested"],
                "Emulation did not reload the existing WKWebView")
        require(applied["documentId"] != second["documentId"], "Emulation reload did not commit a document")
        require(self.data("walnut_browser", action="status")["canGoBack"], "Emulation apply dropped back history")
        detected = self.data("diagnostics", section="accessibility")
        expected = {"colorScheme": scheme.title(), "contrast": "More", "reducedMotion": "Reduce", "reducedTransparency": "Reduce"}
        require(detected["source"] == "live_wkwebview" and all(detected["data"].get(key) == value for key, value in expected.items()),
                "The live WKWebView did not observe the emulated preferences")
        restored = self.call("settings_reset", keys=list(emulation))
        require(restored["data"]["browserReloadRequested"] and restored["documentId"] != applied["documentId"],
                "Emulation reset did not reload the current document")
        require(self.data("walnut_browser", action="status")["canGoBack"], "Emulation reset dropped back history")
        observed = self.data("diagnostics", section="accessibility")["data"]
        require(all(observed[key] == baseline[key] for key in expected), "Emulation reset did not restore the previous preferences")

        for menu, visible, hidden in (("wk_toolbar", "console", "network"), ("wk_app_bar", "home", "back")):
            saved = self.data("menus", menu=menu, action="get")["items"]
            rows = [{"menuItem": hidden, "isVisible": False}, {"menuItem": visible, "isVisible": True}]
            result = self.data("menus", menu=menu, action="apply", items=rows)
            require(result["items"][:2] == rows and result["visibleOrder"] == [visible],
                    f"The {menu} did not keep the ordered hidden row")
            require(self.data("menus", menu=menu, action="reset")["items"] == saved, f"The {menu} did not restore its saved layout")
        print(json.dumps({"passed": "live emulation, retained browser history and ordered toolbar and App Bar visibility"}), flush=True)

    def verify_auxiliary(self):
        baseline = self.open("/agent-e2e")
        original = baseline["webViewState"]
        options = {
            key: not original[key] for key in
            ("allowsBackForwardGestures", "allowsLinkPreview", "textInteractionEnabled", "findInteractionEnabled")
        }
        options.update(pageZoom=1.25 if original["pageZoom"] != 1.25 else 1.5)
        configured = baseline["configuredBrowserSettings"]
        live = {
            **options,
            "webViewWidthRatio": 0.75 if configured["webViewWidthRatio"] != 0.75 else 0.85,
            "webViewHeightRatio": 0.65 if configured["webViewHeightRatio"] != 0.65 else 0.75,
        }
        applied = self.call("settings_apply", settings=live)
        require(not applied["data"]["browserRecreationRequested"], "Live WKWebView options requested recreation")
        for _ in range(20):
            status = self.call("walnut_browser", action="status")
            view = status["webViewState"]
            resized = all(view[key] > 0 and abs(view[key] - original[key]) > 1 for key in ("widthPoints", "heightPoints"))
            if resized and all(view.get(key) == value for key, value in options.items()):
                break
            time.sleep(0.1)
        else:
            raise RuntimeError("The live WKWebView did not apply its interaction settings, size or zoom")
        require(status["documentId"] == baseline["documentId"], "A live setting replaced the document")
        require(all(status["configuredBrowserSettings"][key] == value for key, value in live.items()),
                "The applied WebView settings did not match")
        require(status["webViewState"]["privateBrowsing"], "Fixture did not use the private data store")

        self.data("settings_apply", settings={"allowsContentJavaScript": False})
        disabled = self.open("/agent-e2e")
        require(not disabled["configuredBrowserSettings"]["allowsContentJavaScript"], "Page JavaScript was not disabled")
        require(self.data("network_list", method="POST", documentId=disabled["documentId"])["requestCount"] == 0,
                "The fixture page executed a script while JavaScript was disabled")
        self.data("settings_apply", settings={"allowsContentJavaScript": True})
        enabled = self.open("/agent-e2e")["documentId"]
        for _ in range(20):
            requests = self.data("network_list", method="POST", minStatus=201, maxStatus=201, documentId=enabled)
            if requests["requestCount"]:
                break
            time.sleep(0.25)
        else:
            raise RuntimeError("Re-enabled JavaScript did not produce the fixture POST 201")

        presets = self.data("user_agent", action="presets", query="Firefox")
        require(presets and all(entry["browser"] == "Firefox" for entry in presets), "UA preset search did not match")
        ua = self.data("user_agent", action="build", browser="Chrome", platform="Windows 10/11 64-bit", version="131.0.0.0")["userAgent"]
        parsed = self.data("user_agent", action="parse", userAgent=ua)
        require(parsed["browser"] == "Chrome" and parsed["browserVersion"] == "131.0.0.0", "Built UA did not parse back to Chrome")
        self.data("settings_apply", settings={"customUserAgent": ua})
        override = self.open("/checkout-a")
        require(override["userAgentOverride"] == ua, "The WebView did not set the custom UA")
        browser = self.data("diagnostics", section="browser")
        require(browser["source"] == "live_wkwebview" and browser["data"]["userAgent"] == ua, "Browser Info did not observe the UA")

        api = self.data("diagnostics", section="api")
        require(api["source"] == "live_wkwebview" and api["data"]["supportsFetch"], "Browser API capabilities were unavailable")
        display = self.data("diagnostics", section="display")["data"]
        require(all(display[key].endswith(" px") and int(display[key][:-3]) > 0 for key in ("screenWidth", "screenHeight")),
                "Display Info lacked dimensions")
        codecs = self.data("diagnostics", section="codecs")["data"]
        require({"h264", "hevc", "aac", "opus", "mp4", "webm"}.issubset(codecs), "Media Codec Info was incomplete")
        device = self.data("diagnostics", section="device")
        require(device["source"] == "device" and device["data"]["modelIdentifier"] and device["data"]["systemVersion"],
                "Device Info lacked hardware or OS evidence")
        benchmark = self.data("diagnostics", section="benchmark")
        require(benchmark["source"] == "temporary_benchmark_webview" and benchmark["data"]["totalScore"] > 0,
                "The benchmark did not complete a measured run")
        permissions = self.data("permissions", action="status")
        require(permissions == self.data("diagnostics", section="permissions") and {"camera", "microphone", "location"}.issubset(permissions),
                "The two permission status views disagreed")
        callback = self.data("callbacks", action="test_page")
        require(urlsplit(callback["url"]).scheme == "https" and callback["scheme"] == "walnut", "Callback test URL was not configured")
        require("received" in self.data("callbacks", action="get"), "Callback observation was unavailable")
        for action in ("list", "history"):
            page = self.data("bookmarks", action=action, query="walnut-qa-no-saved-entry.invalid")
            require(page["redacted"] and page["total"] == 0 and not page["urls"], f"{action} query exposed unrelated saved URLs")
        print(json.dumps({"passed": "WKWebView configuration, UA, device, browser, API, display, codecs, benchmark, permissions, callback and URL lists"}), flush=True)

    def verify_documents(self):
        document = self.open("/agent-e2e")["documentId"]
        initial = self.data("accessibility_audit", run=True)
        issue = next(row for row in initial["issues"] if row.get("ruleId") == "image-alt")
        require(initial["hasScanned"] and initial["documentId"] == document, "The audit was not tied to the active document")
        require(initial["scope"] == "main-frame" and initial["hasUntestedFrames"], "Accessibility scope did not report the fixture iframe")
        filters = {"severity": issue["severity"], "category": issue["category"]}
        retained = self.data("accessibility_audit", run=False, query="image-alt", **filters)
        require(retained["total"] and all(row["ruleId"] == "image-alt" and all(row[key] == value for key, value in filters.items())
                                           for row in retained["issues"]), "The retained audit search or filters selected other rules")
        other_severity = "info" if issue["severity"] != "info" else "error"
        mismatched = self.data("accessibility_audit", run=False, severity=other_severity)
        require(mismatched["total"] < initial["total"] and all(row["severity"] == other_severity for row in mismatched["issues"]),
                "The severity filter retained findings from another level")
        other_category = "links" if issue["category"] != "links" else "images"
        mismatched = self.data("accessibility_audit", run=False, category=other_category)
        require(mismatched["total"] < initial["total"] and all(row["category"] == other_category for row in mismatched["issues"]),
                "The category filter retained findings from another category")
        rerun = self.data("accessibility_audit", run=True, **filters)
        fresh = next(row for row in rerun["issues"] if row.get("ruleId") == "image-alt")
        require(fresh["id"] != issue["id"] and rerun["documentId"] == document, "The audit was not rerun on the same document")
        detail = self.data("accessibility_detail", id=fresh["id"])
        require(detail.get("failure") and "<img" in detail.get("html", ""), "The image-alt finding lacked markup or failure evidence")
        report = self.data("accessibility_audit", run=False, format="markdown", **filters)
        require("- Rule: image-alt" in report["export"], "The Markdown report did not contain the finding")
        self.data("accessibility_clear")
        require(not self.data("accessibility_audit", run=False)["hasScanned"], "The cleared audit still reported results")

        snippet = self.data("snippets_list", category="Layout", query="Border All")
        require([entry["id"] for entry in snippet] == ["border_all"], "Snippet category and text did not select Border All")
        enabled = self.data("snippets_run", id="border_all", enabled=True)
        require(enabled["active"] and enabled["result"] == "Borders enabled", "The snippet did not add its stylesheet")
        disabled = self.data("snippets_run", id="border_all")
        require(not disabled["active"] and disabled["result"] == "Borders disabled", "The snippet toggle did not undo its stylesheet")
        self.data("snippets_run", id="border_all", enabled=True)
        self.data("snippets_reset")
        require(not self.data("snippets_list", category="Layout", query="Border All")[0]["active"], "The reset left the snippet active")
        style = self.data("console_evaluate", script="document.getElementById('__wina_border_style__') ? 'present' : 'removed'")
        require(style["result"] == "removed",
                "The snippet reset left its stylesheet in the live document")
        print(json.dumps({"passed": "Accessibility rerun, filters, failure evidence, export, clear and live snippet toggle/undo"}), flush=True)

    def verify_storage_options(self):
        page = self.open("/agent-e2e")
        require(page["webViewState"]["privateBrowsing"], "Storage checks require the isolated fixture data store")
        key = "walnut-e2e-encoded"
        renamed = key + "-renamed"
        value = "Walnut + café %"
        self.data("storage_write", action="add", type="localStorage", key=key, value=value, encode=True)
        self.data("storage_write", action="edit", type="localStorage", key=key, newKey=renamed, value=value, encode=True)
        encoded = self.data("storage_list", type="localStorage", query=key, raw=True)["entries"]
        decoded = self.data("storage_list", type="localStorage", query=key, raw=True, decode=True)["entries"]
        require(len(encoded) == 1 and encoded[0]["key"] == renamed and encoded[0]["value"] != value,
                "The rename left the original key or lost percent encoding")
        require(len(decoded) == 1 and decoded[0]["value"] == value, "Storage decode did not round-trip the text")
        require(self.data("storage_list", type="sessionStorage")["total"] > 0, "The fixture had no Session Storage")
        for kind in ("localStorage", "sessionStorage"):
            self.data("storage_clear", type=kind)
            require(self.data("storage_list", type=kind)["total"] == 0, f"{kind} still contained entries after clear")

        cookie = "walnut-e2e-scope"
        for path, cookie_value in (("/qa-one", "one"), ("/qa-two", "two")):
            self.data("storage_write", type="cookies", action="add", key=cookie, path=path, value=cookie_value)
        self.data("storage_write", type="cookies", action="edit", key=cookie, newKey=cookie + "-renamed",
                  path="/qa-one", value="updated", cookieScope="current")
        cookies = self.data("storage_list", type="cookies", query=cookie, raw=True, cookieScope="current")["entries"]
        require({(row["key"], row["path"], row["value"]) for row in cookies} ==
                {(cookie + "-renamed", "/qa-one", "updated"), (cookie, "/qa-two", "two")},
                "The cookie rename changed the other path or kept the original identity")
        removed = self.data("storage_write", type="cookies", action="remove", key=cookie + "-renamed", path="/qa-one", cookieScope="current")
        require(removed["applied"], "The selected cookie was not removed")
        cleared_path = self.data("storage_list", type="cookies", path="/qa-one", cookieScope="current")
        require(cleared_path["total"] == 0, "The removed cookie still existed at its exact path")
        scoped = self.data("storage_list", type="cookies", domain=urlsplit(self.origin).hostname, path="/qa-two",
                           raw=True, cookieScope="all")["entries"]
        require([(row["key"], row["path"], row["value"]) for row in scoped] == [(cookie, "/qa-two", "two")],
                "The exact domain and path query did not preserve the other cookie")
        self.data("storage_clear", type="cookies", cookieScope="current")
        require(self.data("storage_list", type="cookies")["total"] == 0, "Current-host cookies remained after clear")
        print(json.dumps({"passed": "Storage encoding and rename, local/session clear and cookie domain/path isolation"}), flush=True)

    def verify_startup_options(self):
        saved = self.data("preload", action="get")
        profile = self.data("preload", action="template", preset="empty")
        profile.update(id=str(uuid4()), name="Walnut QA temporary startup", isEnabled=True, capturesWindowPostMessage=True)
        event = str(uuid4())
        source = """
        document.addEventListener('DOMContentLoaded', () => {
            const marker = document.createElement('div');
            marker.id = 'walnut-preload-marker';
            document.body.append(marker);
            window.postMessage({walnutQA: 'QA_EVENT'}, '*');
        });
        """.replace("QA_EVENT", event)
        profile["customScripts"] = [{
            "id": str(uuid4()), "name": "QA startup event", "isEnabled": True, "forMainFrameOnly": True, "source": source
        }]
        try:
            self.data("walnut_browser", action="home")
            self.data("preload", action="disable")
            self.open("/agent-e2e")
            baseline = {row["id"] for row in self.data("preload", action="logs", limit=200)}
            self.data("walnut_browser", action="home")
            applied = self.data("preload", action="apply", profile=profile)
            require(applied["enabled"] and applied["scriptCount"] == 1 and applied["capturesWindowPostMessage"],
                    "The temporary startup profile was not effective")
            self.open("/agent-e2e")
            self.data("walnut_browser", action="wait", selector="#walnut-preload-marker")
            for _ in range(20):
                logs = self.data("preload", action="logs", limit=10)
                entry = next((row for row in logs if row["id"] not in baseline
                              and row["channel"] == "winaPostMessage" and row["direction"] == "received"), None)
                if entry:
                    break
                time.sleep(0.25)
            require(entry and "body" not in entry, "The redacted startup event was not retained")
            raw = self.data("preload", action="logs", raw=True, logId=entry["id"])
            require(json.loads(raw["body"]) == {"origin": self.origin, "data": {"walnutQA": event}},
                    "The retained bridge log was not the test startup event")
            require(not self.data("preload", action="disable")["enabled"], "The temporary profile was not disabled")
            self.open("/agent-e2e")
            script = "document.getElementById('walnut-preload-marker') ? 'present' : 'absent'"
            require(self.data("console_evaluate", script=script)["result"] == "absent", "The disabled profile still injected its script")
        finally:
            self.data("walnut_browser", action="home")
            restored = self.data("preload", action="reset")
        require(all(restored[key] == saved[key] for key in ("name", "enabled", "cookieCount", "windowItemCount", "scriptCount")),
                "Reset did not restore the saved startup profile")
        print(json.dumps({"passed": "Document-start script, redacted and approved bridge log, disable and saved profile restoration"}), flush=True)

    def verify_tools(self):
        page = self.open("/agent-e2e")
        document = page["documentId"]
        self.data("walnut_browser", action="wait", selector="#network-result")
        for _ in range(20):
            requests = self.data("network_list", method="POST", host=urlsplit(self.origin).hostname, minStatus=201,
                                 maxStatus=201, documentId=document)["requests"]
            if requests:
                break
            time.sleep(0.25)
        require(requests, "Fixture POST 201 was not captured")
        request_id = requests[0]["id"]
        headers = self.data("network_detail", id=request_id, section="headers")
        request_headers = {key.lower(): value for key, value in headers["requestHeaders"].items()}
        response_headers = {key.lower(): value for key, value in headers["responseHeaders"].items()}
        require(request_headers.get("x-walnut-e2e") == "fixture", "Missing the fixture request header")
        require("application/json" in response_headers.get("content-type", ""), "Wrong fixture response Content-Type")
        body = self.data("network_detail", id=request_id, section="response")
        require("walnut-fixture-201" in body.get("body", ""), "Wrong captured response body")
        request = self.data("network_detail", id=request_id, section="request")
        require("WK-417" in request.get("body", ""), "Wrong captured request body")
        stack = self.data("network_detail", id=request_id, section="overview", raw=True)
        require(stack.get("stack") and "durationMs" in stack, "Missing request stack or timing")
        resources = self.data("network_list", documentId=document)["resources"]
        require(resources, "No resource timing was captured")
        self.data("resources_detail", id=resources[0]["id"])
        exported = self.data("network_list", method="POST", minStatus=201, maxStatus=201, format="json")
        require(json.loads(exported["export"])["requests"], "Network export was empty")

        scripts = self.data("sources_list", section="scripts", documentId=document)["entries"]
        external = next((entry for entry in scripts if entry.get("external")), None)
        require(external is not None, "Fixture external script is missing")
        script = self.data("sources_detail", kind="script", index=external["index"], documentId=document)
        require("walnutBreakpointFixture" in json.dumps(script), "External source text was not returned")
        require(self.data("sources_list", section="tree", documentId=document)["total"] > 0, "No DOM tree")
        sheets = self.data("sources_list", section="stylesheets", documentId=document)["entries"]
        require(sheets, "Fixture stylesheet is missing")
        css = self.data("sources_detail", kind="stylesheet", index=sheets[0]["index"], documentId=document)
        require(css.get("rules"), "Fixture stylesheet has no rules")
        require(self.data("performance_read", section="all").get("navigation"), "No navigation timing")
        audit = self.data("accessibility_audit", run=True)
        issue = next((row for row in audit["issues"] if row.get("ruleId") == "image-alt"), None)
        require(issue is not None, "axe did not identify the intentionally missing alt attribute")
        require(self.data("accessibility_detail", id=issue["id"]).get("failure"), "Missing axe failure evidence")
        report = self.data("accessibility_audit", run=False, format="markdown")
        require(report["scope"] == "main-frame" and report["hasUntestedFrames"], "Missing audit scope")
        require("- Rule: image-alt" in report["export"], "Report does not contain the observed failure")

        for kind in ("localStorage", "sessionStorage", "cookies"):
            require(self.data("storage_list", type=kind, cookieScope="current")["total"] > 0, f"Fixture {kind} missing")
            scope = {"path": "/checkout-receipt"} if kind == "cookies" else {}
            read = {"type": kind, "query": "walnut-e2e-write", "raw": True, **scope}
            for action, value in (("add", "first"), ("edit", "second"), ("remove", None)):
                arguments = {"action": action, "type": kind, "key": "walnut-e2e-write", **scope}
                if value is not None:
                    arguments["value"] = value
                require(self.data("storage_write", **arguments)["applied"], f"{kind} {action} failed")
                entries = self.data("storage_list", **read)["entries"]
                require([row["value"] for row in entries] == ([] if value is None else [value]),
                        f"{kind} {action} did not have the expected result")
                if kind == "cookies" and entries:
                    require(entries[0]["path"] == scope["path"], "Cookie was written to the wrong path")
        storage_export = self.data("storage_list", type="localStorage", format="text")
        require("walnut-e2e-local" in storage_export["export"] and "local fixture value" in storage_export["export"],
                "Storage export did not contain the fixture value")

        require(self.data("page_search", action="find", query="Walnut search needle")["count"] == 2, "Search count did not match")
        self.data("page_search", action="next")
        self.data("page_search", action="previous")
        self.data("page_search", action="clear")
        self.data("walnut_panel", action="open", panel="console")
        self.data("walnut_panel", action="close", panel="console")
        self.data("snippets_list")
        require(self.data("snippets_run", id="border_all", enabled=True)["active"], "Snippet did not activate")
        require(self.data("snippets_reset")["reset"], "Snippet reset failed")
        self.data("settings_get")
        self.data("menus", menu="wk_toolbar", action="get")
        self.data("preload", action="template", preset="empty")
        self.data("user_agent", action="presets")
        self.data("permissions", action="status")
        self.data("diagnostics", section="api")
        self.data("callbacks", action="test_page")
        self.data("bookmarks", action="list")
        self.data("storage_clear", type="sessionStorage")
        self.data("accessibility_clear")
        self.data("performance_clear")
        self.data("console_clear")
        self.data("network_clear")
        print(json.dumps({"passed": "fixture network, sources, accessibility, storage and search"}), flush=True)

    def find_control(self, document, label):
        for _ in range(4):
            viewport = self.data("page_interact", action="observe", documentId=document)
            match = next((item for item in viewport["elements"] if item["label"] == label), None)
            if match:
                return match
            if not self.data("page_interact", action="scroll", direction="down", documentId=document)["moved"]:
                break
        raise RuntimeError(f"Fixture control is not visible: {label}")

    def verify_controls(self):
        document = self.open("/agent-e2e")["documentId"]
        field = self.find_control(document, "Delivery reference")
        pointer = self.data("page_interact", action="move", documentId=document, **field["point"])
        require(pointer.get("applied"), "Pointer did not move")
        require(self.data("page_interact", action="fill", documentId=document, ref=field["ref"], text="WK-417")["applied"],
                "Text field did not accept the reference")
        shipping = self.find_control(document, "Shipping method")
        pickup = next(option for option in shipping["options"] if option["label"] == "Express pickup")
        require(pickup["value"] == "express" and not pickup["disabled"], "Express pickup was not reported as selectable")
        require(self.data("page_interact", action="select", documentId=document,
                          ref=shipping["ref"], optionIndexes=[pickup["index"]])["applied"],
                "Select did not accept the option")
        notes = self.find_control(document, "Delivery notes")
        require(self.data("page_interact", action="fill", documentId=document, ref=notes["ref"], text="Use side door")["applied"],
                "Contenteditable did not accept plain text")
        value = self.data("console_evaluate", script="document.querySelector('#shipping').selectedIndex + ':' + document.querySelector('#notes').textContent")
        require(value["result"] == f"{pickup['index']}:Use side door", "Page did not retain the selected option and edited text")
        button = self.find_control(document, "Confirm shipment")
        self.data("page_interact", action="click", documentId=document, ref=button["ref"])
        for _ in range(20):
            result = self.call("walnut_browser", action="status")
            navigation = result["navigation"]
            if (navigation.get("url", "").endswith("/checkout-receipt")
                    and navigation.get("phase") in ("finished", "failed")
                    and result.get("documentId")
                    and result.get("documentId") != document):
                break
            time.sleep(0.25)
        else:
            raise RuntimeError("Submitting the form did not commit the receipt page")
        require(navigation.get("phase") == "finished" and navigation.get("httpStatus") == 200,
                f"Receipt navigation status: {navigation}")
        receipt = self.data("page_interact", action="observe", documentId=result["documentId"])
        require("WALNUT-6205" in receipt["text"], "Visible receipt number did not match")
        print(json.dumps({"passed": "input, select, contenteditable, submit and receipt"}), flush=True)

    def verify_capture(self):
        self.open("/agent-e2e")
        png = self.data("walnut_screenshot", saveToPhotos=False)
        verify_page_png(png["path"])
        print(json.dumps({"passed": "WKWebView screenshot with visible page text", "png": png["path"]}), flush=True)
        self.data("walnut_recording", action="start", saveToPhotos=False)
        time.sleep(2)
        self.data("walnut_recording", action="stop", saveToPhotos=False)
        for _ in range(30):
            if self.data("walnut_recording", action="status")["available"]:
                break
            time.sleep(0.25)
        movie = self.data("walnut_recording", action="read")
        with Path(movie["path"]).open("rb") as media:
            require(media.read(8)[4:] == b"ftyp", "Recording is not a QuickTime movie")
        print(json.dumps({"passed": "WKWebView screenshot and recording", "png": png["path"], "video": movie["path"]}), flush=True)

    def verify_safari(self):
        page = self.open("/agent-e2e-redirect", mode="safarivc")
        navigation = page["navigation"]
        require(page["mode"] == "safarivc" and navigation["phase"] == "finished", f"SafariVC load failed: {navigation}")
        require(urlsplit(navigation.get("url", "")).path == "/agent-e2e", f"SafariVC redirect not observed: {navigation}")
        capabilities = self.data("walnut_capabilities")
        require(capabilities["mode"] == "safarivc"
                and {"sources_list", "walnut_panel"}.issubset(capabilities["unavailable"])
                and "wait" in capabilities["unavailableActions"]["walnut_browser"],
                "SafariVC did not report its unavailable tools")
        print(json.dumps({"passed": "SafariVC redirect, load and capability restrictions"}), flush=True)
        png = self.data("walnut_screenshot", saveToPhotos=False)
        require(png.get("captureScope") == "hostWindow", "SafariVC did not report the host-window capture scope")
        verify_page_png(png["path"])
        print(json.dumps({"passed": "SafariVC host-window screenshot with visible page text", "png": png["path"]}), flush=True)


async def verify_engine(args):
    command = [args.cli, "inspect", "--udid", args.udid]
    if args.usb:
        command.append("--usb")
    if args.wifi:
        command.append("--wifi")
    process = await asyncio.create_subprocess_exec(
        *command, stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, limit=8 * 1024 * 1024,
        start_new_session=True
    )
    replies = {}
    pauses = []
    next_id = 0

    async def receive(predicate, timeout=100):
        async def read_packets():
            while line := await process.stdout.readline():
                packet = json.loads(line)
                require(packet.get("event") != "revoked", "The phone revoked the WebKit document grant")
                if packet.get("event") == "error":
                    raise RuntimeError(packet.get("error", "Web Inspector stopped"))
                if predicate(packet):
                    return packet
                if "id" in packet:
                    replies[packet["id"]] = packet
                elif packet.get("method") == "Debugger.paused":
                    pauses.append(packet)
                require(len(replies) + len(pauses) <= 16, "Unexpected inspector packets")
            raise RuntimeError("Web Inspector closed before replying")

        return await asyncio.wait_for(read_packets(), timeout=timeout)

    async def send(method, **params):
        nonlocal next_id
        next_id += 1
        print(json.dumps({"inspector": method, "id": next_id}), flush=True)
        request = {"id": next_id, "method": method, "params": params}
        process.stdin.write(json.dumps(request).encode() + b"\n")
        await process.stdin.drain()
        return next_id

    async def result(identifier):
        packet = replies.pop(identifier, None) or await receive(lambda item: item.get("id") == identifier)
        require("error" not in packet, packet.get("error", {}).get("message", "Inspector request failed"))
        return packet["result"]

    async def call(method, **params):
        return await result(await send(method, **params))

    async def paused():
        packet = pauses.pop(0) if pauses else await receive(lambda item: item.get("method") == "Debugger.paused")
        frame = packet["params"]["callFrames"][0]
        require(frame["functionName"] == "walnutBreakpointFixture", "Paused outside the fixture function")
        return frame

    try:
        ready = await receive(lambda packet: packet.get("event") == "ready", timeout=180)
        require(ready.get("protocol") == "cdp", "Walnut did not open its WebKit inspector")
        tree = await call("Page.getResourceTree")
        frame = tree["frameTree"]["frame"]
        origin = args.origin.rstrip("/")
        require(frame["url"] == origin + "/agent-e2e", "Open the /agent-e2e fixture in Walnut before running this suite")
        resource = await call("Page.getResourceContent", frameId=frame["id"], url=frame["url"])
        html = base64.b64decode(resource["content"]).decode() if resource["base64Encoded"] else resource["content"]
        require(resource.get("retrieval") == "webkit-resource" and "Walnut developer tools verification" in html,
                "WebKit did not return the retained fixture document")

        await call("Debugger.enable")
        # The fixture declares the first executable statement on zero-based line 14.
        breakpoint = await call("Debugger.setBreakpointByUrl", lineNumber=14, url=origin + "/agent-e2e.js")
        require(breakpoint.get("locations"), "WebKit did not bind a breakpoint to the fixture script")
        evaluation = await send("Runtime.evaluate", expression="walnutBreakpointFixture(21)", returnByValue=True)
        initial = await paused()
        value = await call("Debugger.evaluateOnCallFrame", callFrameId=initial["callFrameId"], expression="value")
        require(value.get("result", {}).get("value") == 21, "WebKit did not expose the paused frame's argument")
        await call("Debugger.stepOver")
        stepped = await paused()
        require(stepped["location"]["lineNumber"] > initial["location"]["lineNumber"], "The debugger did not advance")
        await call("Debugger.resume")
        value = await result(evaluation)
        require(value.get("result", {}).get("value") == 43, "The original evaluation did not finish after resume")
    except BaseException:
        # Stop the adapter too so it can detach from a paused page.
        with contextlib.suppress(ProcessLookupError):
            os.killpg(process.pid, signal.SIGTERM)
        raise
    finally:
        process.stdin.close()
        try:
            await asyncio.wait_for(process.wait(), timeout=10)
        except asyncio.TimeoutError:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGTERM)
            try:
                await asyncio.wait_for(process.wait(), timeout=20)
            except asyncio.TimeoutError:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGKILL)
                await process.wait()
    require(process.returncode == 0, "Web Inspector failed to detach cleanly")
    print(json.dumps({"passed": "WebKit retained HTML, breakpoint, frame scope, step and resume"}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("origin", help="LAN origin of the synthetic checkout.py fixture")
    parser.add_argument("--cli", default="walnut-agent")
    connection = parser.add_mutually_exclusive_group()
    connection.add_argument("--usb", action="store_true")
    connection.add_argument("--wifi", action="store_true", help="Use Apple-trusted Wi-Fi for the engine suite")
    parser.add_argument("--udid", help="Select the iPhone by UDID")
    suites = ("diagnostics", "tools", "capture", "controls", "safari")
    option_suites = ("log_options", "settings", "auxiliary", "documents", "storage_options", "startup_options")
    parser.add_argument("--suite", choices=(*suites, *option_suites, "engine"), action="append", help="Run a specific suite. May be repeated.")
    parser.add_argument("--alternate-origin", help="Second checkout fixture origin for --suite log_options")
    args = parser.parse_args()
    if "engine" in (args.suite or []):
        if args.suite != ["engine"] or not args.udid:
            parser.error("The engine suite runs separately and requires --udid")
        asyncio.run(verify_engine(args))
        return
    if args.wifi:
        parser.error("--wifi requires --suite engine")
    if args.udid and not args.usb:
        parser.error("--udid requires --usb")
    if "log_options" in (args.suite or []):
        if not args.alternate_origin or urlsplit(args.alternate_origin).netloc == urlsplit(args.origin).netloc:
            parser.error("--suite log_options requires a checkout fixture at a different --alternate-origin (e.g. a different port)")
    command = [args.cli, "session"] + (["--usb"] if args.usb else [])
    if args.udid:
        command += ["--udid", args.udid]
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, encoding="utf-8")
    verification = Verification(process, args.origin.rstrip("/"), (args.alternate_origin or "").rstrip("/"))
    try:
        verification.verify(args.suite or suites)
    finally:
        print(json.dumps({"exercised": sorted(verification.exercised),
                          "notExercised": sorted(verification.tools - verification.exercised)}), flush=True)
        process.stdin.close()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait(timeout=5)


if __name__ == "__main__":
    main()
