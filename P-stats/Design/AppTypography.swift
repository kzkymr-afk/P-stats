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
    /// インサイトドロワー内のパネルタイトル（可読性優先で 15pt）
    static let insightPanelTitle = AppDesignSystem.Typography.insightPanelTitle
    /// 本文（数値・主文・モノスペース）
    static let bodyMonoSemibold = AppDesignSystem.Typography.bodyMonoSemibold
    /// 注釈（caption +1pt）
    static let annotation = AppDesignSystem.Typography.annotation
    static let annotationMedium = AppDesignSystem.Typography.annotationMedium
    static let annotationSemibold = AppDesignSystem.Typography.annotationSemibold
    static let annotationLight = AppDesignSystem.Typography.annotationLight
    static let annotationMonospacedDigitSemibold = AppDesignSystem.Typography.annotationMonospacedDigitSemibold
    /// 小さめ注釈（caption2 +1pt）
    static let annotationSmall = AppDesignSystem.Typography.annotationSmall
    static let annotationSmallMedium = AppDesignSystem.Typography.annotationSmallMedium
    static let annotationSmallSemibold = AppDesignSystem.Typography.annotationSmallSemibold
    static let annotationSmallMonospacedDigitSemibold = AppDesignSystem.Typography.annotationSmallMonospacedDigitSemibold
}
