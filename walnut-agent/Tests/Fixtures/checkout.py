"""Serve two matching checkout symptoms for a Walnut Agent diagnostic test."""

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


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
        else:
            self.respond(404, "")

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
