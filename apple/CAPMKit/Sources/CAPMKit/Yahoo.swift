// Las mismas fuentes gratis que usa yfinance, sin librería ni clave: chart v8 (precios, dividendos, bono) y search v1.
import Foundation

public struct YahooClient: MarketData {
    let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    struct Chart: Decodable { let chart: Body
        struct Body: Decodable { let result: [Result]?; let error: Err? }
        struct Err: Decodable { let code: String? }
        struct Result: Decodable { let meta: Meta; let timestamp: [Int]?; let indicators: Indicators; let events: Events? }
        struct Meta: Decodable { let currency, shortName, longName, exchangeTimezoneName: String?; let regularMarketPrice: Double? }
        struct Indicators: Decodable { let quote: [Quote]; let adjclose: [Adj]? }
        struct Quote: Decodable { let close: [Double?]? }
        struct Adj: Decodable { let adjclose: [Double?]? }
        struct Events: Decodable { let dividends: [String: Div]? }
        struct Div: Decodable { let amount: Double; let date: Int }
    }
    struct Search: Decodable { let quotes: [Quote]; struct Quote: Decodable { let symbol: String?; let quoteType: String? } }

    func get<T: Decodable>(_ path: String, _ query: [String: String], as: T.Type) async throws -> T {
        var c = URLComponents(string: "https://query2.finance.yahoo.com" + path)!
        c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: c.url!)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 429 { throw CAPMError.rateLimited }
        return try JSONDecoder().decode(T.self, from: data)  // un 404 de Yahoo trae JSON con result: null
    }

    func chart(_ symbol: String, _ query: [String: String]) async throws -> Chart.Result {
        let sym = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let r = try await get("/v8/finance/chart/\(sym)", query, as: Chart.self).chart.result?.first else { throw CAPMError.notFound(symbol) }
        return r
    }

    public func history(_ symbol: String, years: Int) async throws -> Bars {
        let r = try await chart(symbol, ["range": "\(years)y", "interval": "1mo"])
        let closes = r.indicators.adjclose?.first?.adjclose ?? r.indicators.quote.first?.close ?? []
        let bars = zip(r.timestamp ?? [], closes).compactMap { t, c in c.map { Bar(date: Date(timeIntervalSince1970: TimeInterval(t)), adjClose: $0) } }
        return Bars(currency: r.meta.currency, name: r.meta.longName ?? r.meta.shortName ?? symbol,
                    timeZone: r.meta.exchangeTimezoneName.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "America/New_York")!, bars: bars)
    }

    public func dividendYield(_ etf: String) async throws -> Double {
        let r = try await chart(etf, ["range": "1y", "interval": "1d", "events": "div"])
        guard let price = r.meta.regularMarketPrice, price > 0 else { throw CAPMError.noDividendYield(etf) }
        let divs = (r.events?.dividends ?? [:]).values.map { Dividend(date: Date(timeIntervalSince1970: TimeInterval($0.date)), amount: $0.amount) }
        return CAPM.trailingYield(dividends: divs, price: price)
    }

    public func us10y() async throws -> Double {
        guard let p = try await chart("^TNX", ["range": "5d", "interval": "1d"]).meta.regularMarketPrice else { throw CAPMError.noTreasury }
        return p / 100   // ^TNX viene en % (4.70 = 4.70%)
    }

    public func search(_ query: String) async throws -> [String] {
        let s = try await get("/v1/finance/search", ["q": query, "quotesCount": "10", "newsCount": "0"], as: Search.self)
        return s.quotes.filter { $0.quoteType == "EQUITY" }.compactMap(\.symbol).prefix(8).map { $0 }
    }
}
