import Foundation
import SwiftData

/// スキーマ移行（VersionedSchema）だけでは吸収しづらい「意味のあるデフォルト」や
/// 旧データの整合を、アプリ起動時に一括で正規化する。
///
/// - 注意: 「黙って値を変える」ことで分析が変わるのは避けたいので、
///   ここでは **欠損の明らかな派生値のみ**（再計算しても意味が変わりにくいもの）を対象にする。
enum PStatsDataNormalizer {
    private static let normalizationKey = "PStatsDataNormalizer.lastRun.v1"

    /// ストアを開いた直後に 1 回だけ実行する想定。
    @MainActor
    static func normalizeIfNeeded(container: ModelContainer) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: normalizationKey) { return }

        let ctx = ModelContext(container)
        do {
            try normalizeSessions(ctx: ctx)
            try ctx.save()
            defaults.set(true, forKey: normalizationKey)
        } catch {
            // 正規化に失敗してもアプリを落とさない（次回以降に再試行できる）
        }
    }

    @MainActor
    private static func normalizeSessions(ctx: ModelContext) throws {
        let sessions = try ctx.fetch(FetchDescriptor<GameSession>())
        for s in sessions {
            // 期待値：totalRealCost と expectationRatio が入っているのに theoreticalValue が 0 の行を救う
            if s.theoreticalValue == 0, s.totalRealCost > 0, s.expectationRatioAtSave > 0 {
                let tv = PStatsCalculator.theoreticalValuePt(
                    totalRealCostPt: s.totalRealCost,
                    expectationRatio: s.expectationRatioAtSave
                )
                // 0 のままなら書かない（不正値・期待値比1.0等）
                if tv != 0 { s.theoreticalValue = tv }
            }

            // 実質回転率：保存値が 0 だが raw から算出できる場合のみ埋める（表示計算の高速化・互換補助）
            if s.realRotationRateAtSave == 0, s.totalRealCost > 0, s.normalRotations > 0 {
                if let r = PStatsCalculator.realRotationRatePer1k(
                    normalRotations: s.normalRotations,
                    totalRealCostPt: s.totalRealCost,
                    fallbackRateAtSave: 0
                ) {
                    s.realRotationRateAtSave = r
                }
            }
        }
    }
}

