#!/usr/bin/env python3
"""CAPM — Asset price / return prediction desde datos de Yahoo Finance.

Fórmula (CAPM):
    E[R] = Rf + beta * (E[Rm] - Rf)

    Rf     = tasa libre de riesgo = yield del bono soberano a 10 años de la MONEDA
             de la acción (USD -> ^TNX en vivo; EUR/GBP -> perilla, ver REGION).
    beta   = SE CALCULA por regresión: cov(acción, mercado)/var(mercado) con retornos
             mensuales vs. el índice de la región. Funciona para cualquier empresa con
             histórico (incl. IPOs recientes). La beta es intrínsecamente histórica.
    E[Rm]  = retorno esperado del mercado, FORWARD (no media histórica): modelo de
             Gordon / retorno implícito -> E[Rm] = divyield*(1+g) + g, con el dividend
             yield del ETF de mercado de la región (Yahoo) y g = crecimiento nominal.
    MRP    = E[Rm] - Rf  (market risk premium)

Uso:
    python3 capm.py KO
    python3 capm.py ITX.MC
    python3 capm.py SHEL.L --rf 0.045 --g 0.033
"""
import argparse
import numpy as np
import yfinance as yf

# --- Perillas por región (moneda). El mercado y el índice no se ven en Yahoo por
#     sí solos; estos valores son las entradas económicas que hay que calibrar. ---
# Cada entrada: índice de mercado, ETF para dividend yield, rf (10Y soberano), g.
REGION = {
    "USD": {"index": "^GSPC",     "etf": "SPY",     "rf": None, "g": 0.040},  # rf vivo ^TNX
    "EUR": {"index": "^STOXX50E",  "etf": "EXW1.DE", "rf": 0.025, "g": 0.030}, # Bund ~2.5% (ajústalo)
    "GBP": {"index": "^FTSE",      "etf": "ISF.L",   "rf": 0.045, "g": 0.033}, # Gilt ~4.5% (ajústalo)
}
REGION["GBp"] = REGION["GBP"]  # Londres cotiza en peniques


def us_10y():
    """Yield del Tesoro USA a 10 años (^TNX), en tanto por uno. Dato vivo."""
    s = yf.Ticker("^TNX").history(period="5d")["Close"].dropna()
    if s.empty:
        raise ValueError("No pude leer el bono USA a 10 años (^TNX) ahora mismo. Prueba de nuevo.")
    return s.iloc[-1] / 100  # ^TNX viene en % (4.70 = 4.70%)


def monthly_returns(ticker, years=5):
    s = yf.Ticker(ticker).history(period=f"{years}y", interval="1mo")["Close"].pct_change().dropna()
    s.index = s.index.to_period("M")  # alinear por año-mes (evita desajustes de huso entre mercados)
    return s


def compute_beta(ticker, index):
    """beta = cov(acción, mercado)/var(mercado) con retornos mensuales alineados.
    Devuelve (beta, nº meses, corr) — corr mide la fiabilidad de la regresión."""
    s = monthly_returns(ticker)
    m = monthly_returns(index)
    a, b = s.align(m, join="inner")
    if len(a) < 12:
        raise ValueError(f"Histórico insuficiente ({len(a)} meses) para estimar beta.")
    cov = np.cov(a, b)  # mismo ddof en num y den -> pendiente OLS exacta
    beta = cov[0, 1] / cov[1, 1]
    corr = cov[0, 1] / np.sqrt(cov[0, 0] * cov[1, 1])  # correlación acción-mercado
    return beta, len(a), corr


def market_dividend_yield(etf):
    """Dividend yield del ETF de mercado, tanto por uno (proxy forward)."""
    i = yf.Ticker(etf).info
    y = i.get("yield")
    if y is None:
        dy = i.get("dividendYield")
        y = dy / 100 if dy else None
    if not y:
        raise ValueError(f"Sin dividend yield para {etf}.")
    return y


def expected_market_return(etf, g):
    """Gordon growth (retorno implícito, forward): E[Rm] = D0/P*(1+g) + g."""
    dy = market_dividend_yield(etf)
    return dy * (1 + g) + g


