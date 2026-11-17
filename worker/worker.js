// API de la calculadora web: /api/capm?ticker=&rf=&g= -> mismo JSON que server.py.
// Port de capm.py / CAPMKit (Yahoo chart v8 + search v1, sin yfinance).
const REGION = {
  USD: { index: "^GSPC", etf: "SPY", rf: null, g: 0.04 },
  EUR: { index: "^STOXX50E", etf: "EXW1.DE", rf: 0.025, g: 0.03 },
  GBP: { index: "^FTSE", etf: "ISF.L", rf: 0.045, g: 0.033 },
};
REGION.GBp = REGION.GBP; // Londres cotiza en peniques

class Miss extends Error {} // fallo "de este ticker": se prueba el siguiente candidato

async function yahoo(path, params) {
  const u = new URL("https://query2.finance.yahoo.com" + path);
  for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
  const r = await fetch(u, { headers: { "User-Agent": "Mozilla/5.0" }, cf: { cacheTtl: 900 } });
  if (r.status === 404) return null;
  if (!r.ok) throw new Error(`Yahoo respondió ${r.status}. Prueba de nuevo en un momento.`);
  return r.json();
}

async function chart(sym, params) {
  const j = await yahoo("/v8/finance/chart/" + encodeURIComponent(sym), params);
  const res = j?.chart?.result?.[0];
  if (!res) throw new Miss(`Ticker '${sym}' no encontrado en Yahoo. ¿Está bien escrito?`);
  return res;
}

// +12 h: las barras caen a medianoche local y el offset actual no cuenta el horario de verano.
// Una barra por mes (la primera: Yahoo repite el mes en curso con una barra "en vivo").
function monthly(res) {
  const ts = res.timestamp || [], off = res.meta.gmtoffset || 0;
  const px = res.indicators.adjclose?.[0]?.adjclose || res.indicators.quote[0].close;
  const seen = new Set(), bars = [];
  ts.forEach((t, i) => {
    if (px[i] == null) return;
    const k = new Date((t + off + 43200) * 1000).toISOString().slice(0, 7);
    if (!seen.has(k)) { seen.add(k); bars.push([k, px[i]]); }
  });
  const out = new Map();
  for (let i = 1; i < bars.length; i++) out.set(bars[i][0], bars[i][1] / bars[i - 1][1] - 1);
  return out;
}

function regression(pairs) {
  const n = pairs.length;
  const mx = pairs.reduce((a, p) => a + p[1], 0) / n, my = pairs.reduce((a, p) => a + p[0], 0) / n;
  let cov = 0, vx = 0, vy = 0;
  for (const [s, m] of pairs) { cov += (m - mx) * (s - my); vx += (m - mx) ** 2; vy += (s - my) ** 2; }
  return { beta: cov / vx, corr: cov / Math.sqrt(vx * vy) };
}

async function dividendYield(etf) {
  const r = await chart(etf, { range: "1y", interval: "1d", events: "div" });
  const from = Date.now() / 1000 - 365 * 86400;
  const sum = Object.values(r.events?.dividends || {}).filter(d => d.date > from).reduce((a, d) => a + d.amount, 0);
  const y = sum / r.meta.regularMarketPrice;
  if (!(y > 0)) throw new Error(`Sin dividend yield para ${etf}.`);
  return y;
}

async function us10y() {
  const p = (await chart("^TNX", { range: "5d", interval: "1d" })).meta.regularMarketPrice;
  if (!p) throw new Error("No pude leer el bono USA a 10 años (^TNX) ahora mismo. Prueba de nuevo.");
  return p / 100;
}

async function capm(ticker, rfO, gO) {
  const s = await chart(ticker, { range: "5y", interval: "1mo" });
  const ccy = s.meta.currency, reg = REGION[ccy];
  if (!ccy) throw new Miss(`Ticker '${ticker}' no encontrado en Yahoo.`);
  if (!reg) throw new Miss(`Mercado en ${ccy} aún no soportado (soportados: USD, EUR, GBP).`);
  const name = s.meta.shortName || s.meta.longName || ticker;
  const [rf, m, dy] = await Promise.all([
    rfO ?? reg.rf ?? us10y(),
    chart(reg.index, { range: "5y", interval: "1mo" }),
    dividendYield(reg.etf),
  ]);
  const g = gO ?? reg.g, sm = monthly(s), mm = monthly(m);
  const pairs = [...sm].filter(([k]) => mm.has(k)).map(([k, r]) => [r, mm.get(k)]);
  if (pairs.length < 12) throw new Miss(`Histórico insuficiente (${pairs.length} meses) para estimar beta.`);
  const { beta, corr } = regression(pairs);
  const rm = dy * (1 + g) + g, mrp = rm - rf, n = pairs.length, r2 = corr * corr;
  const d = { name, ticker, ccy, index: reg.index, etf: reg.etf, months: n, rf, beta, dy, g, rm, mrp, er: rf + beta * mrp, r2 };
  const w = [];
  if (n < 24) w.push(`Histórico corto (${n} meses, IPO reciente): la beta es poco fiable.`);
  if (Math.abs(corr) < 0.15) w.push(`Beta poco fiable: ${name} apenas correlaciona con el mercado (${reg.index}, R²=${Math.round(r2 * 100)}%) — los datos de Yahoo para este valor son ruidosos. Tómalo como orientativo, no como una beta real.`);
  if (w.length) d.warn = w.join(" ");
  return d;
}

async function analyze(q, rf, g) {
  q = (q || "").trim();
  if (!q) throw new Error("Escribe el nombre o el ticker de una empresa.");
  try { return await capm(q, rf, g); } catch (e) { if (!(e instanceof Miss)) throw e; }
  const j = await yahoo("/v1/finance/search", { q, quotesCount: "10", newsCount: "0" }).catch(() => null);
  const syms = (j?.quotes || []).filter(x => x.quoteType === "EQUITY" && x.symbol).map(x => x.symbol).slice(0, 8);
  const tried = new Set([q.toUpperCase()]);
  for (const sym of syms) {
    if (tried.has(sym.toUpperCase())) continue;
    tried.add(sym.toUpperCase());
    try { return { ...(await capm(sym, rf, g)), resolved_from: q }; } catch (e) { if (!(e instanceof Miss)) throw e; }
  }
  throw new Error(`No encontré ninguna acción para '${q}' en un mercado soportado (USD, EUR, GBP). Prueba con el ticker exacto (p.ej. REP.MC).`);
}

const num = v => (v == null || v === "" || isNaN(+v) ? undefined : +v);

export default {
  async fetch(req) {
    const u = new URL(req.url);
    const h = { "Content-Type": "application/json; charset=utf-8", "Access-Control-Allow-Origin": "*" };
    if (u.pathname !== "/api/capm") return new Response('{"error":"not found"}', { status: 404, headers: h });
    try {
      const p = u.searchParams;
      const d = await analyze(p.get("ticker"), num(p.get("rf")), num(p.get("g")));
      return new Response(JSON.stringify(d), { headers: h });
    } catch (e) {
      return new Response(JSON.stringify({ error: e.message }), { status: 400, headers: h });
    }
  },
};
