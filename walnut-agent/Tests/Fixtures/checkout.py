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

    def respond(self, status, content, reason=None, javascript=False):
        body = content.encode()
        self.send_response(status, reason)
        self.send_header("Content-Type", "text/javascript" if javascript else "text/html; charset=utf-8")
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
