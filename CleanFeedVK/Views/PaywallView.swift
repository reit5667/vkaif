import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject var storeKit = StoreKitService.shared
    @Environment(\.dismiss) private var dismiss

    private let features = [
        ("waveform", "Без рекламы навсегда", "Никаких рекламных постов в ленте"),
        ("arrow.triangle.branch", "Чистая лента", "Только подписки без алгоритмических вставок"),
        ("music.note", "Музыка", "Полный доступ к аудиозаписям"),
        ("bubble.left.and.bubble.right", "Все функции", "Стикеры, голосовые, документы в чатах")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    featuresSection
                    purchaseSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .onChange(of: storeKit.purchaseState) { _, state in
            if state == .success || state == .restored { dismiss() }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.gradient)
                    .frame(width: 80, height: 80)
                Image(systemName: "crown.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }
            .padding(.top, 16)
            Text("CleanFeedVK Premium")
                .font(.title2.bold())
            Text("Один раз — навсегда")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(features, id: \.1) { icon, title, desc in
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.subheadline.weight(.semibold))
                        Text(desc).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            if storeKit.purchaseState == .purchasing {
                ProgressView("Обработка…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                Button {
                    Task { await storeKit.purchase() }
                } label: {
                    VStack(spacing: 4) {
                        Text("Купить")
                            .font(.headline)
                        if let product = storeKit.product {
                            Text(product.displayPrice)
                                .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            Button {
                Task { await storeKit.restore() }
            } label: {
                Text("Восстановить покупку")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
            .disabled(storeKit.purchaseState == .purchasing)

            if case .failed(let msg) = storeKit.purchaseState {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Text("Разовая покупка. Никаких подписок.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
