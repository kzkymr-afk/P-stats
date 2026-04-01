import SwiftUI

/// 実装指示書「背景直載せテキストの削減と見出しタイポグラフィ」の共通定義。
/// 見出しは本文より少なくとも 1pt（推奨 2pt）大きくする。
enum AppTypography {
    /// パネル見出し（Main）— editPanel・ホーム収支カードの期間ラベル・セクション名など
    static let panelHeading = AppDesignSystem.Typography.panelHeading
    /// サブ見出し — 実戦スタッツのラベル行・フォーカス画面の補助見出しなど
    static let sectionSubheading = AppDesignSystem.Typography.sectionSubheading
    /// 本文・リスト主文
    static let bodyRounded = AppDesignSystem.Typography.bodyRounded
    /// インサイトドロワー内のパネルタイトル（幅が狭いため上限 ~13pt）
    static let insightPanelTitle = AppDesignSystem.Typography.insightPanelTitle
    /// 本文（数値・主文・モノスペース）
    static let bodyMonoSemibold = AppDesignSystem.Typography.bodyMonoSemibold
}
