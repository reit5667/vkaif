import SwiftUI
import WebKit

// MARK: - Auth View

/// Экран авторизации: показывает WKWebView с OAuth страницей VK.
/// Когда пользователь войдёт — AuthService получит токен.
struct AuthView: View {

    @ObservedObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                if let url = authService.buildAuthURL() {
                    WebView(url: url, authService: authService)
                } else {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("Не удалось построить URL авторизации")
                            .padding()
                    }
                }

                // Если авторизация успешна — закрываем экран
                if case .authenticated = authService.state {
                    Color.clear
                        .onAppear {
                            dismiss()
                        }
                }
            }
            .navigationTitle("Вход ВКонтакте")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - WKWebView Wrapper (UIViewRepresentable)

/// Обёртка для WKWebView в SwiftUI.
/// Отслеживает навигацию и передаёт redirect URL в AuthService.
struct WebView: UIViewRepresentable {

    let url: URL
    let authService: AuthService

    func makeCoordinator() -> Coordinator {
        Coordinator(authService: authService)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }

    // MARK: - Coordinator (WKNavigationDelegate)

    class Coordinator: NSObject, WKNavigationDelegate {

        let authService: AuthService

        init(authService: AuthService) {
            self.authService = authService
        }

        /// Вызывается перед каждой навигацией.
        /// Если URL = blank.html — парсим токен, отменяем загрузку страницы.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Если это redirect на blank.html — обрабатываем токен
            if url.absoluteString.hasPrefix("https://oauth.vk.com/blank.html") {
                Task { @MainActor in
                    authService.handleRedirect(url: url)
                }
                decisionHandler(.cancel) // Не грузим blank.html
                return
            }

            decisionHandler(.allow)
        }
    }
}

// MARK: - Preview

#Preview {
    AuthView(authService: AuthService())
}
