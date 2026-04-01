import SwiftUI

// MARK: - Session share template & card

enum SessionShareTemplate: String, CaseIterable, Identifiable {
    case simple = "simple"
    case keiji = "keiji"
    case eva = "eva"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simple: return "シンプル"
        case .keiji: return "和風"
        case .eva: return "サイバー"
        }
    }
}

struct SessionShareCardView: View {
    let snapshot: SessionShareSnapshot
    let showShopName: Bool
    let template: SessionShareTemplate

    // 横長カード：黄金比（人が美しいと感じやすい比率）に寄せる
    static let cardWidth: CGFloat = 1600
    static let cardHeight: CGFloat = 989 // 1600 / 1.618 ≒ 989

    private var totalInvestmentPt: Int { snapshot.totalInvestmentPt }
    private var totalRecoveryBalls: Int { snapshot.totalRecoveryBalls }
    private var profitPt: Int { snapshot.profitPt }

    private var realRate: Double? { snapshot.realRatePer1k }
    private var borderDiff: Double? { snapshot.borderDiffPer1k }

    private var winCountDisplay: String {
        "RUSH：\(snapshot.rushWinCount)回　通常：\(snapshot.normalWinCount)回"
    }

    private var avgFirstHitDisplay: String {
        guard let n = snapshot.averageFirstHitOdds, n.isFinite, n > 0 else { return "—" }
        if n >= 100 { return "1／\(Int(n.rounded()))" }
        return "1／\(n.displayFormat("%.1f"))"
    }

    private var profitDisplayWithUnit: String {
        if profitPt < 0 { return "-\(abs(profitPt).formattedPtWithUnit)" }
        if profitPt > 0 { return "+\(abs(profitPt).formattedPtWithUnit)" }
        return "0\(UnitDisplaySettings.currentSuffix())"
    }

    private var normalRotationsDisplay: String {
        "\(snapshot.normalRotations)回"
    }

    private var profitColor: Color {
        if profitPt > 0 {
            // 「金/青」指定：強い+は金寄り、軽い+は青寄り
            return profitPt >= 10_000 ? Color(red: 0.98, green: 0.84, blue: 0.28) : Color(red: 0.30, green: 0.74, blue: 1.00)
        }
        if profitPt < 0 { return Color(red: 1.00, green: 0.30, blue: 0.30) }
        return .white.opacity(0.9)
    }

    private var baseTextColor: Color {
        template == .simple ? Color.black.opacity(0.92) : Color.white.opacity(0.95)
    }

    private var subTextColor: Color {
        template == .simple ? Color.black.opacity(0.62) : Color.white.opacity(0.72)
    }

    private var cardInnerPanelBackground: Color {
        template == .simple ? Color.white.opacity(0.72) : Color.black.opacity(0.55)
    }

    private var innerPanelStroke: Color {
        template == .simple ? Color.black.opacity(0.10) : Color.white.opacity(0.12)
    }

    private var logoCircleBackground: Color {
        template == .simple ? Color.black.opacity(0.06) : Color.white.opacity(0.12)
    }

    private func titleFont(size: CGFloat, weight: Font.Weight) -> Font {
        // iOSに「メイリオ」を要求できないため、可読性重視で日本語に強いシステム書体へ寄せる。
        if template == .simple {
            return .system(size: size, weight: weight, design: .default)
        }
        return .system(size: size, weight: weight, design: .rounded)
    }

    private func valueFont(size: CGFloat, weight: Font.Weight) -> Font {
        switch template {
        case .simple:
            return .system(size: size, weight: weight, design: .default)
        case .keiji:
            // 行書体は端末依存なので、候補を順に試して雰囲気を寄せる（無ければシステムへ）
            return firstAvailableFont(
                size: size,
                weight: weight,
                candidates: [
                    "HiraMinProN-W6",
                    "HiraginoMinchoProN-W6",
                    "HiraginoMinchoProN-W3",
                    "YuMincho-Demibold",
                    "YuMincho-Regular",
                    "HiraginoSans-W6"
                ],
                fallback: .system(size: size, weight: weight, design: .serif)
            )
        case .eva:
            // デジタル数字っぽさ：モノスペ＋字間
            return .system(size: size, weight: weight, design: .monospaced)
        }
    }

