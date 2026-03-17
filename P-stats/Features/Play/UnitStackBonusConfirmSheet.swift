import SwiftUI

/// ユニット連結型（基本＋追撃）を確定するためのシート
struct UnitStackBonusConfirmSheet: View {
    let bonus: BonusDetail
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void

    @State private var unitCount: Int = 0

    private var base: Int { max(0, bonus.baseOut) }
    private var unit: Int { max(0, bonus.unitOut) }
    private var maxStack: Int { max(1, bonus.maxStack) }
    private var canStack: Bool { unit > 0 && maxStack > 0 }

    private var total: Int { base + unit * unitCount }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("今回の出玉")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(total) 玉")
                        .font(.system(size: 52, weight: .black, design: .monospaced))
                        .foregroundStyle(AppGlassStyle.accent)
                }
                .padding(.top, 16)

                // メイン＋追撃（要件: メインの横に追撃ボタン）
                HStack(spacing: 12) {
                    // メイン（基本出玉）
                    ZStack {
                        Color.white.opacity(0.06)
                        VStack(spacing: 6) {
                            Text(bonus.name)
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            Text("基本 \(base)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                    }
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // 追撃（ユニット出玉）
                    Button {
                        guard canStack, unitCount < maxStack else { return }
                        unitCount += 1
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        ZStack {
                            AppGlassStyle.accent.opacity(0.18)
                            VStack(spacing: 4) {
                                Text("追撃")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                Text("+\(unit)")
                                    .font(.system(size: 18, weight: .black, design: .monospaced))
                            }
                            .foregroundStyle(AppGlassStyle.accent)
                        }
                        .frame(width: 120, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppGlassStyle.accent.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStack || unitCount >= maxStack)
                }

                if canStack {
                    Text("追撃 \(unitCount)/\(maxStack)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    Text("追撃なし（完結型）")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .navigationTitle("当たり確定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("確定") { onConfirm(total) }
                }
            }
        }
    }
}

