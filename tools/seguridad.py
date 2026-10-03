#!/usr/bin/env python3
"""Chequeo de seguridad de las dos apps de dist/, ejecutado de verdad. Escribe docs/seguridad.md.

  .venv/bin/python tools/seguridad.py      (lo llama build.sh al final)

Para cada app (Apple Silicon e Intel):
(a) Abre TODO el paquete (también el archivo de PyInstaller que va dentro del ejecutable
    y cada módulo de su PYZ) y cuenta cuántas veces sale: cada línea de
    ~/.config/personal-scan/patterns.txt (datos personales de Nacho; fuera del repo, no se
    imprime nunca, solo "línea N"), la ruta de su carpeta personal, patrones de claves
    (Gemini, OpenAI, Anthropic, GitHub, ElevenLabs) y ficheros de datos que no deben ir
    (*.db, *.sqlite, config.json, .env, *.key, CVs).
(b) Arquitecturas con `lipo -archs` de cada binario: todos deben ser SOLO de la
    arquitectura de esa app (arm64 o x86_64), sin mezclas.
(c) Lanza el ejecutable empaquetado con --selftest (sin ventana; la de Intel corre por
    Rosetta) y lee su JSON: servidor en 127.0.0.1, página 200 con HTML, Host falso -> 403
    (también en /api), localhost:<puerto> -> 200 y un CAPM real de KO contra Yahoo si hay
    red (sin red queda marcado "sin red" y no falla).
Sale con código 1 si algo falla.
"""
import json
import re
import subprocess
import sys
import zipfile
import zlib
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
NAME = "CAPM Explainer"
APPS = [("Apple Silicon", HERE / "dist" / "AppleSilicon" / f"{NAME}.app", "arm64"),
        ("Intel", HERE / "dist" / "Intel" / f"{NAME}.app", "x86_64")]
PATTERNS = Path.home() / ".config" / "personal-scan" / "patterns.txt"
KEYS = {"clave de Gemini (AIza…)": rb"AIza[0-9A-Za-z_\-]{35}",
        # sin letra delante: "Asterisk-linking-protocols-exception" (licencia SPDX de packaging) no es una clave
        "clave de OpenAI (sk-…)": rb"(?<![A-Za-z0-9])sk-[A-Za-z0-9_\-]{20,}",
        "clave de Anthropic (sk-ant-)": rb"sk-ant-",
        "token de GitHub (ghp_)": rb"ghp_",
        "clave de ElevenLabs (xi-api)": rb"xi-api"}
DATAFILES = re.compile(r"(?i)(\.db|\.sqlite3?|\.key|(^|/)config\.json|(^|/)\.env|(^|/)(cv|curriculum|resume)[^/]*\.(pdf|docx?))$")


def bundle_blobs(app: Path):
    """(nombre, bytes) de cada fichero del .app, con los archivos de PyInstaller abiertos."""
    from PyInstaller.archive.readers import CArchiveReader, ZlibArchiveReader
    for f in app.rglob("*"):
        if not f.is_file() or f.is_symlink():
            continue
        data = f.read_bytes()
        yield str(f.relative_to(app)), data
        if f.suffix == ".zip":
            with zipfile.ZipFile(f) as z:
                for n in z.namelist():
                    yield f"{f.name}!{n}", z.read(n)
        if f.name == NAME and f.parent.name == "MacOS":
            ca = CArchiveReader(str(f))
            for name in ca.toc:
                blob = ca.extract(name) or b""
                yield f"exe!{name}", blob
                if name.endswith(".pyz") or name.startswith("PYZ"):
                    tmp = HERE / "build" / "_pyz.tmp"
                    tmp.write_bytes(blob)
                    z = ZlibArchiveReader(str(tmp))
                    for mod in z.toc:
                        try:
                            code = z.extract(mod, raw=True)
                        except TypeError:
                            code = z.extract(mod)
                        if isinstance(code, bytes):
                            try:
                                code = zlib.decompress(code)
                            except zlib.error:
                                pass
                            yield f"pyz!{mod}", code
                        else:
                            import marshal
                            yield f"pyz!{mod}", marshal.dumps(code) if code else b""
                    tmp.unlink()


def searches():
    """{etiqueta: [patrones]}. Los valores de patterns.txt no se imprimen nunca: solo 'línea N'."""
    s = {}
    if PATTERNS.exists():
        for i, line in enumerate(PATTERNS.read_text().splitlines(), 1):
            if line.strip() and not line.lstrip().startswith("#"):
                s[f"patterns.txt línea {i}"] = [line.strip().lower().encode()]
    s[f"ruta de la carpeta personal (/Users/{Path.home().name})"] = [str(Path.home()).lower().encode()]
    for label, rx in KEYS.items():
        s[label] = [re.compile(rx)]
    return s


def scan(app):
    pats = searches()
    hits = {k: {} for k in pats}
    datafiles, files, total = [], 0, 0
    for name, data in bundle_blobs(app):
        files += 1
        total += len(data)
        if DATAFILES.search(name):
            datafiles.append(name)
        low = data.lower()
        for label, plist in pats.items():
            n = sum(len(p.findall(data)) if hasattr(p, "findall") else low.count(p) for p in plist)
            if n:
                hits[label][name] = n
    return files, total, hits, datafiles, PATTERNS.exists()


