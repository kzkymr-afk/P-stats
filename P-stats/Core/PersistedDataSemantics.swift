import Foundation

// MARK: - 永続化データの意味付け（マイグレーション・解釈の単一参照点）

/// アプリの方針: **投入・回転・店・機種スペックなどの生データを永続化の主役**とし、派生指標は計算で再現できる構造に寄せる。
/// SwiftData で新プロパティを足すと「旧ストアにそのフィールドがない」状態が必ず発生するため、**未設定時の解釈はここと `*Interpreted` 拡張に集約**する（バラバラの `?? 0` を避ける）。
///
/// ## 運用ルール（コードレビュー用チェックリスト）
/// 1. **新プロパティ追加** → `VersionedSchema` で V2 を切り、`SchemaMigrationPlan` のステージで **バックフィル or 明示的デフォルト**を決める。意味のある値が「黙って 0」になるのを防ぐ。
/// 2. **計算式だけ変更** → 可能なら **再計算で直る**形（生データから導出）にし、派生値の永続化は最小限にする。
/// 3. **Optional vs デフォルト** → 「未記録」と「本当に 0」を区別したいときは Optional＋解釈、そうでなければここの既定とコメントで揃える。
enum PersistedDataSemantics {

    // MARK: 店舗（`Shop`）— 貸玉・払出

    /// 貸玉：**500pt あたり**の玉数。UI・`MachineShopSelectionView` の説明と一致。
    /// 未設定・0・負数の解釈に使う（旧データや欠損対策）。
    static let defaultBallsPer500Pt: Int = 125

    /// 払出係数：1 玉あたりの換金（pt/玉）。等価 **4.0**（1000pt＝250玉と整合）。
    static let defaultPayoutCoefficientPtPerBall: Double = 4.0

    // MARK: 実戦の現金投資粒度（`GameLog`・精算）

    /// 現金投資の記録単位（pt）。500pt ごとの貸玉換算の基準。
    static let cashInvestmentStepPt: Int = 500

    // MARK: 等価・回転率の「単位」（説明・GameLog と一致）

    /// 等価 **1000pt** に相当する玉数（**250 玉**）。実質回転率の分母・ボーダー説明の基準。
    static let equivalentBallsPer1000Pt: Double = 250

    /// 500pt あたり玉数から 1000pt あたり玉数へ: `ballsPer500 * (1000 / 500) = ballsPer500 * 2`
    static func ballsPer1000Pt(fromBallsPer500Pt balls: Int) -> Double {
        Double(max(0, balls)) * 2.0
    }

    // MARK: 機種まわりのフォールバック（新規インスタンス・表示）

    static let defaultMachineSupportLimit: Int = 100
    static let defaultMachinePrizeBalls: Int = 1500
}

// MARK: - Shop（欠損時の解釈）

extension Shop {
    /// 貸玉（500pt あたり玉数）。**0 以下**は未設定としてアプリ既定へ。
    var interpretedBallsPer500Pt: Int {
        if ballsPerCashUnit > 0 { return ballsPerCashUnit }
        return PersistedDataSemantics.defaultBallsPer500Pt
    }

    /// 払出係数（pt/玉）。**0 以下**は未設定としてアプリ既定へ。
    var interpretedPayoutCoefficientPtPerBall: Double {
        if payoutCoefficient > 0 { return payoutCoefficient }
        return PersistedDataSemantics.defaultPayoutCoefficientPtPerBall
    }

    /// `GameLog` 等で使う 1000pt あたりの玉数（内部計算用）。
    var interpretedBallsPer1000Pt: Double {
        PersistedDataSemantics.ballsPer1000Pt(fromBallsPer500Pt: interpretedBallsPer500Pt)
    }
}

// MARK: - GameSession（保存済み係数が欠ける行）

extension GameSession {
    /// 行に保存された払出係数。0 のときは **店舗の解釈値**、なければアプリ既定。
    func interpretedPayoutCoefficientPtPerBall(fallbackShop: Shop?) -> Double {
        if payoutCoefficient > 0 { return payoutCoefficient }
        if let shop = fallbackShop { return shop.interpretedPayoutCoefficientPtPerBall }
        return PersistedDataSemantics.defaultPayoutCoefficientPtPerBall
    }
}
