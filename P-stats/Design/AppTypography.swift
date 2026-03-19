import SwiftUI

/// 実装指示書「背景直載せテキストの削減と見出しタイポグラフィ」の共通定義。
/// 見出しは本文より少なくとも 1pt（推奨 2pt）大きくする。
enum AppTypography {
    /// パネル見出し（Main）— editPanel・ホーム収支カードの期間ラベル・セクション名など
    static let panelHeading = Font.system(size: 17, weight: .semibold, design: .rounded)
    /// サブ見出し — 実戦スタッツのラベル行・フォーカス画面の補助見出しなど
    static let sectionSubheading = Font.system(size: 15, weight: .semibold, design: .rounded)
    /// 本文・リスト主文
    static let bodyRounded = Font.system(size: 14, weight: .medium, design: .rounded)
    /// インサイトドロワー内のパネルタイトル（幅が狭いため上限 ~13pt）
    static let insightPanelTitle = Font.system(size: 13, weight: .semibold, design: .rounded)
    /// 本文（数値・主文・モノスペース）
    static let bodyMonoSemibold = Font.system(size: 14, weight: .semibold, design: .monospaced)
}