    private func firstAvailableFont(size: CGFloat, weight: Font.Weight, candidates: [String], fallback: Font) -> Font {
        #if canImport(UIKit)
        for name in candidates {
            if UIFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        #endif
        return fallback
    }

    private func plainSignedNumber(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        let absStr = f.string(from: NSNumber(value: abs(n))) ?? "\(abs(n))"
        if n > 0 { return "+\(absStr)" }
        if n < 0 { return "-\(absStr)" }
        return "0"
    }

    private func toKanjiNumber(_ n: Int) -> String {
        // ざっくり：万/千/百/十。負数は先頭に「マイナス」。
        func digitKanji(_ d: Int) -> String {
            switch d {
            case 1: return "一"
            case 2: return "二"
            case 3: return "三"
            case 4: return "四"
            case 5: return "五"
            case 6: return "六"
            case 7: return "七"
            case 8: return "八"
            case 9: return "九"
            default: return ""
            }
        }
        let sign = n < 0 ? "マイナス" : (n > 0 ? "＋" : "")
        let x = abs(n)
        if x == 0 { return "零" }
        let man = x / 10_000
        let rest = x % 10_000
        let sen = rest / 1000
        let hyaku = (rest % 1000) / 100
        let juu = (rest % 100) / 10
        let ichi = rest % 10
        var out = ""
        if man > 0 { out += (man == 1 ? "" : digitKanji(man)) + "万" }
        if sen > 0 { out += (sen == 1 ? "" : digitKanji(sen)) + "千" }
        if hyaku > 0 { out += (hyaku == 1 ? "" : digitKanji(hyaku)) + "百" }
        if juu > 0 { out += (juu == 1 ? "" : digitKanji(juu)) + "十" }
        if ichi > 0 { out += digitKanji(ichi) }
        return sign + out
    }

    private var profitDisplayText: String {
        switch template {
        case .simple:
            return plainSignedNumber(profitPt)
        case .keiji:
            return plainSignedNumber(profitPt)
        case .eva:
            return plainSignedNumber(profitPt)
        }
    }

    var body: some View {
        ZStack {
            background
            VStack(alignment: .leading, spacing: 10) {
                header
                metricsStack
                footer
            }
            .padding(24)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .stroke(borderStroke, lineWidth: 4)
        )
        .overlay {
            if template == .simple {
                // 枠の“手前”に出す（枠の後ろで切れて見えるのを防ぐ）
                sparklesBadge
            }
        }
        .drawingGroup()
    }

    @ViewBuilder
    private var background: some View {
        switch template {
        case .simple:
            ZStack {
                LinearGradient(colors: [Color.white, Color(red: 0.96, green: 0.97, blue: 0.99)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(
                    colors: [Color.black.opacity(0.06), .clear],
                    center: .bottomTrailing,
                    startRadius: 10,
                    endRadius: 720
                )
                rocketBackdrop
            }
        case .keiji:
            ZStack {
                // 紅白＋金箔
                LinearGradient(
                    colors: [Color(red: 0.32, green: 0.02, blue: 0.06), Color(red: 0.92, green: 0.92, blue: 0.90), Color(red: 0.20, green: 0.02, blue: 0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                KeijiSakuraConfetti()
                    .opacity(0.55)
                KeijiGoldFoil()
                    .opacity(0.22)
                rocketBackdrop.opacity(0.20)
            }
        case .eva:
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.02, green: 0.06, blue: 0.16), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                EvaCircuitBoard()
                    .opacity(0.95)
                EvaNeonGlow()
                    .opacity(0.85)
                rocketBackdrop.opacity(0.16)
            }
        }
    }

    private var rocketBackdrop: some View {
        // シンプルなロケット（上方に飛ぶ）を背景に薄く配置
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Image(systemName: "rocket.fill")
                .resizable()
                .scaledToFit()
                .frame(width: w * 0.52)
                .foregroundStyle(template == .simple ? Color.black.opacity(0.08) : Color.white.opacity(0.08))
                .rotationEffect(.degrees(-18))
                .position(x: w * 0.78, y: h * 0.38)
        }
        .allowsHitTesting(false)
    }

    private var sparklesBadge: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Image(systemName: "sparkles")
                .resizable()
                .scaledToFit()
                .frame(width: w * 0.11)
                .foregroundStyle(Color.black.opacity(0.08))
                .position(x: w * 0.86, y: h * 0.22)
        }
        .allowsHitTesting(false)
    }

    private var borderStroke: LinearGradient {
        switch template {
        case .simple:
            return LinearGradient(colors: [Color.black.opacity(0.16), Color.black.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .keiji:
            return LinearGradient(colors: [Color(red: 0.98, green: 0.86, blue: 0.35).opacity(0.9), .white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .eva:
            return LinearGradient(colors: [Color(red: 0.75, green: 0.25, blue: 1.0).opacity(0.85), Color(red: 0.35, green: 1.0, blue: 0.55).opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.machineName)
                .font(titleFont(size: 98, weight: .heavy))
                .foregroundStyle(baseTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            if showShopName, !snapshot.shopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(snapshot.shopName)
                    .font(titleFont(size: 56, weight: .semibold))
                    .foregroundStyle(subTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var metricsStack: some View {
        VStack(spacing: 12) {
            // 収支
            profitBox

            // 大当たり回数（1行）
            metricBox(title: "大当たり回数", value: winCountDisplay, valueColor: baseTextColor, valueMinScale: 0.66, titleSize: 32, valueSize: 80)

            // 総回転数／平均初あたり
            HStack(spacing: 16) {
                metricBox(title: "総回転数", value: normalRotationsDisplay, valueColor: baseTextColor, valueMinScale: 0.72, titleSize: 32, valueSize: 76)
                metricBox(title: "平均初あたり", value: avgFirstHitDisplay, valueColor: baseTextColor, valueMinScale: 0.72, titleSize: 32, valueSize: 76)
            }

            // 実質回転率 ／ ボーダー＋N回（=差）
            HStack(spacing: 16) {
                metricBox(
                    title: "実質回転率",
                    value: realRate.flatMap { r -> String? in
                        guard r.isValidForNumericDisplay else { return nil }
                        return r.displayFormat("%.1f 回/1k")
                    } ?? "—",
                    valueColor: baseTextColor,
                    valueMinScale: 0.78,
                    titleSize: 32,
                    valueSize: 72
                )
                metricBox(
                    title: "ボーダー＋",
                    value: borderDiff.flatMap { d -> String? in
                        guard d.isValidForNumericDisplay else { return nil }
                        return "\(d >= 0 ? "+" : "")\(d.displayFormat("%.1f")) 回/1k"
                    } ?? "—",
                    valueColor: borderDiff.map { $0 >= 0 ? (template == .simple ? Color(red: 0.10, green: 0.50, blue: 0.90) : Color(red: 0.38, green: 0.95, blue: 0.70)) : Color(red: 1.00, green: 0.42, blue: 0.42) } ?? subTextColor,
                    valueMinScale: 0.76,
                    titleSize: 32,
                    valueSize: 72
                )
            }
        }
    }

    private var profitBox: some View {
        switch template {
        case .eva:
            return AnyView(EvaProfitIndicatorBox(title: "", signedNumber: profitDisplayWithUnit, profit: profitPt, bigFontSize: 124))
        case .keiji:
            return AnyView(bigMetricBox(title: "", value: profitDisplayWithUnit, valueColor: profitPt >= 0 ? Color(red: 0.88, green: 0.72, blue: 0.22) : Color(red: 0.75, green: 0.10, blue: 0.10)))
        case .simple:
            return AnyView(bigMetricBox(title: "", value: profitDisplayWithUnit, valueColor: profitPt >= 0 ? Color(red: 0.05, green: 0.35, blue: 0.90) : Color(red: 0.90, green: 0.10, blue: 0.10)))
        }
    }

    private func metricBox(title: String, value: String, valueColor: Color, valueMinScale: CGFloat = 0.75, titleSize: CGFloat = 30, valueSize: CGFloat = 64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(titleFont(size: titleSize, weight: .semibold))
                .foregroundStyle(subTextColor)
            Text(value)
                .font(valueFont(size: valueSize, weight: .heavy))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(valueMinScale)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardInnerPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(innerPanelStroke, lineWidth: 1)
        )
    }

    private func bigMetricBox(title: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(title)
                    .font(titleFont(size: 32, weight: .semibold))
                    .foregroundStyle(subTextColor)
            }
            Text(value)
                .font(valueFont(size: 140, weight: .black))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardInnerPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(innerPanelStroke, lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack {
            // ロゴ（画像アセットを要求しない）
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(logoCircleBackground)
                    Text("P")
                        .font(titleFont(size: 22, weight: .heavy))
                        .foregroundStyle(baseTextColor)
                }
                .frame(width: 40, height: 40)
                Text("P-stats")
                    .font(titleFont(size: 28, weight: .heavy))
                    .foregroundStyle(baseTextColor)
            }
            Spacer()
            Text(JapaneseDateFormatters.yearMonthDay.string(from: snapshot.date))
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(subTextColor)
        }
        .padding(.top, 8)
    }
}

// MARK: - Profit special boxes

private struct EvaProfitIndicatorBox: View {
    let title: String
    let signedNumber: String
    let profit: Int
    let bigFontSize: CGFloat

    private var glow: Color { profit >= 0 ? Color(red: 0.35, green: 0.95, blue: 1.0) : Color(red: 1.0, green: 0.42, blue: 0.42) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(title)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
            Text(signedNumber)
                .font(.system(size: bigFontSize, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.95))
                .tracking(1.0)
                .shadow(color: glow.opacity(0.75), radius: 14, x: 0, y: 0)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

// ゴールド系テンプレは一旦削除（必要なら復活）
// MARK: - Template backgrounds (pure SwiftUI)

private struct KeijiSakuraConfetti: View {
    var body: some View {
        Canvas { ctx, size in
            let count = 120
            for i in 0..<count {
                let t = Double(i) / Double(count)
                let x = size.width * CGFloat((t * 977).truncatingRemainder(dividingBy: 1))
                let y = size.height * CGFloat(((t * 571).truncatingRemainder(dividingBy: 1)))
                let r = CGFloat(4 + (t * 10).truncatingRemainder(dividingBy: 6))
                let p = Path(ellipseIn: CGRect(x: x, y: y, width: r * 1.6, height: r))
                let c = Color(red: 1.0, green: 0.75, blue: 0.88).opacity(0.55)
                ctx.fill(p, with: .color(c))
            }
        }
    }
}

private struct KeijiGoldFoil: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.88, blue: 0.35).opacity(0.35),
                Color(red: 0.95, green: 0.70, blue: 0.18).opacity(0.12),
                Color(red: 1.0, green: 0.92, blue: 0.55).opacity(0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .blur(radius: 18)
    }
}

private struct EvaCircuitBoard: View {
    var body: some View {
        Canvas { ctx, size in
            func stroke(_ path: Path, _ color: Color, _ width: CGFloat) {
                ctx.stroke(path, with: .color(color), lineWidth: width)
            }

            let colors: [Color] = [
                Color(red: 0.45, green: 0.90, blue: 1.00).opacity(0.55), // 水色
                Color(red: 0.20, green: 0.65, blue: 1.00).opacity(0.45), // 青
                Color(red: 1.00, green: 0.90, blue: 0.25).opacity(0.35), // 黄
                Color.white.opacity(0.22)
            ]

            // 幹線（回路）
            for i in 0..<14 {
                let t = CGFloat(i) / 13
                let y0 = size.height * (0.12 + 0.76 * t)
                let bend = (i % 2 == 0) ? CGFloat(64) : CGFloat(-64)
                var p = Path()
                p.move(to: CGPoint(x: -40, y: y0))
                p.addLine(to: CGPoint(x: size.width * 0.36, y: y0))
                p.addLine(to: CGPoint(x: size.width * 0.36, y: y0 + bend))
                p.addLine(to: CGPoint(x: size.width + 40, y: y0 + bend))
                stroke(p, colors[i % colors.count], i % 3 == 0 ? 2.0 : 1.2)
            }

            // 垂直の配線
            for i in 0..<10 {
                let t = CGFloat(i) / 9
                let x0 = size.width * (0.10 + 0.80 * t)
                var p = Path()
                p.move(to: CGPoint(x: x0, y: -40))
                p.addLine(to: CGPoint(x: x0, y: size.height + 40))
                stroke(p, colors[(i * 2) % colors.count].opacity(0.7), 0.9)
            }

            // ノード（接点）
            for i in 0..<52 {
                let t = Double(i) / 52.0
                let x = size.width * CGFloat((t * 977).truncatingRemainder(dividingBy: 1))
                let y = size.height * CGFloat((t * 571).truncatingRemainder(dividingBy: 1))
                let r: CGFloat = (i % 9 == 0) ? 4.8 : 3.2
                let c = colors[(i * 3) % colors.count]
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                stroke(Path(ellipseIn: rect), c, 1.1)
            }
        }
        .blur(radius: 0.6)
    }
}

private struct EvaNeonGlow: View {
    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(red: 0.75, green: 0.25, blue: 1.0).opacity(0.45), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 700
            )
            RadialGradient(
                colors: [Color(red: 0.35, green: 1.0, blue: 0.55).opacity(0.38), .clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 760
            )
        }
        .blur(radius: 10)
    }
}

// ゴールド系テンプレは一旦削除（必要なら復活）

