import Foundation
import SwiftData
import os

/// スキーマ移行（VersionedSchema）だけでは吸収しづらい「意味のあるデフォルト」や
/// 旧データの整合を、ストアオープン直後に **版付き**で実行する。
///
/// - 注意: 「黙って値を変える」ことで分析が変わるのは避けたいので、
///   ここでは **欠損の明らかな派生値のみ**（再計算しても意味が変わりにくいもの）を対象にする。
///
/// ## 正規化を追加するとき
/// 1. `applyNormalizationSteps` に **冪等**な処理だけ追加する。
/// 2. `currentNormalizationRevision` を **1 つ上げる**（未適用ユーザーだけ再実行される）。
enum PStatsDataNormalizer {

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "P-stats", category: "PStatsDataNormalizer")

    /// 実装済み正規化ロジックの最新版。手順を足したら必ずインクリメントする。
    private static let currentNormalizationRevision = 1

    private static let appliedRevisionKey = "PStatsDataNormalizer.appliedNormalizationRevision"
    /// 旧実装（bool）からの移行用
    private static let legacyBoolKey = "PStatsDataNormalizer.lastRun.v1"

    /// `ModelContainer` 生成直後・UI が `@Query` する前に呼ぶ。
    @MainActor
    static func normalizeIfNeeded(container: ModelContainer) {
        let defaults = UserDefaults.standard
        migrateLegacyDefaults(defaults)

        let applied = defaults.integer(forKey: appliedRevisionKey)
        guard applied < currentNormalizationRevision else { return }

        let ctx = ModelContext(container)
        do {
            try applyNormalizationSteps(fromRevision: applied, ctx: ctx)
            try ctx.save()
            defaults.set(currentNormalizationRevision, forKey: appliedRevisionKey)
        } catch {
            log.error("正規化に失敗: \(String(describing: error), privacy: .public)")
            // 失敗時は revision を進めない → 次回起動で再試行
        }
    }

    private static func migrateLegacyDefaults(_ defaults: UserDefaults) {
        guard defaults.object(forKey: legacyBoolKey) != nil else { return }
        if defaults.bool(forKey: legacyBoolKey), defaults.object(forKey: appliedRevisionKey) == nil {
            defaults.set(1, forKey: appliedRevisionKey)
        }
        defaults.removeObject(forKey: legacyBoolKey)
    }

    /// `fromRevision` は「すでに適用済みの版」。`fromRevision+1 ... current` のステップを想定（現状は一括）。
    @MainActor
    private static func applyNormalizationSteps(fromRevision: Int, ctx: ModelContext) throws {
        // 将来: if fromRevision < 2 { try stepV2(ctx) }
        //       if fromRevision < 3 { try stepV3(ctx) }
        _ = fromRevision
        try normalizeSessions(ctx: ctx)
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

