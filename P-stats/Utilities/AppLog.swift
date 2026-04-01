import Foundation
import os

/// 本番では `print` を使わず Unified Logging のみ。デバッグ詳細は `#if DEBUG` で抑制。
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "P-stats"

    static let places = Logger(subsystem: subsystem, category: "Places")
    static let machineMaster = Logger(subsystem: subsystem, category: "MachineMaster")
    static let presets = Logger(subsystem: subsystem, category: "Presets")
}
