# Chequeo de seguridad de CAPM Explainer.app

Generado por `tools/seguridad.py` el 2026-10-03 19:49. Todo lo de abajo es salida real del script, no texto escrito a mano.

| App | Prueba | Resultado |
|---|---|---|
| Apple Silicon | (a) Sin datos personales, ruta personal ni claves en el paquete | OK |
| Apple Silicon | (a) Sin ficheros de datos (*.db, *.sqlite, config.json, .env, *.key, CVs) | OK |
| Apple Silicon | (b) Los 139 binarios son solo arm64 | OK |
| Apple Silicon | (c) Selftest de la app empaquetada (Host, página, CAPM de KO) | OK |
| Intel | (a) Sin datos personales, ruta personal ni claves en el paquete | OK |
| Intel | (a) Sin ficheros de datos (*.db, *.sqlite, config.json, .env, *.key, CVs) | OK |
| Intel | (b) Los 139 binarios son solo x86_64 | OK |
| Intel | (c) Selftest de la app empaquetada (Host, página, CAPM de KO) | OK |

## Apple Silicon — `dist/AppleSilicon/CAPM Explainer.app`

Ficheros revisados: 2208 (incluye cada módulo del PYZ dentro del ejecutable), 124.1 MB descomprimidos.

### (a) Lo buscado y cuántas veces sale

- patterns.txt línea 1: **0**
- patterns.txt línea 2: **0**
- patterns.txt línea 3: **0**
- patterns.txt línea 4: **0**
- patterns.txt línea 5: **0**
- patterns.txt línea 6: **0**
- patterns.txt línea 7: **0**
- patterns.txt línea 8: **0**
- patterns.txt línea 9: **0**
- patterns.txt línea 10: **0**
- patterns.txt línea 11: **0**
- patterns.txt línea 12: **0**
- patterns.txt línea 13: **0**
- ruta de la carpeta personal (/Users/nachosanbenito): **0**
- clave de Gemini (AIza…): **0**
- clave de OpenAI (sk-…): **0**
- clave de Anthropic (sk-ant-): **0**
- token de GitHub (ghp_): **0**
- clave de ElevenLabs (xi-api): **0**
- Ficheros de datos: **0**

### (b) Arquitecturas (`lipo -archs`)

- Ejecutable principal: `arm64`
- Binarios revisados: 139; de otra arquitectura o mezclados: 0

### (c) Selftest

`CAPM Explainer --selftest` (código de salida 0):

- Servidor en `127.0.0.1`, puerto libre 56365
- `GET /` → {'status': 200, 'html': True}
- Host falso `evil.example:80` → 403; en `/api/capm` → 403
- Host `localhost:<puerto>` → 200
- Red hacia Yahoo: True
- CAPM de KO: HTTP 200 en 1.5 s — Coca-Cola Company (The): β=0.284, Rf=5.28%, E[Rm]=5.02%, E[R]=5.20% (59 meses)
- Caché de yfinance en ~/Library/Application Support/CAPM Explainer/yfinance-cache: ['cookies.db', 'cookies.db-shm', 'cookies.db-wal', 'tkr-tz.db', 'tkr-tz.db-shm', 'tkr-tz.db-wal']

## Intel — `dist/Intel/CAPM Explainer.app`

Ficheros revisados: 2210 (incluye cada módulo del PYZ dentro del ejecutable), 127.4 MB descomprimidos.

### (a) Lo buscado y cuántas veces sale

- patterns.txt línea 1: **0**
- patterns.txt línea 2: **0**
- patterns.txt línea 3: **0**
- patterns.txt línea 4: **0**
- patterns.txt línea 5: **0**
- patterns.txt línea 6: **0**
- patterns.txt línea 7: **0**
- patterns.txt línea 8: **0**
- patterns.txt línea 9: **0**
- patterns.txt línea 10: **0**
- patterns.txt línea 11: **0**
- patterns.txt línea 12: **0**
- patterns.txt línea 13: **0**
- ruta de la carpeta personal (/Users/nachosanbenito): **0**
- clave de Gemini (AIza…): **0**
- clave de OpenAI (sk-…): **0**
- clave de Anthropic (sk-ant-): **0**
- token de GitHub (ghp_): **0**
- clave de ElevenLabs (xi-api): **0**
- Ficheros de datos: **0**

### (b) Arquitecturas (`lipo -archs`)

- Ejecutable principal: `x86_64`
- Binarios revisados: 139; de otra arquitectura o mezclados: 0

### (c) Selftest

`CAPM Explainer --selftest` (código de salida 0):

- Servidor en `127.0.0.1`, puerto libre 56385
- `GET /` → {'status': 200, 'html': True}
- Host falso `evil.example:80` → 403; en `/api/capm` → 403
- Host `localhost:<puerto>` → 200
- Red hacia Yahoo: True
- CAPM de KO: HTTP 200 en 1.1 s — Coca-Cola Company (The): β=0.284, Rf=5.28%, E[Rm]=5.02%, E[R]=5.20% (59 meses)
- Caché de yfinance en ~/Library/Application Support/CAPM Explainer/yfinance-cache: ['cookies.db', 'cookies.db-shm', 'cookies.db-wal', 'tkr-tz.db', 'tkr-tz.db-shm', 'tkr-tz.db-wal']
