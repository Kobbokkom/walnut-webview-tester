"""Serve checkout diagnostics and an interactive Walnut Agent test page."""

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs


class Checkout(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/checkout-a":
            mobile = "iPhone" in self.headers.get("User-Agent", "")
            self.respond(
                403 if mobile else 200,
                "" if mobile else '<main id="checkout-ready">Checkout ready</main>',
                "Mobile client unsupported" if mobile else None,
            )
        elif self.path == "/checkout-b":
            self.respond(
                200,
                '<main id="checkout"></main><script src="/checkout.js"></script>',
            )
        elif self.path == "/checkout.js":
            self.respond(200, "throw new TypeError('Checkout renderer unavailable');", javascript=True)
        elif self.path == "/agent-e2e":
            self.respond(200, """<!doctype html>
<html lang="en"><head><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Walnut developer tools verification</title>
<link rel="stylesheet" href="/agent-e2e.css"><script src="/agent-e2e.js" defer></script>
</head><body><header><h1>Walnut developer tools verification</h1>
<p>Walnut search needle. Walnut search needle.</p><img src="/missing-e2e-image"></header>
<main><h2>Test controls</h2><form action="/checkout-receipt" method="post">
<label for="reference">Delivery reference</label><input id="reference" name="reference" required>
<label for="shipping">Shipping method</label><select id="shipping" name="shipping">
<option value="standard">Standard</option><option value="express">Express</option>
<option value="express">Express pickup</option></select>
<label for="notes">Delivery notes</label><div id="notes" role="textbox" aria-label="Delivery notes" contenteditable="true"></div>
<button type="submit" disabled>Confirm shipment</button></form>
<label><input id="fragile" type="checkbox">Fragile test shipment</label>
<div id="scroll-region" style="height:120px;overflow:auto"><p style="height:400px">Nested scroll content</p><button>Nested action</button></div>
<iframe title="Test same-origin frame" src="/agent-e2e-frame"></iframe>
<p id="network-result">Waiting for fixture response</p>
</main></body></html>""")
        elif self.path == "/agent-e2e.js":
            self.respond(200, """console.info('Walnut E2E external script loaded');
console.group('Walnut E2E group'); console.warn('Walnut E2E warning'); console.groupEnd();
localStorage.setItem('walnut-e2e-local', 'local fixture value');
sessionStorage.setItem('walnut-e2e-session', 'session fixture value');
document.cookie = 'walnut-e2e-cookie=cookie-fixture; SameSite=Lax; path=/';
const reference = document.querySelector('#reference');
const confirm = document.querySelector('button[type="submit"]');
reference.addEventListener('input', () => { confirm.disabled = !reference.value.trim(); });
fetch('/agent-e2e-api', {method:'POST', headers:{'Content-Type':'application/json', 'X-Walnut-E2E':'fixture'},
body:JSON.stringify({reference:'WK-417'})}).then(response => response.json()).then(data => {
document.querySelector('#network-result').textContent = data.message;
console.log('Walnut E2E response', data);
});
function walnutBreakpointFixture(value) {
    const doubled = value * 2;
    return doubled + 1;
}
window.walnutBreakpointFixture = walnutBreakpointFixture;
""", javascript=True)
        elif self.path == "/agent-e2e.css":
            self.respond(200, """body { font: 18px system-ui; margin: 24px; }
header { min-height: 110vh; }
label, input, select, button, [contenteditable] { display: block; margin: 12px 0; font: inherit; }
[contenteditable] { min-height: 44px; border: 1px solid #777; }
iframe { width: 100%; height: 180px; }""", content_type="text/css; charset=utf-8")
        elif self.path == "/agent-e2e-frame":
            self.respond(200, """<!doctype html><html lang="en"><body>
<label for="frame-note">Frame note</label><input id="frame-note">
<button onclick="document.querySelector('#frame-result').textContent = document.querySelector('#frame-note').value">Apply frame note</button>
<p id="frame-result"></p></body></html>""")
        elif self.path == "/agent-e2e-redirect":
            self.send_response(302)
            self.send_header("Location", "/agent-e2e")
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif self.path == "/checkout-interaction":
            self.respond(200, """<!doctype html>
<html lang="en"><head><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Test shipment checkout</title>
<style>
body { font: 18px system-ui; margin: 24px; }
header { min-height: 125vh; }
label, input, button { display: block; margin: 12px 0; font: inherit; }
</style></head><body>
<header><h1>Test shipment checkout</h1><p>The shipment form is below this guide.</p></header>
<main><h2>Confirm your test shipment</h2>
<form action="/checkout-receipt" method="post">
<label for="reference">Delivery reference</label>
<input id="reference" name="reference" type="text" required>
<button type="submit" disabled>Confirm shipment</button>
</form></main>
<script>
const reference = document.querySelector('#reference');
const confirm = document.querySelector('button');
reference.addEventListener('input', () => { confirm.disabled = !reference.value.trim(); });
</script>
</body></html>""")
        else:
            self.respond(404, "")

    def do_POST(self):
        if self.path == "/agent-e2e-api":
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 4096:
                self.respond(413, "")
                return
            self.rfile.read(length)
            self.respond(201, '{"message":"Walnut E2E network ready","requestId":"walnut-fixture-201"}',
                         content_type="application/json")
            return
        if self.path != "/checkout-receipt":
            self.respond(404, "")
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            fields = parse_qs(self.rfile.read(length).decode()) if 0 < length <= 4096 else {}
        except (UnicodeDecodeError, ValueError):
            fields = {}
        if fields.get("reference") != ["WK-417"]:
            self.respond(422, "<h1>Delivery reference rejected</h1>")
            return
        self.respond(200, """<!doctype html>
<html lang="en"><head><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Shipment confirmed</title></head><body>
<h1>Shipment confirmed</h1><p>Receipt WALNUT-6205</p>
</body></html>""")

    def respond(self, status, content, reason=None, javascript=False, content_type=None):
        body = content.encode()
        self.send_response(status, reason)
        self.send_header("Content-Type", content_type or ("text/javascript" if javascript else "text/html; charset=utf-8"))
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8874, type=int)
    args = parser.parse_args()
    with ThreadingHTTPServer((args.host, args.port), Checkout) as server:
        server.serve_forever()
