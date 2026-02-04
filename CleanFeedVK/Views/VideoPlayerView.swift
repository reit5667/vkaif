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

/// Полноэкранный плеер VK по URL. Закрытие — кнопка. Снизу только лайки и комментарии; реплей по центру — только после окончания видео.
struct VideoPlayerView: View {
    let url: URL
    let onDismiss: () -> Void
    /// Если задан — показывается панель с лайками и комментариями (как под фото).
    var postContext: VideoPlayerPostContext? = nil

    @State private var replayTrigger = 0
    @State private var videoEnded = false

    var body: some View {
        ZStack(alignment: .top) {
            VideoWebView(url: url, replayTrigger: replayTrigger, videoEnded: $videoEnded)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)

                Spacer(minLength: 0)

                if videoEnded {
                    Button(action: {
                        videoEnded = false
                        replayTrigger += 1
                    }) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// Скрипт скрывает блоки рекомендаций при паузе (карточки «Эпизод», «История вселенной» и т.п.), таймер, «следующее видео».
private let hideOverlaysScript = """
(function() {
    var sel = '[class*="recommend"],[class*="Recommend"],[id*="recommend"],[class*="related"],[class*="Related"],[class*="suggest"],[class*="next-video"],[class*="NextVideo"],[class*="countdown"],[class*="Countdown"],[class*="autoplay"],[class*="Autoplay"],[class*="VideoCard"],[class*="video-card"],[class*="vkui"],[class*="Vkui"],[data-class*="recommend"],[data-class*="related"]';
    var hideKeywords = ['следующ','начнётся через','next video','эпизод','история вселенной','история и геймдизайн','полная версия'];
    function hide() {
        document.querySelectorAll(sel).forEach(function(el) { el.style.setProperty('display', 'none', 'important'); });
        document.querySelectorAll('*').forEach(function(el) {
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

/// Детект окончания видео: addEventListener('ended') + опрос video.ended (на случай iframe/другого контекста).
private let videoEndedScript = """
(function() {
    function postEnded() {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.videoEnded) {
            window.webkit.messageHandlers.videoEnded.postMessage('ended');
        }
    }
    function setupListener(v) {
        if (!v || v.dataset.endedListener) return;
        v.dataset.endedListener = '1';
        v.addEventListener('ended', postEnded);
    }
    function setup() {
        var v = document.querySelector('video');
        setupListener(v);
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', setup);
    else setup();
    [500, 1000, 2000, 4000].forEach(function(ms) { setTimeout(setup, ms); });
    setInterval(function() {
        var v = document.querySelector('video');
        if (v && v.ended && !v.dataset.reportedEnd) {
            v.dataset.reportedEnd = '1';
            postEnded();
        }
    }, 500);
})();
"""

private struct VideoWebView: UIViewRepresentable {
    let url: URL
    var replayTrigger: Int
    @Binding var videoEnded: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let script = WKUserScript(
            source: "document.addEventListener('DOMContentLoaded', function() { " + hideOverlaysScript + " });",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(script)
        config.userContentController.add(context.coordinator, name: "videoEnded")
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
        if replayTrigger != coord.lastReplayTrigger {
            coord.lastReplayTrigger = replayTrigger
            coord.videoEndedBinding?.wrappedValue = false
            webView.load(URLRequest(url: url))
        } else if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastReplayTrigger: Int = 0
        var videoEndedBinding: Binding<Bool>?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "videoEnded" {
                DispatchQueue.main.async { [weak self] in
                    self?.videoEndedBinding?.wrappedValue = true
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(hideOverlaysScript, completionHandler: nil)
            webView.evaluateJavaScript(videoEndedScript, completionHandler: nil)
            for delay in [0.5, 1.0, 2.0, 4.0] as [Double] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    webView.evaluateJavaScript(hideOverlaysScript, completionHandler: nil)
                    webView.evaluateJavaScript(videoEndedScript, completionHandler: nil)
                }
            }
        }
    }
}
