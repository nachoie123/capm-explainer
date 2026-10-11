#!/usr/bin/env python3
"""Regenera Fixtures/python.json con los números del capm.py de hoy (necesita red)."""
import json, sys, pathlib, numpy as np
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[3]))
import capm
out = {}
for t in ["KO", "ITX.MC", "SHEL.L"]:
    d = capm.capm(t)
    s = capm.monthly_returns(t); m = capm.monthly_returns(d["index"])
    a, b = s.align(m, join="inner")
    d["series"] = [{"month": str(i), "stock": float(x), "market": float(y)} for i, x, y in zip(a.index, a.values, b.values)]
    d["corr"] = float(np.sqrt(d["r2"]))
    for k in ("rf", "beta", "dy", "g", "rm", "mrp", "er", "r2"): d[k] = float(d[k])
    out[t] = d
pathlib.Path(__file__).with_name("CAPMKitTests").joinpath("Fixtures", "python.json").write_text(json.dumps(out, indent=1))
print("ok", {t: round(v["er"], 4) for t, v in out.items()})
