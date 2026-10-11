// Los números de referencia salen del Python (capm.py) el 12/10/2026: Tests/fixtures.py los regenera.
import Foundation
import Testing
@testable import CAPMKit

struct Fixture: Decodable {
    let ticker, ccy, index, etf: String
    let months: Int
    let rf, beta, dy, g, rm, mrp, er, r2, corr: Double
    let warn: String?
    let series: [MonthlyReturn]
}

let fixtures: [String: Fixture] = {
    let url = Bundle.module.url(forResource: "python", withExtension: "json", subdirectory: "Fixtures")!
    return try! JSONDecoder().decode([String: Fixture].self, from: Data(contentsOf: url))
}()
let tickers = ["KO", "ITX.MC", "SHEL.L"]

// MARK: matemática pura, mismos inputs que el Python

@Test(arguments: tickers) func betaMatchesPython(t: String) {
    let f = fixtures[t]!
    let r = CAPM.regression(f.series)
    #expect(abs(r.beta - f.beta) < 1e-9)
    #expect(abs(r.corr - f.corr) < 1e-9)
}

@Test(arguments: tickers) func gordonMatchesPython(t: String) {
    let f = fixtures[t]!
    #expect(abs(CAPM.gordon(dividendYield: f.dy, g: f.g) - f.rm) < 1e-12)
}

@Test(arguments: tickers) func expectedReturnMatchesPython(t: String) {
    let f = fixtures[t]!
    #expect(abs(CAPM.expectedReturn(rf: f.rf, beta: f.beta, marketReturn: f.rm) - f.er) < 1e-12)
}

@Test func trailingYieldOnlyCountsLast12Months() {
    let now = Date(timeIntervalSince1970: 1_760_000_000)
    let day = 86_400.0
    let divs = [Dividend(date: now.addingTimeInterval(-30 * day), amount: 1),
                Dividend(date: now.addingTimeInterval(-300 * day), amount: 2),
                Dividend(date: now.addingTimeInterval(-400 * day), amount: 100)]
    #expect(CAPM.trailingYield(dividends: divs, price: 50, now: now) == 3.0 / 50)
}

// MARK: pipeline entero con datos falsos: alinear meses, quitar la barra repetida, región, avisos

/// Fabrica barras de precio a partir de los retornos del fixture (precio0 = 100), añade una barra
/// "en vivo" repetida al final y un mes extra solo en el índice (el Python los descarta los dos).
struct FakeData: MarketData {
    let f: Fixture
    var searchHits: [String] = []
    let tz = TimeZone(identifier: "America/New_York")!
    func bars(returns: [Double], firstMonth: String, extra: Bool) -> Bars {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM"; fmt.timeZone = tz
        var d = cal.date(byAdding: .month, value: -1, to: fmt.date(from: firstMonth)!)!
        var p = 100.0
        var out = [Bar(date: d, adjClose: p)]
        for r in returns { p *= 1 + r; d = cal.date(byAdding: .month, value: 1, to: d)!; out.append(Bar(date: d, adjClose: p)) }
        out.append(Bar(date: d.addingTimeInterval(9 * 86_400), adjClose: p))  // barra en vivo del mes en curso
        if extra { out.append(Bar(date: cal.date(byAdding: .month, value: 1, to: d)!, adjClose: p)) }
        return Bars(currency: f.ccy, name: f.ticker, timeZone: tz, bars: out)
    }
    func history(_ symbol: String, years: Int) async throws -> Bars {
        let first = f.series[0].month
        if symbol == f.ticker { return bars(returns: f.series.map(\.stock), firstMonth: first, extra: false) }
        if symbol == f.index { return bars(returns: f.series.map(\.market), firstMonth: first, extra: true) }
        throw CAPMError.notFound(symbol)
    }
    func dividendYield(_ etf: String) async throws -> Double { etf == f.etf ? f.dy : 0 }
    func us10y() async throws -> Double { f.ccy == "USD" ? f.rf : 0 }
    func search(_ query: String) async throws -> [String] { searchHits }
}

