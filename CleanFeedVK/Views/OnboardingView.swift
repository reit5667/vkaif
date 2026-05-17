import SwiftUI

struct OnboardingView: View {
    @ObservedObject var authService: AuthService
    @State private var showAuth = false

    private let features: [(icon: String, title: String, description: String)] = [
        ("line.3.horizontal.decrease.circle", "Без алгоритмов", "Только посты людей и сообществ, на которые ты подписан. Никаких рекомендаций."),
        ("nosign", "Без рекламы", "Лента без спонсорских постов, рекламных блоков и продвигаемого контента."),
        ("eye.slash", "Только важное", "Чистый интерфейс — фокус на контенте, а не на отвлекающих элементах.")
    ]

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                headerSection
                Spacer()
                featuresSection
                Spacer()
                bottomSection
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showAuth) {
            AuthView(authService: authService)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.accentColor.gradient)
                    .frame(width: 88, height: 88)
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 6) {
                Text("CleanFeedVK")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("ВКонтакте без лишнего")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(features, id: \.title) { feature in
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: feature.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(Color.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(feature.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(feature.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var bottomSection: some View {
        VStack(spacing: 12) {
            Button {
                showAuth = true
            } label: {
                Text("Войти через ВКонтакте")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            Text("Используется OAuth авторизация VK.\nПароль не передаётся в приложение.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
