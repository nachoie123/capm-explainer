# -*- mode: python ; coding: utf-8 -*-
# Construir con ./build.sh, que pone ARCH (arm64 o x86_64): una app por arquitectura,
# porque numpy/pandas no tienen ruedas universal2.
import os

ARCH = os.environ["ARCH"]
a = Analysis(['app.py'], pathex=[], binaries=[], datas=[('index.html', '.')],
             hiddenimports=[], hookspath=[], hooksconfig={}, runtime_hooks=[],
             excludes=['tkinter'], noarchive=False, optimize=0)
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name='CAPM Explainer', debug=False,
          bootloader_ignore_signals=False, strip=False, upx=False, console=False,
          disable_windowed_traceback=False, argv_emulation=False, target_arch=ARCH,
          codesign_identity=None, entitlements_file=None, icon=['build/icon.icns'])
coll = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False, upx_exclude=[], name='CAPM Explainer')
app = BUNDLE(coll, name='CAPM Explainer.app', icon='build/icon.icns',
             bundle_identifier='com.nachosanbenito.capmexplainer',
             info_plist={'CFBundleShortVersionString': '1.0.0', 'NSHighResolutionCapable': True,
                         'LSMinimumSystemVersion': '11.0', 'NSHumanReadableCopyright': 'CAPM Explainer'})
