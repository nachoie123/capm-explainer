import SwiftUI

/// Paleta "Neural Noir" de CAPM.html: negro cálido, oro y bronce, serif para titulares y cifras.
enum Theme {
    static let bg = Color(red: 10 / 255, green: 9 / 255, blue: 8 / 255)
    static let fg = Color(red: 242 / 255, green: 236 / 255, blue: 225 / 255)
    static let dim = Color(red: 143 / 255, green: 135 / 255, blue: 122 / 255)
    static let gold = Color(red: 201 / 255, green: 168 / 255, blue: 106 / 255)
    static let bronze = Color(red: 167 / 255, green: 139 / 255, blue: 113 / 255)
    static let champagne = Color(red: 232 / 255, green: 213 / 255, blue: 183 / 255)
    static let text2 = Color(red: 221 / 255, green: 212 / 255, blue: 198 / 255)
    static let panel = champagne.opacity(0.028)
    static let border = champagne.opacity(0.12)
    static let borderLit = gold.opacity(0.45)
}

func pct(_ x: Double, _ digits: Int = 2) -> String { x.formatted(.percent.precision(.fractionLength(digits))) }
func num(_ x: Double, _ digits: Int = 3) -> String { x.formatted(.number.precision(.fractionLength(digits))) }

/// Tarjeta de paso. `sub` = sub-cálculo encadenado (raíl de bronce con nodo). `lit` = borde dorado.
struct Card<Content: View>: View {
    var kicker: LocalizedStringKey? = nil
    var title: LocalizedStringKey? = nil
    var sub = false
    var lit = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let kicker {
                Text(kicker).font(.caption.weight(.semibold)).tracking(1.4).textCase(.uppercase)
                    .foregroundStyle(sub ? Theme.gold : Theme.bronze)
            }
            if let title {
                Text(title).font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(Theme.fg)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(lit ? Theme.borderLit : Theme.border))
        .overlay(alignment: .topLeading) {
            if sub {
                Rectangle().fill(Theme.bronze).frame(width: 1).frame(maxHeight: .infinity)
                Circle().fill(Theme.gold).frame(width: 9, height: 9)
                    .background(Circle().fill(Theme.gold.opacity(0.14)).frame(width: 17, height: 17))
                    .offset(x: -4, y: 26)
            }
        }
        .padding(.leading, sub ? 28 : 0)
    }
}

/// Fórmula en serif. `{x}` se dibuja como subíndice: "R{f}" → R con f pequeña y baja.
struct Formula: View {
    let s: String
    var lit = false
    var body: some View {
        text.font(.system(size: 21, design: .serif)).foregroundStyle(Theme.champagne)
            .frame(maxWidth: .infinity).padding(16)
            .background((lit ? Theme.gold.opacity(0.05) : Color.black.opacity(0.4)), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(lit ? Theme.borderLit : Theme.border))
    }
    var text: Text {
        var out = Text(verbatim: ""), rest = Substring(s)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out = out + Text(verbatim: String(rest[..<open]))
                + Text(verbatim: String(rest[rest.index(after: open)..<close])).font(.system(size: 13, design: .serif)).baselineOffset(-6)
            rest = rest[rest.index(after: close)...]
        }
        return out + Text(verbatim: String(rest))
    }
}

struct LegendRow: View {
    let sym: String
    let desc: LocalizedStringKey
    var note: LocalizedStringKey? = nil
    var val: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: sym).font(.system(size: 15, weight: .semibold, design: .serif)).foregroundStyle(Theme.gold).frame(minWidth: 72, alignment: .leading)
            (Text(desc) + Text(verbatim: note == nil ? "" : " ") + Text(note ?? "").foregroundStyle(Theme.dim))
                .font(.system(size: 14.5)).foregroundStyle(Theme.text2)
            if let val {
                Spacer(minLength: 8)
                Text(verbatim: val).font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(Theme.champagne)
            }
        }
    }
}

struct Callout: View {
    enum Kind { case plain, back, warn }
    var kind: Kind = .plain
    let icon: String
    let text: Text
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).padding(.top, 2)
            text.font(.system(size: 14))
        }
        .foregroundStyle(kind == .warn ? Color(red: 232 / 255, green: 201 / 255, blue: 160 / 255) : Theme.text2)
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(bgColor, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(borderColor))
    }
    var bgColor: Color {
        switch kind { case .plain: Theme.bronze.opacity(0.10); case .back: Theme.gold.opacity(0.10); case .warn: Color(red: 190 / 255, green: 120 / 255, blue: 60 / 255).opacity(0.12) }
    }
    var borderColor: Color {
        switch kind { case .plain: Theme.bronze.opacity(0.3); case .back: Theme.borderLit; case .warn: Color(red: 190 / 255, green: 120 / 255, blue: 60 / 255).opacity(0.4) }
    }
}

/// Ficha de valor del tablero: se enciende cuando el paso que la calcula aparece.
struct Chip: View {
    let label: String
    let value: String
    let on: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: label).font(.system(size: 11, weight: .medium)).tracking(0.3).foregroundStyle(Theme.bronze)
            Text(verbatim: value).font(.system(size: 17, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.champagne)
        }
        .padding(.horizontal, 14).padding(.vertical, 10).frame(minWidth: 96, alignment: .leading)
        .background(on ? Theme.gold.opacity(0.07) : Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Theme.borderLit : Theme.border))
        .opacity(on ? 1 : 0.38).scaleEffect(on ? 1 : 0.94)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: on)
    }
}