def archs(app):
    out = {}
    for f in app.rglob("*"):
        if f.is_file() and not f.is_symlink() and (f.suffix in (".so", ".dylib") or f.parent.name == "MacOS"
                                                   or f.name == "Python"):
            r = subprocess.run(["lipo", "-archs", str(f)], capture_output=True, text=True)
            if r.returncode == 0:
                out[str(f.relative_to(app))] = r.stdout.strip()
    return out


def selftest(app, tag):
    out = HERE / "build" / f"selftest-{tag}.json"
    out.unlink(missing_ok=True)
    try:
        p = subprocess.run([str(app / "Contents" / "MacOS" / NAME), "--selftest", str(out)],
                           capture_output=True, text=True, timeout=240)
        code = p.returncode
    except subprocess.TimeoutExpired:
        code = "timeout"
    st = json.loads(out.read_text()) if out.exists() else {"ok": False, "error": "la app no escribió el JSON"}
    st["exit"] = code
    return st


def main():
    mark = lambda b: "OK" if b else "FALLA"
    L = [f"# Chequeo de seguridad de {NAME}.app", "",
         f"Generado por `tools/seguridad.py` el {datetime.now():%Y-%m-%d %H:%M}. Todo lo de abajo es salida"
         " real del script, no texto escrito a mano.", ""]
    rows, detail, all_ok = [], [], True
    for label, app, want in APPS:
        if not app.exists():
            rows.append(f"| {label} | existe `{app.relative_to(HERE)}` | FALLA |")
            all_ok = False
            continue
        files, size, hits, datafiles, have_pat = scan(app)
        ar = archs(app)
        wrong = {k: v for k, v in ar.items() if v.split() != [want]}
        exe_arch = ar.get(f"Contents/MacOS/{NAME}")
        st = selftest(app, want)
        ok_a = have_pat and not any(hits.values())
        ok_df = not datafiles
        ok_b = bool(ar) and not wrong and exe_arch == want
        ok_c = st.get("ok") is True and st.get("exit") == 0
        all_ok &= ok_a and ok_df and ok_b and ok_c
        rows += [f"| {label} | (a) Sin datos personales, ruta personal ni claves en el paquete | {mark(ok_a)} |",
                 f"| {label} | (a) Sin ficheros de datos (*.db, *.sqlite, config.json, .env, *.key, CVs) | {mark(ok_df)} |",
                 f"| {label} | (b) Los {len(ar)} binarios son solo {want} | {mark(ok_b)} |",
                 f"| {label} | (c) Selftest de la app empaquetada (Host, página, CAPM de KO) | {mark(ok_c)} |"]
        ko = st.get("ko")
        detail += [f"## {label} — `{app.relative_to(HERE)}`", "",
                   f"Ficheros revisados: {files} (incluye cada módulo del PYZ dentro del ejecutable),"
                   f" {size / 1e6:.1f} MB descomprimidos.", "",
                   "### (a) Lo buscado y cuántas veces sale", ""]
        if not have_pat:
            detail.append(f"- **No existe {PATTERNS}**: no se pudieron buscar los datos personales.")
        for k, v in hits.items():
            detail.append(f"- {k}: **{sum(v.values())}**" + (f" en {', '.join(list(v)[:5])}" if v else ""))
        detail += [f"- Ficheros de datos: **{len(datafiles)}**" + (f" ({', '.join(datafiles[:5])})" if datafiles else ""), "",
                   "### (b) Arquitecturas (`lipo -archs`)", "",
                   f"- Ejecutable principal: `{exe_arch}`",
                   f"- Binarios revisados: {len(ar)}; de otra arquitectura o mezclados: {len(wrong)}"
                   + (f" ({', '.join(f'{k}={v}' for k, v in list(wrong.items())[:5])})" if wrong else ""), "",
                   "### (c) Selftest", "",
                   f"`{NAME} --selftest` (código de salida {st.get('exit')}):", "",
                   f"- Servidor en `{st.get('host')}`, puerto libre {st.get('port')}",
                   f"- `GET /` → {st.get('index')}",
                   f"- Host falso `evil.example:80` → {st.get('host_falso')}; en `/api/capm` → {st.get('host_falso_api')}",
                   f"- Host `localhost:<puerto>` → {st.get('localhost_ok')}",
                   f"- Red hacia Yahoo: {st.get('red')}",
                   "- CAPM de KO: " + (ko if isinstance(ko, str) else
                                        f"HTTP {ko.get('status')} en {ko.get('secs')} s — {ko.get('name')}: "
                                        f"β={ko.get('beta'):.3f}, Rf={ko.get('rf'):.2%}, E[Rm]={ko.get('rm'):.2%}, "
                                        f"E[R]={ko.get('er'):.2%} ({ko.get('months')} meses)"
                                        if ko and ko.get("status") == 200 else f"{ko}"),
                   f"- Caché de yfinance en ~/Library/Application Support/{NAME}/yfinance-cache: {st.get('cache')}", ""]
        print(f"{label}: datos {mark(ok_a)}, ficheros {mark(ok_df)}, arquitectura {mark(ok_b)} ({exe_arch}), "
              f"selftest {mark(ok_c)}")
    L += ["| App | Prueba | Resultado |", "|---|---|---|", *rows, ""] + detail
    (HERE / "docs" / "seguridad.md").write_text("\n".join(L))
    print("docs/seguridad.md escrito;", "TODO OK" if all_ok else "HAY FALLOS")
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
