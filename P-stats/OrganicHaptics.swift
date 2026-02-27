import Foundation
import UIKit
import CoreHaptics

/// RUSH押下用：Organic Heartbeat（有機的心拍）パターン
/// 興奮を煽る短い強パルス3回 → 深い低周波の2連振動（心拍）をゆらぎ付きで繰り返す
enum OrganicHaptics {
    private static var engine: CHHapticEngine?

    /// Organic Heartbeat パターンを再生。メインスレッド以外から呼んでも内部でディスパッチする
    static func playRushHeartbeat() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        if Thread.isMainThread {
            playRushHeartbeatImpl()
        } else {
            DispatchQueue.main.async { playRushHeartbeatImpl() }
        }
    }

    private static func playRushHeartbeatImpl() {
        do {
            let e = try engine ?? CHHapticEngine()
            if engine == nil {
                engine = e
                try e.start()
                e.resetHandler = { [weak engine] in
                    try? engine?.start()
                }
                e.stoppedHandler = { [weak engine] _ in
                    try? engine?.start()
                }
            }
            var events: [CHHapticEvent] = []

            // Phase 1: 興奮を煽る短い強めのパルスを3回
            let pulseTimes: [TimeInterval] = [0, 0.06, 0.14]
            for t in pulseTimes {
                let ev = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.75)
                    ],
                    relativeTime: t
                )
                events.append(ev)
            }

            // Phase 2: 深い重み（低周波の2連振動＝心拍）。ゆらぎを持って繰り返す
            // 低 sharpness = 重く・低周波。intensity を少しずつ変えて「中身に重い液体が満たされていく」感触に
            let heartbeatPairs: [(TimeInterval, TimeInterval, Float, Float)] = [
                (0.28, 0.40, 0.94, 0.30),
                (0.62, 0.75, 0.88, 0.26),
                (0.99, 1.12, 0.91, 0.28)
            ]
            let sharpnessDeep: Float = 0.16
            for (t1, t2, i1, i2) in heartbeatPairs {
                let ev1 = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: i1),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpnessDeep)
                    ],
                    relativeTime: t1
                )
                let ev2 = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: i2),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpnessDeep + 0.05)
                    ],
                    relativeTime: t2
                )
                events.append(ev1)
                events.append(ev2)
            }

            // 心拍フェーズ全体を包む「重み」：持続の弱い低周波で液体が満たされるような質感
            let sustain = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.22),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.08)
                ],
                relativeTime: 0.26,
                duration: 0.92
            )
            events.append(sustain)

            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try e.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // フォールバック: 従来の Impact で代用（Core Haptics 非対応 or エラー時）
            let g = UIImpactFeedbackGenerator(style: .heavy)
            g.impactOccurred()
        }
    }
}
