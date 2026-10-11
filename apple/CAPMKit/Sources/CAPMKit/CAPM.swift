// CAPMKit: la matemática de capm.py portada a Swift, línea a línea.
//   E[R] = Rf + β (E[Rm] − Rf)      β = Cov(Ri, Rm) / Var(Rm)      E[Rm] = D/P (1+g) + g
import Foundation

public struct MonthlyReturn: Codable, Equatable, Sendable, Identifiable {
    public let month: String   // "2024-03"
    public let stock: Double
    public let market: Double
    public var id: String { month }
    public init(month: String, stock: Double, market: Double) { self.month = month; self.stock = stock; self.market = market }
}

public struct Bar: Sendable { public let date: Date; public let adjClose: Double
    public init(date: Date, adjClose: Double) { self.date = date; self.adjClose = adjClose } }

public struct Bars: Sendable {
    public let currency: String?, name: String, timeZone: TimeZone, bars: [Bar]
    public init(currency: String?, name: String, timeZone: TimeZone, bars: [Bar]) {
        self.currency = currency; self.name = name; self.timeZone = timeZone; self.bars = bars }
}

public struct Dividend: Sendable { public let date: Date, amount: Double
    public init(date: Date, amount: Double) { self.date = date; self.amount = amount } }

public struct Region: Sendable { public let index, etf: String; public let rf: Double?; public let g: Double }

public enum CAPMError: Error, Equatable, LocalizedError {
    case empty, notFound(String), unsupportedCurrency(String), shortHistory(Int), noDividendYield(String), noTreasury, nothingFound(String), rateLimited
    public var errorDescription: String? {
        switch self {
        case .empty: return String(localized: "Type a company name or ticker.", bundle: .module)
        case .notFound(let t): return String(localized: "'\(t)' not found on Yahoo. Is it spelled right?", bundle: .module)
        case .unsupportedCurrency(let c): return String(localized: "Markets in \(c) are not supported yet (USD, EUR, GBP only).", bundle: .module)
        case .shortHistory(let n): return String(localized: "Not enough history (\(n) months) to estimate beta.", bundle: .module)
        case .noDividendYield(let e): return String(localized: "No dividend yield for \(e).", bundle: .module)
        case .noTreasury: return String(localized: "Could not read the US 10-year Treasury (^TNX) right now. Try again.", bundle: .module)
        case .nothingFound(let q): return String(localized: "No stock found for '\(q)' in a supported market (USD, EUR, GBP). Try the exact ticker (e.g. REP.MC).", bundle: .module)
        case .rateLimited: return String(localized: "Yahoo is rate-limiting requests (429). Wait a minute and try again.", bundle: .module)
        }
    }
}

public struct CAPMResult: Codable, Sendable {
    public var name, ticker, ccy, index, etf: String
    public var months: Int
    public var rf, beta, dy, g, rm, mrp, er, r2: Double
    public var warn: String?
    public var resolvedFrom: String?
    public var series: [MonthlyReturn]
}

public enum CAPM {
    /// Perillas por moneda, copiadas de capm.py. rf nil = bono USA a 10 años en vivo.
    public static let regions: [String: Region] = [
        "USD": Region(index: "^GSPC", etf: "SPY", rf: nil, g: 0.040),
        "EUR": Region(index: "^STOXX50E", etf: "EXW1.DE", rf: 0.025, g: 0.030),
        "GBP": Region(index: "^FTSE", etf: "ISF.L", rf: 0.045, g: 0.033),
        "GBp": Region(index: "^FTSE", etf: "ISF.L", rf: 0.045, g: 0.033),  // Londres cotiza en peniques
    ]

    public static func expectedReturn(rf: Double, beta: Double, marketReturn: Double) -> Double { rf + beta * (marketReturn - rf) }
    public static func gordon(dividendYield: Double, g: Double) -> Double { dividendYield * (1 + g) + g }

    /// Pendiente OLS y correlación de los retornos mensuales acción-mercado (np.cov: mismo ddof arriba y abajo).
    public static func regression(_ s: [MonthlyReturn]) -> (beta: Double, corr: Double) {
        let n = Double(s.count)
        let mx = s.map(\.market).reduce(0, +) / n, my = s.map(\.stock).reduce(0, +) / n
        var cov = 0.0, vx = 0.0, vy = 0.0
        for p in s { cov += (p.market - mx) * (p.stock - my); vx += (p.market - mx) * (p.market - mx); vy += (p.stock - my) * (p.stock - my) }
        return (cov / vx, cov / (vx * vy).squareRoot())
    }

    static func monthKey(_ d: Date, _ tz: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let c = cal.dateComponents([.year, .month], from: d)
        return String(format: "%04d-%02d", c.year!, c.month!)
    }

