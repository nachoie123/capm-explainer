#!/usr/bin/env python3
"""Servidor mínimo (stdlib) para el explicador CAPM.
    /                 -> index.html
    /api/capm?ticker=KO&rf=&g=  -> JSON con todos los pasos
Uso: python3 server.py   (abre http://localhost:8000)
"""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

import capm

HERE = os.path.dirname(os.path.abspath(__file__))


class H(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        if u.path in ("/", "/index.html"):
            with open(os.path.join(HERE, "index.html"), "rb") as f:
                self._send(200, f.read(), "text/html")
            return
        if u.path == "/api/capm":
            q = parse_qs(u.query)
            ticker = (q.get("ticker", [""])[0]).strip().upper()
            rf = float(q["rf"][0]) if q.get("rf") else None
            g = float(q["g"][0]) if q.get("g") else None
            try:
                data = capm.capm(ticker, rf, g)
                self._send(200, json.dumps(data).encode())
            except Exception as e:
                self._send(400, json.dumps({"error": str(e)}).encode())
            return
        self._send(404, b'{"error":"not found"}')

    def log_message(self, *a):  # silencio
        pass


if __name__ == "__main__":
    print("CAPM Explainer -> http://localhost:8000  (Ctrl+C para parar)")
    ThreadingHTTPServer(("127.0.0.1", 8000), H).serve_forever()
