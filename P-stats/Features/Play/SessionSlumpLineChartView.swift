import SwiftUI

/// 大当たりモード用：横軸＝通常累積回転、縦軸＝損益（pt）。`liveChartPoints` を利用。
struct SessionSlumpLineChartView: View {
    @Bindable var log: GameLog
    var height: CGFloat
    /// 枠・軸ラベル用（RUSH 色で統一可能）
    var strokeTint: Color

    /// 横軸最大：300回未満のときは300、それ以降は現在の通常回転に合わせる
    private var xAxisMax: CGFloat {
        let n = log.normalRotations
        if n < 300 { return 300 }
        return CGFloat(max(n, 1))
    }

    private var yRange: (min: Double, max: Double) {
        let pts = log.liveChartPoints.map(\.1)
        let dataMin = pts.min() ?? 0
        let dataMax = pts.max() ?? 0
        let spanNeeded = max(abs(dataMin), abs(dataMax))
        let half = max(SessionSlumpChartStyle.defaultHalfRangePt, spanNeeded * 1.08)
        return (-half, half)
    }

    var body: some View {
        SessionSlumpChartCanvas(
            points: log.liveChartPoints,
            yRange: yRange,
            xAxisMax: xAxisMax,
            strokeTint: strokeTint,
            height: height
        )
    }
}