    /// Retorno mensual = cierre ajustado / cierre ajustado anterior − 1. Una barra por mes (la primera):
    /// Yahoo repite el mes en curso con una barra "en vivo" y yfinance la descarta.
    public static func monthlyReturns(_ h: Bars) -> [(month: String, r: Double)] {
        var seen = Set<String>(), bars: [(String, Double)] = []
        for b in h.bars { let k = monthKey(b.date, h.timeZone); if seen.insert(k).inserted { bars.append((k, b.adjClose)) } }
        return zip(bars.dropFirst(), bars).map { (month: $0.0, r: $0.1 / $1.1 - 1) }
    }

    /// Inner join por año-mes, como `s.align(m, join="inner")` en pandas.
    public static func align(_ stock: [(month: String, r: Double)], _ market: [(month: String, r: Double)]) -> [MonthlyReturn] {
        let m = Dictionary(market.map { ($0.month, $0.r) }, uniquingKeysWith: { a, _ in a })
        return stock.compactMap { s in m[s.month].map { MonthlyReturn(month: s.month, stock: s.r, market: $0) } }
    }

    /// Dividendos de los últimos 12 meses / precio: proxy forward del dividend yield (yfinance usa el "yield" de Yahoo).
    public static func trailingYield(dividends: [Dividend], price: Double, now: Date = Date()) -> Double {
        let from = now.addingTimeInterval(-365 * 86_400)
        return dividends.filter { $0.date > from }.map(\.amount).reduce(0, +) / price
    }

    public static func warnings(months: Int, corr: Double, name: String, index: String) -> String? {
        var w: [String] = []
        if months < 24 { w.append(String(localized: "Short history (\(months) months, recent IPO): beta is unreliable.", bundle: .module)) }
        if abs(corr) < 0.15 {
            let r2 = (corr * corr).formatted(.percent.precision(.fractionLength(0)))
            w.append(String(localized: "Unreliable beta: \(name) barely correlates with the market (\(index), R²=\(r2)). Yahoo's data for this stock is noisy. Treat it as indicative, not as a real beta.", bundle: .module))
        }
        return w.isEmpty ? nil : w.joined(separator: " ")
    }
}

public protocol MarketData: Sendable {
    func history(_ symbol: String, years: Int) async throws -> Bars   // barras mensuales; .notFound si Yahoo no lo conoce
    func dividendYield(_ etf: String) async throws -> Double
    func us10y() async throws -> Double
    func search(_ query: String) async throws -> [String]
}

public struct Analyzer: Sendable {
    let data: MarketData
    public init(data: MarketData) { self.data = data }

    /// capm.capm(): un ticker exacto → resultado.
    public func capm(_ ticker: String, rf rfOverride: Double? = nil, g gOverride: Double? = nil) async throws -> CAPMResult {
        let s = try await data.history(ticker, years: 5)
        guard let ccy = s.currency else { throw CAPMError.notFound(ticker) }
        guard let reg = CAPM.regions[ccy] else { throw CAPMError.unsupportedCurrency(ccy) }
        let rf: Double
        if let o = rfOverride { rf = o } else if let fixed = reg.rf { rf = fixed } else { rf = try await data.us10y() }
        let g = gOverride ?? reg.g
        let m = try await data.history(reg.index, years: 5)
        let series = CAPM.align(CAPM.monthlyReturns(s), CAPM.monthlyReturns(m))
        guard series.count >= 12 else { throw CAPMError.shortHistory(series.count) }
        let (beta, corr) = CAPM.regression(series)
        let dy = try await data.dividendYield(reg.etf)
        guard dy > 0 else { throw CAPMError.noDividendYield(reg.etf) }
        let rm = CAPM.gordon(dividendYield: dy, g: g)
        return CAPMResult(name: s.name, ticker: ticker, ccy: ccy, index: reg.index, etf: reg.etf, months: series.count,
                          rf: rf, beta: beta, dy: dy, g: g, rm: rm, mrp: rm - rf, er: CAPM.expectedReturn(rf: rf, beta: beta, marketReturn: rm),
                          r2: corr * corr, warn: CAPM.warnings(months: series.count, corr: corr, name: s.name, index: reg.index),
                          resolvedFrom: nil, series: series)
    }

    /// capm.analyze(): nombre o ticker → prueba tal cual y, si falla, los candidatos del buscador de Yahoo.
    public func analyze(_ query: String, rf: Double? = nil, g: Double? = nil) async throws -> CAPMResult {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw CAPMError.empty }
        do { return try await capm(q, rf: rf, g: g) } catch is CAPMError {}
        var tried: Set<String> = [q.uppercased()]
        for sym in (try? await data.search(q)) ?? [] where tried.insert(sym.uppercased()).inserted {
            do { var r = try await capm(sym, rf: rf, g: g); r.resolvedFrom = q; return r } catch is CAPMError { continue }
        }
        throw CAPMError.nothingFound(q)
    }
}
