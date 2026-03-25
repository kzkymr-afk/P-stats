# 指示書：Android 対応を見据えたファイル構成の再構築

エージェント・メモ用。実施済みの場合は現状構成の参照として利用。

---

## 1. 目的

- デザイン（色・余白・フォント・コンポーネント見た目）を独立したファイル・フォルダに集約し、将来 Android 版で同じトークンやルールを流用しやすくする。
- レイヤーごとにフォルダを分ける（App / Design / Core / Services / Features）ことで、共有ロジックと UI を分離し、Android 実装時の対応関係を分かりやすくする。
- 既存の挙動は変えず、移動・分割・参照の付け替えのみで再構成する。

---

## 2. 推奨フォルダ構成（P-stats 内）

```
P-stats/
├── P_statsApp.swift                    # @main・WindowGroup のみ（Bootstrap は App/AppBootstrap.swift）
├── App/                                # アプリ全体で1つだけのもの
│   ├── HomeBackgroundStore.swift
│   ├── PlayBackgroundStore.swift
│   └── TranslucentBlurView.swift
├── Design/                             # デザイン関連（Android で同じ値を使いやすいように）
│   ├── DesignTokens.swift              # 色・余白・フォントサイズの「値だけ」
│   ├── AppGlassStyle.swift             # SwiftUI 用の Color / Gradient（DesignTokens を参照）
│   ├── MetalStyle.swift                # メタル系の ViewModifier / ButtonStyle
│   └── Color+Hex.swift                # Color(hex:) 拡張
├── Core/                               # モデル・永続化・ゲームロジック
│   ├── Models.swift
│   ├── GameLog.swift
│   ├── MachineMasterModels.swift
│   ├── MachineDetailLoader.swift
│   ├── PrizeStringParser.swift
│   └── ResumableStateStore.swift
├── Services/                           # 外部API・マスタ取得・設定
│   ├── PresetService.swift
│   ├── PresetServiceConfig.swift
│   ├── SharedMachineCloudKitService.swift
│   ├── PlaceSearchService.swift
│   └── LocationManager.swift
├── Features/                           # 画面・機能ごと（SwiftUI View が中心）
│   ├── Play/
│   │   ├── PlayView.swift
│   │   └── BigHitModeView.swift
│   ├── MachineShop/
│   │   ├── MachineShopSelectionView.swift
│   │   ├── MachineEditView.swift
│   │   ├── MasterMachineSearchView.swift
│   │   └── PresetMasterView.swift
│   ├── Analytics/
│   │   ├── AnalyticsDashboardView.swift
│   │   └── AnalyticsEngine.swift
│   └── Common/
│       ├── InsightPanelView.swift
│       ├── InfoPopoverView.swift
│       ├── LaunchView.swift
│       ├── PowerSavingModeView.swift
│       ├── PlayEventHistoryView.swift
│       ├── GameSessionEditView.swift
│       └── PrizeSetListView.swift
├── Utilities/                          # 汎用ヘルパー
│   └── PlaceSearchFilter.swift
└── Resources/
    └── Assets.xcassets
```

---

## 3. デザインの分離（Design フォルダ）

### 3.1 DesignTokens.swift

- 色コード（hex / RGB）、余白・角丸・フォントサイズなど「数値・文字列だけ」を定義。
- SwiftUI の Color / View は持たない。Android の Theme / colors.xml / dimens.xml と揃えやすい。

### 3.2 AppGlassStyle.swift

- DesignTokens を参照して Color / Gradient を組み立てる。
- `background`, `accent`, `rushColor`, `modeColor(modeId:)`, `edgeGlowColor(border:realRate:)` など。

### 3.3 Color+Hex.swift

- `Color(hex: String)` 拡張。DesignTokens の hex 値からも利用。

### 3.4 MetalStyle.swift

- メタル質感の ViewModifier / ButtonStyle（MetalViewModifier, MetalButtonStyle, MetalRadialView, MetalLinearView, MetalSlider 等）。

---

## 4. 注意事項

- 同一ターゲット内ではフォルダは「見た目上の整理」で、名前空間は変わらない。既存の `AppGlassStyle.xxx` 等の参照はそのまま有効。
- Xcode で PBXFileSystemSynchronizedRootGroup を使っている場合、P-stats 配下のファイルは自動でビルドに含まれる。
- Android 用には DesignTokens を Markdown / JSON 等でエクスポートし、同じ値で Theme を組むとよい。

---

## 5. 実施状況

- [x] Design の分離（DesignTokens, Color+Hex, AppGlassStyle, MetalStyle）
- [x] App/ への Store・TranslucentBlurView 移動
- [x] Core / Services / Features / Utilities のフォルダ作成とファイル移動
- [ ] 設定画面を Features/Settings/ に分離（任意）
- [ ] Int.formattedYen を Utilities/Extensions 等にまとめる（任意）
