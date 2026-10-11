import CAPMKit
import SwiftUI

enum Step: Hashable { case company, formula, rf, beta, warn, chain, gordon, gordonNum, subst, result }

@MainActor @Observable final class Model {
    var query = ""
    var rfText = ""
    var gText = ""
    var result: CAPMResult?
    var error: String?
    var busy = false
    var shown: [Step] = []
    var instant = false   // reducir movimiento: todo de golpe

    static func number(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }

    /// Mismo ritmo que CAPM.html: cada paso espera su tiempo y entonces aparece.
    func steps(for d: CAPMResult) -> [(Step, Int)] {
        var s: [(Step, Int)] = [(.company, 0), (.formula, 1100), (.rf, 1600), (.beta, 1300)]
        if d.warn != nil { s.append((.warn, 1500)) }
        s += [(.chain, 1300), (.gordon, 1200), (.gordonNum, 1600), (.subst, 1600), (.result, 1700)]
        return s
    }

    func go() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !busy else { return }
        busy = true; error = nil; result = nil; shown = []
        defer { busy = false }
        do {
            let r = try await Analyzer(data: YahooClient()).analyze(q, rf: Self.number(rfText).map { $0 / 100 }, g: Self.number(gText).map { $0 / 100 })
            result = r
            for (step, ms) in steps(for: r) {
                if !instant { try? await Task.sleep(for: .milliseconds(ms)) }
                withAnimation(.spring(duration: 0.6, bounce: 0.15)) { shown.append(step) }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ContentView: View {
    @State private var m = Model()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    searchBar
                    Text("Rf and g are optional. USD uses the live US 10-year Treasury; EUR/GBP use a default you can override here.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.dim).padding(.top, 10)
                    if let d = m.result { chips(d).padding(.top, 26) }
                    VStack(spacing: 16) {
                        if let d = m.result { ForEach(m.shown, id: \.self) { step in card(step, d).id(step).transition(.move(edge: .bottom).combined(with: .opacity)) } }
                        if let e = m.error { errorCard(e) }
                    }
                    .padding(.top, 24)
                    footer
                }
                .frame(maxWidth: 840).frame(maxWidth: .infinity)
                .padding(.horizontal, 20).padding(.top, 36).padding(.bottom, 80)
            }
            .onChange(of: m.shown) { _, s in if let last = s.last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } } }
        }
        .background(background.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            m.instant = reduceMotion; focused = true
            if let a = CommandLine.arguments.first(where: { $0.hasPrefix("capm://") }), let u = URL(string: a) { open(u) }  // simctl launch … capm://KO
        }
        .onOpenURL(perform: open)
        .tint(Theme.gold)
    }

    /// capm://Repsol o capm://?q=KO&rf=4.5&g=3
    func open(_ url: URL) {
        let c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let q = { (k: String) in c?.queryItems?.first { $0.name == k }?.value }
        m.query = q("q") ?? url.host ?? ""; m.rfText = q("rf") ?? ""; m.gText = q("g") ?? ""
        go()
    }

    func go() { focused = false; Task { await m.go() } }

    var background: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [Theme.gold.opacity(0.14), .clear], center: .init(x: 0.12, y: -0.08), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Theme.bronze.opacity(0.10), .clear], center: .init(x: 0.96, y: -0.04), startRadius: 0, endRadius: 460)
        }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text(verbatim: "CAPM ") + Text(verbatim: "Explainer").foregroundStyle(Theme.gold))
                .font(.system(size: 40, weight: .semibold, design: .serif)).foregroundStyle(Theme.fg)
            Text("Type a company's name or ticker and I'll show you, step by step, how its expected return is calculated.")
                .font(.system(size: 15)).foregroundStyle(Theme.dim).frame(maxWidth: 520, alignment: .leading)
        }
        .padding(.bottom, 26)
    }

    func field(_ placeholder: LocalizedStringKey, _ text: Binding<String>, bold: Bool = false) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain).font(.system(size: 16, weight: bold ? .semibold : .regular)).foregroundStyle(Theme.fg)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
            .onSubmit(go)
    }

    var searchBar: some View {
        let ticker = field("Repsol, Apple, KO, Santander…", $m.query, bold: true).focused($focused)
            #if os(iOS)
            .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.go)
            #endif
        let rf = field("Rf %", $m.rfText).frame(width: 84)
        let g = field("g %", $m.gText).frame(width: 84)
        let button = Button(action: go) {
            Text(m.busy ? "Searching…" : "Calculate")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(red: 26 / 255, green: 21 / 255, blue: 9 / 255))
                .padding(.horizontal, 24).frame(minHeight: 44)
                .background(LinearGradient(colors: [Theme.champagne, Theme.gold], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: Theme.gold.opacity(0.35), radius: 12, y: 8)
        }
        .buttonStyle(.plain).disabled(m.busy).opacity(m.busy ? 0.6 : 1).keyboardShortcut(.defaultAction)
        return Group {
            if sizeClass == .compact {
                VStack(spacing: 10) { ticker; HStack(spacing: 10) { rf; g; Spacer(); button } }
            } else {
                HStack(spacing: 10) { ticker; rf; g; button }
            }
        }
        #if os(iOS)
        .keyboardType(.default)
        #endif
        .padding(12)
        .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
    }

    func chips(_ d: CAPMResult) -> some View {
        let s = m.shown
        let items: [(String, String, Bool)] = [
            ("Rf", pct(d.rf), s.contains(.rf)), ("β", num(d.beta), s.contains(.beta)),
            ("D/P", pct(d.dy), s.contains(.gordon)), ("g", pct(d.g), s.contains(.gordon)),
            ("E[Rm]", pct(d.rm), s.contains(.gordonNum)), ("MRP", pct(d.mrp), s.contains(.subst)), ("E[R]", pct(d.er), s.contains(.result)),
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10, alignment: .leading)], alignment: .leading, spacing: 10) {
            ForEach(items, id: \.0) { Chip(label: $0.0, value: $0.1, on: $0.2) }
        }
    }

    @ViewBuilder func card(_ step: Step, _ d: CAPMResult) -> some View {
        let b = num(d.beta)
        switch step {
        case .company:
            Card(kicker: "Company") {
                (Text(verbatim: d.name + " · ") + Text(verbatim: d.ticker).foregroundStyle(Theme.gold) + Text(verbatim: " (\(d.ccy))").foregroundStyle(Theme.dim).fontWeight(.medium))
                    .font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(Theme.fg)
                if let from = d.resolvedFrom { Text("You searched “\(from)” → \(d.ticker)").font(.system(size: 13)).foregroundStyle(Theme.gold) }
                Text("Reference market: \(d.index) · Dividend ETF: \(d.etf)").font(.system(size: 14)).foregroundStyle(Theme.dim)
            }
        case .formula:
            Card(kicker: "Step 1 · The formula", title: "Expected return · the CAPM model") {
                Formula(s: "E[R{i}] = R{f} + β{i} (E[R{m}] − R{f})")
                VStack(alignment: .leading, spacing: 9) {
                    LegendRow(sym: "E[Rᵢ]", desc: "Expected return of the asset", note: "· what we want to find")
                    LegendRow(sym: "Rf", desc: "Risk-free rate", note: "· sovereign bond")
                    LegendRow(sym: "βᵢ", desc: "Beta", note: "· how much the stock moves relative to the market")
                    LegendRow(sym: "E[Rₘ]", desc: "Expected market return")
                    LegendRow(sym: "(E[Rₘ]−Rf)", desc: "Market risk premium", note: "(MRP)")
                }.padding(.top, 4)
            }
        case .rf:
            Card(kicker: "Step 2 · Components", title: "Risk-free rate · Rf") {
                LegendRow(sym: "Rf", desc: "10-year sovereign bond (\(d.ccy))", val: pct(d.rf))
            }
        case .beta:
            Card(kicker: "Step 2 · Components", title: "Beta · βᵢ") {
                Formula(s: "β{i} = Cov(R{i}, R{m}) / Var(R{m})")
                LegendRow(sym: "βᵢ", desc: "Regression of monthly returns vs \(d.index)", note: "· \(d.months) months · R² = \(pct(d.r2, 0))", val: b)
                BetaChart(series: d.series, beta: d.beta, ticker: d.ticker)
                Text("Each dot is one month: how the market moved (across) and how \(d.ticker) moved (up). The slope of the gold line is β.")
                    .font(.system(size: 13)).foregroundStyle(Theme.dim)
            }
        case .warn:
            Card { Callout(kind: .warn, icon: "exclamationmark.triangle", text: Text(verbatim: d.warn ?? "")) }
        case .chain:
            Card { Callout(icon: "link", text: Text("**E[Rₘ]** is not a direct input: it needs its own formula. We chain into the Gordon model…")) }
        case .gordon:
            Card(kicker: "Sub-calculation · E[Rₘ]", title: "Expected market return · the Gordon model", sub: true) {
                Formula(s: "E[R{m}] = D/P · (1 + g) + g")
                VStack(alignment: .leading, spacing: 9) {
                    LegendRow(sym: "D/P", desc: "Market dividend yield", note: "(ETF \(d.etf))", val: pct(d.dy))
                    LegendRow(sym: "g", desc: "Expected nominal growth", note: "(adjustable)", val: pct(d.g))
                }.padding(.top, 4)
            }
        case .gordonNum:
            Card(sub: true) {
                Formula(s: "E[R{m}] = \(num(d.dy, 4)) · (1 + \(num(d.g, 3))) + \(num(d.g, 3)) = \(pct(d.rm))", lit: true)
                Callout(kind: .back, icon: "arrow.turn.up.left", text: Text("We carry **E[Rₘ] = \(pct(d.rm))** back into the main formula."))
            }
        case .subst:
            Card(kicker: "Step 3 · Substitution", title: "We plug each value into the formula") {
                Formula(s: "E[R] = \(pct(d.rf)) + \(b) · (\(pct(d.rm)) − \(pct(d.rf)))", lit: true)
                Formula(s: "E[R] = \(pct(d.rf)) + \(b) × \(pct(d.mrp)) = \(pct(d.er))", lit: true)
            }
        case .result:
            Card(lit: true) {
                VStack(spacing: 12) {
                    Text("Expected return (CAPM) · \(d.ticker)").font(.caption.weight(.semibold)).tracking(1.4).textCase(.uppercase).foregroundStyle(Theme.bronze)
                    Text(verbatim: pct(d.er))
                        .font(.system(size: 72, weight: .bold, design: .serif)).monospacedDigit()
                        .foregroundStyle(LinearGradient(colors: [Color(red: 251 / 255, green: 244 / 255, blue: 230 / 255), Theme.gold], startPoint: .top, endPoint: .bottom))
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                    (Text("According to CAPM, an investor should demand around **\(pct(d.er))** a year for holding \(d.name), given its risk (β=\(b)) against the market.")
                        + Text(verbatim: d.er < d.rf ? " " : "")
                        + Text(d.er < d.rf ? "Note: it comes out below the risk-free asset: very low beta and a tight market premium." : ""))
                        .font(.system(size: 14.5)).foregroundStyle(Theme.text2).multilineTextAlignment(.center).frame(maxWidth: 520)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .background(RadialGradient(colors: [Theme.gold.opacity(0.2), .clear], center: .top, startRadius: 0, endRadius: 420).clipShape(RoundedRectangle(cornerRadius: 18)))
        }
    }

    func errorCard(_ e: String) -> some View {
        Text("Could not calculate **\(m.query)**: \(e)")
            .font(.system(size: 15)).foregroundStyle(Color(red: 232 / 255, green: 180 / 255, blue: 160 / 255))
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Color(red: 150 / 255, green: 60 / 255, blue: 40 / 255).opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 150 / 255, green: 60 / 255, blue: 40 / 255).opacity(0.45)))
    }

    var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Data: Yahoo Finance · Educational tool, not financial advice.")
            Text(verbatim: "Ignacio San Benito · IE University")
        }
        .font(.system(size: 12)).foregroundStyle(Theme.dim).padding(.top, 40)
    }
}
