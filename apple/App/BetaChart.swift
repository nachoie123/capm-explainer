import Charts
import CAPMKit
import SwiftUI

/// La beta se ve: cada punto es un mes (mercado en horizontal, acción en vertical) y la recta OLS tiene pendiente β.
struct BetaChart: View {
    let series: [MonthlyReturn]
    let beta: Double
    let ticker: String
    @State private var selX: Double?

    var alpha: Double {
        let n = Double(series.count)
        return series.map(\.stock).reduce(0, +) / n - beta * series.map(\.market).reduce(0, +) / n
    }
    var selected: MonthlyReturn? {
        guard let selX else { return nil }
        return series.min { abs($0.market - selX) < abs($1.market - selX) }
    }
    static let monthIn: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f }()
    func monthLabel(_ m: String) -> String {
        Self.monthIn.date(from: m)?.formatted(.dateTime.month(.abbreviated).year()) ?? m
    }

    var body: some View {
        let xs = series.map(\.market), lo = xs.min() ?? -0.1, hi = xs.max() ?? 0.1
        Chart {
            ForEach(series) { p in
                PointMark(x: .value("Market", p.market), y: .value("Stock", p.stock))
                    .foregroundStyle(Theme.champagne.opacity(selected == nil || selected == p ? 0.8 : 0.3))
                    .symbolSize(30)
            }
            ForEach([lo, hi], id: \.self) { x in
                LineMark(x: .value("Market", x), y: .value("Stock", alpha + beta * x))
                    .foregroundStyle(Theme.gold).lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let p = selected {
                PointMark(x: .value("Market", p.market), y: .value("Stock", p.stock))
                    .foregroundStyle(Theme.gold).symbolSize(110)
                    .annotation(position: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: monthLabel(p.month)).font(.caption.weight(.semibold)).foregroundStyle(Theme.champagne)
                            Text("Market \(pct(p.market, 1)) · \(ticker) \(pct(p.stock, 1))").font(.caption2).monospacedDigit().foregroundStyle(Theme.text2)
                        }
                        .padding(8).background(Theme.bg.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLit))
                    }
            }
        }
        .chartXSelection(value: $selX)
        .chartXAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.border); AxisValueLabel(format: FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0))).foregroundStyle(Theme.dim) } }
        .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.border); AxisValueLabel(format: FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0))).foregroundStyle(Theme.dim) } }
        .chartXAxisLabel { Text("Market, monthly return").font(.caption).foregroundStyle(Theme.dim) }
        .chartYAxisLabel(position: .leading) { Text("\(ticker), monthly return").font(.caption).foregroundStyle(Theme.dim) }
        .frame(height: 260)
        .padding(.top, 4)
    }
}