def capm(ticker, rf_override=None, g_override=None):
    info = yf.Ticker(ticker).info
    ccy = info.get("currency")
    if not ccy:
        raise ValueError(f"Ticker '{ticker}' no encontrado en Yahoo. ¿Está bien escrito?")
    if ccy not in REGION:
        raise ValueError(f"Mercado en {ccy} aún no soportado (soportados: USD, EUR, GBP). "
                         f"Usa una cotización en esas monedas.")
    reg = REGION[ccy]

    rf = rf_override if rf_override is not None else (us_10y() if reg["rf"] is None else reg["rf"])
    g = g_override if g_override is not None else reg["g"]

    beta, n, corr = compute_beta(ticker, reg["index"])
    dy = market_dividend_yield(reg["etf"])
    rm = dy * (1 + g) + g
    mrp = rm - rf
    er = rf + beta * mrp
    r2 = corr ** 2
    d = {
        "name": info.get("shortName", ticker), "ticker": ticker, "ccy": ccy,
        "index": reg["index"], "etf": reg["etf"], "months": n,
        "rf": rf, "beta": beta, "dy": dy, "g": g, "rm": rm, "mrp": mrp, "er": er, "r2": r2,
    }
    warns = []
    if n < 24:
        warns.append(f"Histórico corto ({n} meses, IPO reciente): la beta es poco fiable.")
    if abs(corr) < 0.15:
        warns.append(f"Beta poco fiable: {d['name']} apenas correlaciona con el mercado "
                     f"({reg['index']}, R²={r2:.0%}) — los datos de Yahoo para este valor son "
                     f"ruidosos. Tómalo como orientativo, no como una beta real.")
    if warns:
        d["warn"] = " ".join(warns)
    return d


def search_symbols(query, limit=8):
    """Símbolos de acciones (EQUITY) que Yahoo devuelve para un texto libre."""
    try:
        quotes = yf.Search(query, max_results=10).quotes
    except Exception:
        return []
    return [q["symbol"] for q in quotes
            if q.get("quoteType") == "EQUITY" and q.get("symbol")][:limit]


def analyze(query, rf_override=None, g_override=None):
    """Resuelve un nombre o ticker (p.ej. 'Repsol', 'REP.MC', 'Apple') a una acción
    en un mercado soportado y devuelve su CAPM. Prueba el texto tal cual y, si falla,
    los candidatos de la búsqueda de Yahoo hasta dar con uno que funcione."""
    query = (query or "").strip()
    if not query:
        raise ValueError("Escribe el nombre o el ticker de una empresa.")
    try:
        return capm(query, rf_override, g_override)  # respeta tickers exactos (KO, REP.MC)
    except ValueError:
        pass
    tried = {query.upper()}
    for sym in search_symbols(query):
        if sym.upper() in tried:
            continue
        tried.add(sym.upper())
        try:
            d = capm(sym, rf_override, g_override)
            d["resolved_from"] = query
            return d
        except ValueError:
            continue
    raise ValueError(f"No encontré ninguna acción para '{query}' en un mercado soportado "
                     f"(USD, EUR, GBP). Prueba con el ticker exacto (p.ej. REP.MC).")


def report(d):
    L = ["", "=" * 62, f"  CAPM — {d['name']} ({d['ticker']})  [{d['ccy']}]", "=" * 62,
         "", "  Fórmula:", "      E[R] = Rf + beta * (E[Rm] - Rf)", "",
         "  Valores (fuente: Yahoo Finance):",
         f"      Rf   (soberano 10Y {d['ccy']}) ......... {d['rf']:7.2%}",
         f"      beta ({d['ticker']} vs {d['index']}, {d['months']}m) ...... {d['beta']:7.3f}",
         f"      E[Rm] (Gordon, ETF {d['etf']}, g={d['g']:.1%}) . {d['rm']:7.2%}",
         f"      MRP  (E[Rm] - Rf) .................... {d['mrp']:7.2%}",
         "", "  Cálculo:",
         f"      E[R] = {d['rf']:.2%} + {d['beta']:.3f} * ({d['rm']:.2%} - {d['rf']:.2%})",
         f"      E[R] = {d['rf']:.2%} + {d['beta']:.3f} * {d['mrp']:.2%}",
         "", "  " + "-" * 42,
         f"  >>> Retorno esperado (CAPM):  {d['er']:.2%}",
         "  " + "-" * 42, ""]
    return "\n".join(L)


def main():
    p = argparse.ArgumentParser(description="CAPM desde Yahoo Finance")
    p.add_argument("ticker", nargs="?", help="p.ej. KO, ITX.MC, SHEL.L")
    p.add_argument("--rf", type=float, help="risk-free en tanto por uno (override, p.ej. 0.045)")
    p.add_argument("--g", type=float, help="crecimiento nominal para E[Rm] (override, p.ej. 0.03)")
    a = p.parse_args()
    query = a.ticker or input("Empresa o ticker (p.ej. Repsol, KO): ")
    print(report(analyze(query, a.rf, a.g)))


if __name__ == "__main__":
    main()
