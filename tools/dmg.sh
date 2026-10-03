#!/bin/bash
# dist/<Arq>/CAPM Explainer.app -> dist/CAPM-Explainer-<Arq>.dmg (AppleSilicon e Intel): ventana con fondo
# (arrastrar a Applications + "Open Anyway"). Después de ./build.sh. Mismo método que Guardados:
# bounds dos veces o el Finder no guarda el tamaño. Paleta oro/negro de CAPM sobre crema.
set -e
cd "$(dirname "$0")/.."
APP="CAPM Explainer"; VOL="CAPM Explainer"

fondo() {  # $1 = línea de arquitectura que va bajo el título
python3 - "$1" <<'EOF'
import sys
from PIL import Image, ImageDraw, ImageFont
W, H, S = 660, 520, 2
GOLD, BRONZE, CREAM, INK, MUTED = "#C9A86A", "#8A6A2C", "#F7F1E6", "#1F1A12", "#6B5D45"
im = Image.new("RGB", (W*S, H*S), CREAM); d = ImageDraw.Draw(im)
F = lambda sz, b=False: ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", sz*S, index=1 if b else 0)
d.line([(255*S, 150*S), (405*S, 150*S)], fill=BRONZE, width=6*S)
d.polygon([(405*S, 135*S), (430*S, 150*S), (405*S, 165*S)], fill=BRONZE)
d.text((W*S//2, 34*S), "1 · Drag CAPM Explainer into Applications", font=F(20, True), fill=INK, anchor="mm")
d.text((W*S//2, 58*S), sys.argv[1], font=F(13), fill=BRONZE, anchor="mm")
y = 270
d.rounded_rectangle([(30*S, y*S), (630*S, (y+225)*S)], radius=16*S, fill="#FBF7EF", outline=GOLD, width=2*S)
d.text((52*S, (y+22)*S), "2 · The first time, macOS stops it (that's normal)", font=F(18, True), fill=INK)
lines = ["It says Apple could not verify \"CAPM Explainer\".",
         "The app isn't notarized by Apple ($99/year), like most indie apps.", "",
         "Click \"Done\", then:",
         "System Settings  ›  Privacy & Security  ›",
         "scroll to the bottom  ›  \"Open Anyway\"  ›  confirm.", "",
         "Only once. After that it opens with a double-click."]
for i, l in enumerate(lines):
    d.text((52*S, (y+58+i*20)*S), l, font=F(14, i in (4, 5)), fill=INK if i in (4, 5) else MUTED)
im.save("build/bg@2x.png"); im.resize((W, H), Image.LANCZOS).save("build/bg.png")
EOF
}

hacer() {  # $1 = AppleSilicon | Intel   $2 = texto de arquitectura
  local N=$1 ST=build/dmg_stage OUT="dist/CAPM-Explainer-$1.dmg"
  hdiutil detach "/Volumes/$VOL" -force -quiet 2>/dev/null || true
  rm -rf $ST build/rw.dmg; mkdir -p $ST/.background
  fondo "$2"
  tiffutil -cathidpicheck build/bg.png build/bg@2x.png -out $ST/.background/bg.tiff >/dev/null
  ditto "dist/$N/$APP.app" "$ST/$APP.app"
  ln -s /Applications $ST/Applications
  hdiutil create -srcfolder $ST -volname "$VOL" -fs HFS+ -format UDRW -size 400m build/rw.dmg >/dev/null
  hdiutil attach build/rw.dmg -noautoopen -quiet; sleep 2
  osascript <<OSA
tell application "Finder"
  tell disk "$VOL"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set vo to the icon view options of container window
    set arrangement of vo to not arranged
    set icon size of vo to 96
    set text size of vo to 13
    set background picture of vo to file ".background:bg.tiff"
    set position of item "$APP.app" of container window to {170, 150}
    set position of item "Applications" of container window to {500, 150}
    set the bounds of container window to {200, 120, 860, 700}
    delay 1
    set the bounds of container window to {200, 120, 860, 700}
    update without registering applications
    delay 3
    close
  end tell
end tell
OSA
  sleep 2; sync; hdiutil detach "/Volumes/$VOL" -quiet; rm -f "$OUT"
  hdiutil convert build/rw.dmg -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null; rm build/rw.dmg
  ls -la "$OUT"
}

hacer AppleSilicon "For Macs with Apple Silicon (M1 and later)"
hacer Intel "For Macs with an Intel processor"
