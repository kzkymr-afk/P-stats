import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - スキン（見た目）の契約
//
// ご要望の「AppTheme プロトコル」に相当する型です。
// 既に `Core/Models.swift` の `enum AppTheme`（表示モード設定）が存在するため、
// プロトコル名は `ApplicationTheme` とし、ビルド衝突を避けています。

/// どのスキンでも共通して定義しておく色・形状・フォント識別子。
protocol ApplicationTheme {
    /// メインのアクセント色
    var accentColor: Color { get }
    /// パネルやカードの背景色
    var panelBackground: Color { get }
    /// 標準的な文字色
    var mainTextColor: Color { get }
    /// 補足情報の文字色
    var subTextColor: Color { get }
    /// パネルの角丸の大きさ
    var cornerRadius: CGFloat { get }
    /// 枠線の太さ
    var borderWidth: CGFloat { get }
    /// メインで使用するフォント名（システムフォントの場合は識別用の論理名）
    var fontName: String { get }

    // MARK: - 実戦・インサイト（セマンティック色）

    /// 実戦の「通常」系カウント・状態表示（旧 `AppGlassStyle.normalColor`）
    var playNormalAccent: Color { get }
    /// RUSH 系の強調（旧 `AppGlassStyle.rushColor`）
    var playRushAccent: Color { get }
    /// 投資ゾーン見出し（現金・持ち玉）
    var playInvestmentHeadline: Color { get }
    /// 実戦カード類の枠線（単色）
    var playCardOutline: Color { get }
    /// インサイトドロワー全体の背景
    var insightDrawerBackdrop: Color { get }
    /// インサイト内の区画・行の面
    var insightSectionSurface: Color { get }
}

/// 現行の `DesignTokens` / `AppGlassStyle` / `AppDesignSystem` と同じ値を束ねたデフォルトスキン。
struct DefaultTheme: ApplicationTheme {
    var accentColor: Color { AppGlassStyle.accent }
    var panelBackground: Color { AppGlassStyle.cardBackground }
    var mainTextColor: Color { AppGlassStyle.textPrimary }
    var subTextColor: Color { AppGlassStyle.textSecondary }
    var cornerRadius: CGFloat { DesignTokens.CornerRadius.panel }
    var borderWidth: CGFloat { AppDesignSystem.CardStyle.strokeLineWidth }

    /// SF の Rounded デザイン（`Font.system(..., design: .rounded)` と整合）。カスタムフォント差し替え時は PostScript 名などに置き換え。
    var fontName: String { "SF Pro Rounded" }

    var playNormalAccent: Color { AppGlassStyle.normalColor }
    var playRushAccent: Color { AppGlassStyle.rushColor }
    var playInvestmentHeadline: Color { Color(red: 1.0, green: 0.35, blue: 0.32) }
    var playCardOutline: Color { Color.white.opacity(0.14) }
    var insightDrawerBackdrop: Color { AppGlassStyle.background }
    var insightSectionSurface: Color { AppGlassStyle.rowBackground }
}

extension DefaultTheme {
    /// 環境や DI なしで参照するシングルトン的デフォルト。
    static let shared = DefaultTheme()
}

// MARK: - テーマに基づくフォント

extension ApplicationTheme {
    /// `fontName` が SF Pro Rounded（既定）のときはシステムの Rounded／Monospaced を使う。
    /// `system.default` は標準のサンセリフ（モダンなゴシック体に近いシステム UI フォント）。
    func themedFont(size: CGFloat, weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        let n = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        let useSystemDefault = n == "system.default" || n == "system.sans"
        if useSystemDefault {
            return .system(size: size, weight: weight, design: monospaced ? .monospaced : .default)
        }
        let useSystemRounded = n.isEmpty
            || n.localizedCaseInsensitiveContains("SF Pro Rounded")
            || n == "system.rounded"
        if useSystemRounded {
            return .system(size: size, weight: weight, design: monospaced ? .monospaced : .rounded)
        }
        return Font.custom(n, size: size)
    }

    /// PostScript 名など **実フォント名** を `fontName` にしたスキン用。バンドルに無い名前のときはシステム系へフォールバックし、黙って潰れるのを防ぐ。
    /// - Note: カスタムフォント追加手順: フォントファイルをプロジェクトに追加 → Target Membership をオン → Info.plist の `UIAppFonts` にファイル名を列挙 → 実行時に `UIFont.familyNames` 等で実名を確認して `fontName` に設定。
    func themedFontResolvingCustomName(size: CGFloat, weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        let n = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLogicalToken = n.isEmpty
            || n == "system.default"
            || n == "system.sans"
            || n == "system.rounded"
            || n.localizedCaseInsensitiveContains("SF Pro Rounded")
        if isLogicalToken {
            return themedFont(size: size, weight: weight, monospaced: monospaced)
        }
        #if canImport(UIKit)
        if UIFont(name: n, size: size) != nil {
            return Font.custom(n, size: size)
        }
        #endif
        return themedFont(size: size, weight: weight, monospaced: monospaced)
    }
}

// MARK: - スキン識別子（設定の保存・Picker 用）

enum PStatsSkin: String, CaseIterable, Identifiable, Hashable {
    /// 現行のグラス／DesignTokens ベース
    case standard = "standard"
    /// 近未来・サイバーパンク（角ばり・ネオン枠）
    case neonCyber = "neonCyber"

    var id: String { rawValue }

    static let storageKey = "pstatsApplicationSkin"

    var title: String {
        switch self {
        case .standard: return "デフォルト（グラス）"
        case .neonCyber: return "ネオンサイバー"
        }
    }

    func resolveTheme() -> any ApplicationTheme {
        switch self {
        case .standard: return DefaultTheme.shared
        case .neonCyber: return NeonCyberTheme.shared
        }
    }
}

// MARK: - ネオンサイバー（別スキン）

struct NeonCyberTheme: ApplicationTheme {
    var accentColor: Color { Color(red: 191 / 255, green: 0, blue: 1) }
    var panelBackground: Color { .black }
    var mainTextColor: Color { Color(red: 0.94, green: 0.96, blue: 1) }
    var subTextColor: Color { Color(red: 0.55, green: 0.48, blue: 0.82) }
    var cornerRadius: CGFloat { 0 }
    var borderWidth: CGFloat { 2 }
    /// システムの標準サンセリフ（カスタム PostScript 名に依存しない）
    var fontName: String { "system.default" }

    var playNormalAccent: Color { Color(hex: "00FFFF") }
    var playRushAccent: Color { Color(red: 191 / 255, green: 0, blue: 1) }
    var playInvestmentHeadline: Color { Color(red: 1.0, green: 0.42, blue: 0.38) }
    var playCardOutline: Color { Color(red: 191 / 255, green: 0, blue: 1).opacity(0.72) }
    var insightDrawerBackdrop: Color { Color.black }
    var insightSectionSurface: Color { Color.white.opacity(0.07) }
}

extension NeonCyberTheme {
    static let shared = NeonCyberTheme()
}