@Test(arguments: tickers) func pipelineMatchesPython(t: String) async throws {
    let f = fixtures[t]!
    let r = try await Analyzer(data: FakeData(f: f)).analyze(t)
    #expect(r.months == f.months)
    #expect(r.ccy == f.ccy && r.index == f.index && r.etf == f.etf)
    #expect(abs(r.beta - f.beta) < 1e-9)
    #expect(abs(r.rf - f.rf) < 1e-12 && abs(r.rm - f.rm) < 1e-12)
    #expect(abs(r.er - f.er) < 1e-9)
    #expect(abs(r.r2 - f.r2) < 1e-9)
    #expect((r.warn == nil) == (f.warn == nil))
    #expect(r.series.count == f.months)
}

@Test func overridesReplaceRfAndG() async throws {
    let f = fixtures["KO"]!
    let r = try await Analyzer(data: FakeData(f: f)).analyze("KO", rf: 0.045, g: 0.03)
    #expect(r.rf == 0.045 && r.g == 0.03)
    #expect(abs(r.er - (0.045 + f.beta * (f.dy * 1.03 + 0.03 - 0.045))) < 1e-12)
}

@Test func nameResolvesThroughSearch() async throws {
    let f = fixtures["KO"]!
    let r = try await Analyzer(data: FakeData(f: f, searchHits: ["ZZZ", "KO"])).analyze("Coca Cola")
    #expect(r.ticker == "KO" && r.resolvedFrom == "Coca Cola")
}

@Test func nothingFoundIsAnError() async {
    let f = fixtures["KO"]!
    await #expect(throws: CAPMError.nothingFound("Nada")) {
        try await Analyzer(data: FakeData(f: f)).analyze("Nada")
    }
}

@Test func emptyQueryIsAnError() async {
    await #expect(throws: CAPMError.empty) { try await Analyzer(data: FakeData(f: fixtures["KO"]!)).analyze("  ") }
}

@Test func unsupportedCurrencyIsAnError() async {
    struct Yen: MarketData {
        func history(_ s: String, years: Int) async throws -> Bars { Bars(currency: "JPY", name: s, timeZone: .current, bars: []) }
        func dividendYield(_ etf: String) async throws -> Double { 0 }
        func us10y() async throws -> Double { 0 }
        func search(_ q: String) async throws -> [String] { [] }
    }
    await #expect(throws: CAPMError.nothingFound("7203.T")) { try await Analyzer(data: Yen()).analyze("7203.T") }
}

@Test func shortHistoryWarnsBelow24AndFailsBelow12() {
    let f = fixtures["KO"]!
    #expect(CAPM.warnings(months: 20, corr: 0.9, name: "X", index: "^GSPC") != nil)
    #expect(CAPM.warnings(months: 30, corr: 0.9, name: "X", index: "^GSPC") == nil)
    #expect(CAPM.warnings(months: 30, corr: 0.1, name: "X", index: "^GSPC") != nil)
    _ = f
}

// MARK: Yahoo de verdad (se salta sin red). Tolerancias anchas: el fixture es de un día concreto.

@Test func liveYahooAgreesWithPython() async throws {
    let f = fixtures["KO"]!
    let r: CAPMResult
    do { r = try await Analyzer(data: YahooClient()).analyze("KO") }
    catch let e as URLError { throw SkipTest("sin red: \(e.code)") }
    #expect(r.ccy == "USD" && r.months >= 24)
    #expect(abs(r.beta - f.beta) < 0.05)
    #expect(abs(r.dy - f.dy) < 0.005)   // Yahoo calcula su yield a su manera; nosotros sumamos 12 meses de dividendos
    #expect(abs(r.rf - f.rf) < 0.01)
}

struct SkipTest: Error { let why: String; init(_ w: String) { why = w } }
