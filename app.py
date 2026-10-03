#!/usr/bin/env python3
"""CAPM Explainer como app de Mac: el mismo server.py, en una ventana propia.

    python3 app.py               -> ventana "CAPM Explainer"
    python3 app.py --selftest X  -> sin ventana: prueba el servidor, escribe el JSON en X y sale

Servidor en 127.0.0.1 con puerto libre (0) y solo acepta Host 127.0.0.1:<puerto> o
localhost:<puerto> (anti DNS-rebinding). La caché de yfinance va a
~/Library/Application Support/CAPM Explainer/, nunca dentro del .app.
Al cerrar la ventana, la app termina.
"""
import http.client
import json
import os
import socket
import sys
import threading
import time
from http.server import ThreadingHTTPServer
from pathlib import Path

import yfinance as yf

import server

DATA = Path.home() / "Library" / "Application Support" / "CAPM Explainer"
DATA.mkdir(parents=True, exist_ok=True)
yf.set_tz_cache_location(str(DATA / "yfinance-cache"))  # zona horaria + cookies de Yahoo


class Local(server.H):
    def do_GET(self):
        if self.headers.get("Host") not in self.server.hosts:
            self._send(403, b'{"error":"host no permitido"}')
            return
        super().do_GET()


def start():
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Local)
    port = srv.server_address[1]
    srv.hosts = {f"127.0.0.1:{port}", f"localhost:{port}"}
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, port


def get(port, path, host=None, timeout=10):
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    c.request("GET", path, headers={"Host": host or f"127.0.0.1:{port}"})
    r = c.getresponse()
    return r.status, r.getheader("Content-Type") or "", r.read()


def selftest(out):
    """Lo básico sin nadie delante: página, Host falso y un CAPM real de KO si hay red."""
    srv, port = start()
    res = {"host": srv.server_address[0], "port": port}
    s, ct, body = get(port, "/")
    res["index"] = {"status": s, "html": "text/html" in ct and b"CAPM Explainer" in body}
    res["host_falso"] = get(port, "/", host="evil.example:80")[0]
    res["host_falso_api"] = get(port, "/api/capm?ticker=KO", host=f"evil.example:{port}")[0]
    res["localhost_ok"] = get(port, "/", host=f"localhost:{port}")[0]
    try:
        socket.create_connection(("query1.finance.yahoo.com", 443), timeout=5).close()
        res["red"] = True
    except OSError:
        res["red"] = False
    if res["red"]:
        t = time.time()
        s, _, body = get(port, "/api/capm?ticker=KO", timeout=90)
        d = json.loads(body)
        res["ko"] = {"status": s, "secs": round(time.time() - t, 1), "error": d.get("error"),
                     **{k: d.get(k) for k in ("name", "ccy", "rf", "beta", "rm", "er", "months")}}
        ok_ko = s == 200 and isinstance(d.get("er"), float) and 0 < d["beta"] < 3 and -0.2 < d["er"] < 0.5
    else:
        res["ko"] = "sin red"
        ok_ko = True
    res["cache"] = sorted(p.name for p in (DATA / "yfinance-cache").rglob("*") if p.is_file())
    res["ok"] = (res["host"] == "127.0.0.1" and res["index"] == {"status": 200, "html": True}
                 and res["host_falso"] == 403 and res["host_falso_api"] == 403
                 and res["localhost_ok"] == 200 and ok_ko)
    Path(out).write_text(json.dumps(res, ensure_ascii=False, indent=1))
    return res["ok"]


def main():
    if "--selftest" in sys.argv:
        i = sys.argv.index("--selftest")
        out = sys.argv[i + 1] if len(sys.argv) > i + 1 else str(DATA / "selftest.json")
        os._exit(0 if selftest(out) else 1)
    import webview
    _, port = start()
    webview.create_window("CAPM Explainer", f"http://127.0.0.1:{port}/", width=1180, height=860,
                          min_size=(760, 600), background_color="#0A0908")
    webview.start()
    os._exit(0)  # ventana cerrada -> fuera todo (servidor e hilos de yfinance incluidos)


if __name__ == "__main__":
    main()
