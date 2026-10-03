#!/bin/bash
# Empaqueta "CAPM Explainer.app" DOS veces en dist/: Apple Silicon (arm64) e Intel (x86_64).
# numpy y pandas no tienen ruedas universal2, así que cada arquitectura lleva su venv y su app.
# Al final pasa tools/seguridad.py sobre las dos y falla si algo no está bien.
set -e
cd "$(dirname "$0")"

# Nunca empaquetar una carpeta de trabajo: todo lo que no esté ignorado tiene que estar commiteado.
SUCIO=$(git status --porcelain)
if [ -n "$SUCIO" ]; then
  echo "build.sh: hay ficheros sin commitear, no empaqueto:"; echo "$SUCIO"; exit 1
fi

# Python de python.org (universal2): sirve para las dos arquitecturas con `arch`.
PY=/Library/Frameworks/Python.framework/Versions/3.12/bin/python3.12
[ -x $PY ] || { echo "Falta $PY (python.org 3.12, universal2)"; exit 1; }
arch -x86_64 /usr/bin/true 2>/dev/null || { echo "Falta Rosetta 2 para la build Intel (softwareupdate --install-rosetta)"; exit 1; }

# icono: build_assets/icon.png -> build/icon.icns
mkdir -p build; rm -rf build/icon.iconset; mkdir build/icon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s build_assets/icon.png --out build/icon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build_assets/icon.png --out build/icon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/icon.iconset -o build/icon.icns

construir() {  # $1 = arm64 | x86_64   $2 = venv   $3 = carpeta en dist/ (AppleSilicon | Intel)
  local A=$1 V=$2 N=$3
  [ -x $V/bin/python ] || arch -$A $PY -m venv $V
  arch -$A $V/bin/python -m pip install -q -r requirements-app.txt
  arch -$A $V/bin/python test_capm.py
  rm -rf "build/$N" "dist/$N"
  ARCH=$A arch -$A $V/bin/pyinstaller --noconfirm --clean --distpath "dist/$N" --workpath "build/$N" \
    "CAPM Explainer.spec" > "build/pyinstaller-$N.log" 2>&1 || { tail -30 "build/pyinstaller-$N.log"; exit 1; }
  tail -1 "build/pyinstaller-$N.log"
  rm -rf "dist/$N/CAPM Explainer"   # la carpeta suelta de COLLECT: solo queda el .app
}
construir arm64 .venv AppleSilicon
construir x86_64 .venv-x86_64 Intel

.venv/bin/python tools/seguridad.py
