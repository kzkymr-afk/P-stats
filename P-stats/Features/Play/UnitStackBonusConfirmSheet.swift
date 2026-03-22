import SwiftUI

/// ユニット連結型（基本＋追撃）を確定するためのシート
struct UnitStackBonusConfirmSheet: View {
    let bonus: BonusDetail
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void

    @State private var unitTapAmounts: [Int] = []

    private var base: Int { max(0, bonus.baseOut) }
    private var payouts: [Int] { bonus.positiveUnitOuts }
    private var maxStack: Int { max(1, bonus.maxStack) }
    private var canStack: Bool { !payouts.isEmpty && maxStack > 0 }

    private var total: Int { base + unitTapAmounts.reduce(0, +) }
    private var tapCount: Int { unitTapAmounts.count }

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
                HStack(alignment: .top, spacing: 12) {
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

                    // 追撃（ユニット出玉・複数ならサブボタン）
                    Group {
                        if payouts.count <= 1 {
                            let u = payouts.first ?? 0
                            Button {
                                guard canStack, tapCount < maxStack, u > 0 else { return }
                                unitTapAmounts.append(u)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                ZStack {
                                    AppGlassStyle.accent.opacity(0.18)
                                    VStack(spacing: 4) {
                                        Text("追撃")
                                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        Text("+\(u)")
                                            .font(.system(size: 18, weight: .black, design: .monospaced))
                                    }
                                    .foregroundStyle(AppGlassStyle.accent)
                                }
                                .frame(width: 120, height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppGlassStyle.accent.opacity(0.35), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(!canStack || tapCount >= maxStack || u <= 0)
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVGrid(
                                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                                    spacing: 8
                                ) {
                                    ForEach(Array(payouts.enumerated()), id: \.offset) { _, u in
                                        Button {
                                            guard canStack, tapCount < maxStack, u > 0 else { return }
                                            unitTapAmounts.append(u)
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        } label: {
                                            Text("＋\(u)")
                                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                                .foregroundStyle(AppGlassStyle.accent)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(AppGlassStyle.accent.opacity(0.18))
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppGlassStyle.accent.opacity(0.35), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(!canStack || tapCount >= maxStack || u <= 0)
                                    }
                                }
                            }
                            .frame(width: 120)
                            .frame(minHeight: 110, maxHeight: 160)
                        }
                    }
                }

                if canStack {
                    Text("追撃 \(tapCount)/\(maxStack)")
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
