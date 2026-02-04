import SwiftUI
import WebKit

/// Контекст поста для панели под плеером: лайки и комментарии (как под фото).
struct VideoPlayerPostContext {
    let likesCount: Int
    let commentsCount: Int
    let isLiked: Bool
    let onLike: () -> Void
    let onTapComments: () -> Void
}

/// Полноэкранный плеер VK по URL. Закрытие — кнопка. Снизу только лайки и комментарии; реплей по центру после окончания; кнопка Play при паузе.
struct VideoPlayerView: View {
    let url: URL
    let onDismiss: () -> Void
    /// Если задан — показывается панель с лайками и комментариями (как под фото).
    var postContext: VideoPlayerPostContext? = nil

    @State private var replayTrigger = 0
    @State private var videoEnded = false
    /// true = видео на паузе (показываем кнопку возобновления).
    @State private var videoPaused = false
    /// Инкремент при тапе «Возобновить» — WebView выполняет video.play().
    @State private var playRequestTrigger = 0

    var body: some View {
        ZStack(alignment: .top) {
            VideoWebView(
                url: url,
                replayTrigger: replayTrigger,
                videoEnded: $videoEnded,
                videoPaused: $videoPaused,
                playRequestTrigger: playRequestTrigger
            )
            .ignoresSafeArea()

            VStack {
                HStack(spacing: 16) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    }
                    Spacer(minLength: 0)
                    Button(action: { playRequestTrigger += 1 }) {
                        Label("Возобновить", systemImage: "play.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    Button(action: {
                        videoEnded = false
                        replayTrigger += 1
                    }) {
                        Label("Повторить", systemImage: "arrow.clockwise.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)

                Spacer(minLength: 0)

                // Кнопка «Смотреть снова» — после окончания (если событие пришло).
                if videoEnded {
                    Button(action: {
                        videoEnded = false
                        replayTrigger += 1
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                            Text("Смотреть снова")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .background(Color.black.opacity(0.2))
                    }
                    .buttonStyle(.plain)
                    .zIndex(1)
                }

                Spacer(minLength: 0)

                bottomBar
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 24) {
            if let ctx = postContext {
                Button(action: ctx.onLike) {
                    Label("\(ctx.likesCount)", systemImage: ctx.isLiked ? "heart.fill" : "heart")
                        .font(.body)
                        .foregroundStyle(ctx.isLiked ? .red : .white)
                }
                .buttonStyle(.plain)

                Button(action: ctx.onTapComments) {
                    Label("\(ctx.commentsCount)", systemImage: "bubble.right.fill")
                        .font(.body)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        )
    }
}

/// Скрипт скрывает блоки рекомендаций (карточки «Эпизод», «следующее видео»). Не трогает элементы, содержащие video — иначе при паузе/конце получается черный экран.
private let hideOverlaysScript = """
(function() {
    var sel = '[class*="recommend"],[class*="Recommend"],[id*="recommend"],[class*="related"],[class*="Related"],[class*="suggest"],[class*="next-video"],[class*="NextVideo"],[class*="countdown"],[class*="Countdown"],[class*="autoplay"],[class*="Autoplay"],[class*="VideoCard"],[class*="video-card"],[data-class*="recommend"],[data-class*="related"]';
    var hideKeywords = ['следующ','начнётся через','next video','эпизод','история вселенной','история и геймдизайн','полная версия'];
    function containsVideo(el) { return el && (el.tagName === 'VIDEO' || (el.querySelector && el.querySelector('video'))); }
    function hide() {
        document.querySelectorAll(sel).forEach(function(el) {
            if (!containsVideo(el)) el.style.setProperty('display', 'none', 'important');
        });
        document.querySelectorAll('*').forEach(function(el) {
            if (containsVideo(el)) return;
            var t = (el.innerText || el.textContent || '').toLowerCase();
            var len = (el.innerText || el.textContent || '').length;
            if (len > 15 && len < 800 && hideKeywords.some(function(k) { return t.indexOf(k) >= 0; }))
                el.style.setProperty('display', 'none', 'important');
        });
    }
    hide();
    var t = 0, id = setInterval(function() { hide(); t++; if (t > 80) clearInterval(id); }, 350);
})();
"""

/// Держим video и его контейнеры видимыми — чтобы при паузе/конце не оставался черный экран (VK иногда скрывает плеер).
private let keepVideoVisibleScript = """
(function() {
    function keepVisible() {
        document.querySelectorAll('video').forEach(function(v) {
            v.style.setProperty('opacity', '1', 'important');
            v.style.setProperty('visibility', 'visible', 'important');
            v.style.setProperty('display', 'block', 'important');
            var p = v.parentElement;
            for (var i = 0; i < 8 && p; i++) {
                p.style.setProperty('opacity', '1', 'important');
                p.style.setProperty('visibility', 'visible', 'important');
                p.style.setProperty('display', '', 'important');
                p = p.parentElement;
            }
        });
    }
    keepVisible();
    setInterval(keepVisible, 600);
})();
"""

/// Единый скрипт для всех фреймов (в т.ч. iframe плеера VK): детект ended/pause, postMessage в main frame, приём requestPlay для воспроизведения.
/// Инжектируется как user script с forMainFrameOnly: false, чтобы срабатывал и внутри iframe с видео.
private let videoBridgeScript = """
(function() {
    function postEnded() {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.videoEnded)
            window.webkit.messageHandlers.videoEnded.postMessage('ended');
        else
            window.parent.postMessage({ type: 'videoEnded' }, '*');
    }
    function postPaused() {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.videoPaused)
            window.webkit.messageHandlers.videoPaused.postMessage('paused');
        else
            window.parent.postMessage({ type: 'videoPaused' }, '*');
    }
    window.addEventListener('message', function(e) {
        if (e.data && e.data.type === 'videoEnded' && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.videoEnded)
            window.webkit.messageHandlers.videoEnded.postMessage('ended');
        if (e.data && e.data.type === 'videoPaused' && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.videoPaused)
            window.webkit.messageHandlers.videoPaused.postMessage('paused');
        if (e.data && e.data.type === 'requestPlay') {
            var v = document.querySelector('video');
            if (v) v.play();
        }
    });
    function setupVideo(v) {
        if (!v || v.dataset.videoBridge) return;
        v.dataset.videoBridge = '1';
        v.addEventListener('ended', postEnded);
        v.addEventListener('pause', postPaused);
    }
    function setup() {
        var v = document.querySelector('video');
        setupVideo(v);
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', setup);
    else setup();
    [500, 1000, 2000, 4000].forEach(function(ms) { setTimeout(setup, ms); });
    setInterval(function() {
        var v = document.querySelector('video');
        if (v && v.ended && !v.dataset.reportedEnd) { v.dataset.reportedEnd = '1'; postEnded(); }
    }, 500);
})();
"""

/// Запрос воспроизведения из Swift (кнопка «Возобновить» или после реплея). Выполняется в main frame, iframe получит через postMessage.
private let videoRequestPlayScript = """
window.postMessage({ type: 'requestPlay' }, '*');
"""

private struct VideoWebView: UIViewRepresentable {
    let url: URL
    var replayTrigger: Int
    @Binding var videoEnded: Bool
    @Binding var videoPaused: Bool
    var playRequestTrigger: Int

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let hideScript = WKUserScript(
            source: "document.addEventListener('DOMContentLoaded', function() { " + hideOverlaysScript + " });",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(hideScript)
        let bridgeScript = WKUserScript(
            source: videoBridgeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(bridgeScript)
        let keepVisibleScript = WKUserScript(
            source: keepVideoVisibleScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(keepVisibleScript)
        config.userContentController.add(context.coordinator, name: "videoEnded")
        config.userContentController.add(context.coordinator, name: "videoPaused")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator
        coord.videoEndedBinding = $videoEnded
        coord.videoPausedBinding = $videoPaused
        if replayTrigger != coord.lastReplayTrigger {
            coord.lastReplayTrigger = replayTrigger
            coord.videoEndedBinding?.wrappedValue = false
            coord.videoPausedBinding?.wrappedValue = false
            webView.load(URLRequest(url: url))
        } else if webView.url != url {
            webView.load(URLRequest(url: url))
        }
        if playRequestTrigger != coord.lastPlayRequestTrigger {
            coord.lastPlayRequestTrigger = playRequestTrigger
            webView.evaluateJavaScript(videoRequestPlayScript, completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastReplayTrigger: Int = 0
        var lastPlayRequestTrigger: Int = 0
        var videoEndedBinding: Binding<Bool>?
        var videoPausedBinding: Binding<Bool>?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "videoEnded" {
                DispatchQueue.main.async { [weak self] in
                    self?.videoEndedBinding?.wrappedValue = true
                }
            } else if message.name == "videoPaused" {
                DispatchQueue.main.async { [weak self] in
                    self?.videoPausedBinding?.wrappedValue = true
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(hideOverlaysScript, completionHandler: nil)
            webView.evaluateJavaScript(keepVideoVisibleScript, completionHandler: nil)
            webView.evaluateJavaScript(videoBridgeScript, completionHandler: nil)
            [0.3, 0.7, 1.0, 2.0, 4.0].forEach { delay in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak webView] in
                    guard let w = webView else { return }
                    w.evaluateJavaScript(hideOverlaysScript, completionHandler: nil)
                    w.evaluateJavaScript(keepVideoVisibleScript, completionHandler: nil)
                    w.evaluateJavaScript(videoBridgeScript, completionHandler: nil)
                    w.evaluateJavaScript(videoRequestPlayScript, completionHandler: nil)
                }
            }
        }
    }
}
