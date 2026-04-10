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

/// Полноэкранный плеер VK по URL. Закрытие — кнопка. Снизу лайки и комментарии; реплей по центру после окончания.
/// Одна кнопка «Пауза» / «Возобновить»: при воспроизведении — пауза (video.pause()), при паузе — возобновление (video.play()).
/// Ограничение: при паузе через интерфейс VK может показываться «следующее видео»; наша кнопка «Пауза» ставит на паузу без переключения.
struct VideoPlayerView: View {
    let url: URL
    let onDismiss: () -> Void
    /// Если задан — показывается панель с лайками и комментариями (как под фото).
    var postContext: VideoPlayerPostContext? = nil

    @State private var replayTrigger = 0
    @State private var videoEnded = false
    /// true = видео на паузе (показываем «Возобновить»).
    @State private var videoPaused = false
    /// Инкремент при тапе «Возобновить» — один вызов video.play().
    @State private var playRequestTrigger = 0
    /// Инкремент при тапе «Пауза» — один вызов video.pause() (без переключения на «следующее видео» VK).
    @State private var pauseRequestTrigger = 0
    /// Контролы (кнопки) видимы или скрыты.
    @State private var controlsVisible = true
    /// Инкремент отменяет предыдущий delayed-hide.
    @State private var controlsHideGeneration = 0

    /// Показать контролы; если видео играет — автоскрыть через 3 с.
    private func showControls() {
        controlsHideGeneration += 1
        let gen = controlsHideGeneration
        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = true }
        guard !videoPaused && !videoEnded else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard controlsHideGeneration == gen else { return }
            withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = false }
        }
    }

    /// Скрыть контролы немедленно (тап, когда они уже видимы).
    private func hideControls() {
        controlsHideGeneration += 1
        withAnimation(.easeInOut(duration: 0.25)) { controlsVisible = false }
    }

    /// Рилсы (короткие видео): наши кнопки работают. Длинные видео: только родной плеер VK, наши кнопки скрыты.
    private var isReelsLike: Bool {
        let lower = url.absoluteString.lowercased()
        return lower.contains("clip") || lower.contains("reel") || lower.contains("short")
    }

    var body: some View {
        ZStack(alignment: .top) {
            VideoWebView(
                url: url,
                replayTrigger: replayTrigger,
                videoEnded: $videoEnded,
                videoPaused: $videoPaused,
                playRequestTrigger: playRequestTrigger,
                pauseRequestTrigger: pauseRequestTrigger,
                onTap: { if controlsVisible { hideControls() } else { showControls() } }
            )
            .ignoresSafeArea()

            // Авто-скрываемые контролы: пауза/повтор (рилсы), центральная кнопка, лайки/комментарии.
            VStack {
                HStack(spacing: 16) {
                    Spacer(minLength: 44) // место под крестик
                    if isReelsLike {
                        Button(action: {
                            if videoPaused {
                                playRequestTrigger += 1
                                videoPaused = false
                            } else {
                                pauseRequestTrigger += 1
                                videoPaused = true
                            }
                        }) {
                            Label(
                                videoPaused ? "Возобновить" : "Пауза",
                                systemImage: videoPaused ? "play.circle.fill" : "pause.circle.fill"
                            )
                            .font(.title3)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
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

                if isReelsLike {
                    Button {
                        if videoPaused {
                            playRequestTrigger += 1
                            videoPaused = false
                        } else {
                            pauseRequestTrigger += 1
                            videoPaused = true
                        }
                    } label: {
                        Image(systemName: videoPaused ? "play.circle.fill" : "pause.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 80, height: 80)
                    .contentShape(Circle())
                    .zIndex(0.5)
                }

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
            .opacity(controlsVisible || videoPaused || videoEnded ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: controlsVisible)
            .allowsHitTesting(controlsVisible || videoPaused || videoEnded)

            // Кнопка закрытия — всегда видима поверх плеера.
            VStack {
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
                    }
                    Spacer()
                }
                .padding(16)
                Spacer()
            }
        }
        .onAppear { showControls() }
        .onChange(of: videoPaused) { isPaused in
            if isPaused { cancelAutoHide() } else { showControls() }
        }
        .onChange(of: videoEnded) { ended in
            if ended { cancelAutoHide() }
        }
    }

    /// Отменяет отложенное скрытие и оставляет контролы видимыми (пауза / конец видео).
    private func cancelAutoHide() {
        controlsHideGeneration += 1
        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = true }
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
/// MutationObserver следит за изменениями DOM и скрывает рекомендации как только они появляются (в том числе после окончания видео).
/// Дополнительно инжектирует CSS для скрытия VK-классов end-screen через таблицу стилей (надёжнее, чем inline style).
private let hideOverlaysScript = """
(function() {
    // CSS-инъекция: скрываем известные VK-классы end-screen/рекомендаций через <style>
    function injectCSS() {
        if (document.getElementById('cfvk-hide')) return;
        var s = document.createElement('style');
        s.id = 'cfvk-hide';
        s.textContent = [
            '[class*="vp_series"]','[class*="series_ep"]','[class*="ep_switch"]',
            '[class*="next_video"]','[class*="nextVideo"]','[class*="next-video"]',
            '[class*="rec_video"]','[class*="recVideo"]',
            '[class*="end_screen"]','[class*="endScreen"]','[class*="endscreen"]',
            '[class*="related_video"]','[class*="relatedVideo"]',
            '[class*="autoplay_next"]','[class*="autoplayNext"]',
            '.mv_rel_video_wrap','.videoplayer_end','.vp_end','.vp_overlay_end'
        ].join(',') + '{ display:none!important; }';
        (document.head || document.documentElement).appendChild(s);
    }
    injectCSS();
    var sel = '[class*="recommend"],[class*="Recommend"],[id*="recommend"],[class*="related"],[class*="Related"],[class*="suggest"],[class*="next-video"],[class*="NextVideo"],[class*="autoplay"],[class*="Autoplay"],[data-class*="recommend"],[data-class*="related"]';
    var hideKeywords = ['следующ','начнётся через','next video','стало известно','смотрите также','похожие видео','вам может понравиться','эпизод','история вселенной','история и геймдизайн','полная версия'];
    function containsVideo(el) { return el && (el.tagName === 'VIDEO' || (el.querySelector && el.querySelector('video'))); }
    function hide() {
        injectCSS();
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
    setTimeout(hide, 1500);
    setTimeout(hide, 3000);
    if (typeof MutationObserver !== 'undefined') {
        var observer = new MutationObserver(function(mutations) {
            var hasNew = false;
            mutations.forEach(function(m) { if (m.addedNodes.length > 0) hasNew = true; });
            if (hasNew) hide();
        });
        var root = document.body || document.documentElement;
        if (root) observer.observe(root, { childList: true, subtree: true });
        else document.addEventListener('DOMContentLoaded', function() {
            observer.observe(document.body || document.documentElement, { childList: true, subtree: true });
        });
    }
})();
"""

/// Держим video и контейнеры видимыми при загрузке (чтобы не было чёрного экрана). Запуск 3 раз без setInterval — не ломаем контролы обычного плеера.
private let keepVideoVisibleScript = """
(function() {
    function keepVisible() {
        document.querySelectorAll('video').forEach(function(v) {
            v.style.setProperty('opacity', '1', 'important');
            v.style.setProperty('visibility', 'visible', 'important');
            var p = v.parentElement;
            for (var i = 0; i < 5 && p; i++) {
                p.style.setProperty('opacity', '1', 'important');
                p.style.setProperty('visibility', 'visible', 'important');
                p = p.parentElement;
            }
        });
    }
    keepVisible();
    setTimeout(keepVisible, 1000);
    setTimeout(keepVisible, 2500);
})();
"""

/// Единый скрипт для всех фреймов (в т.ч. iframe плеера VK): детект ended/pause, postMessage в main frame, приём requestPlay для воспроизведения.
/// Инжектируется как user script с forMainFrameOnly: false, чтобы срабатывал и внутри iframe с видео.
/// ВАЖНО: запоминаем ПЕРВЫЙ найденный video-элемент (originalVideo) и не переключаемся на превью рекомендаций,
/// которые VK добавляет в DOM после окончания основного видео.
private let videoBridgeScript = """
(function() {
    var originalVideo = null;
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
    function postPlaying() {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.videoPlaying)
            window.webkit.messageHandlers.videoPlaying.postMessage('playing');
        else
            window.parent.postMessage({ type: 'videoPlaying' }, '*');
    }
    window.addEventListener('message', function(e) {
        if (e.data && e.data.type === 'videoEnded' && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.videoEnded)
            window.webkit.messageHandlers.videoEnded.postMessage('ended');
        if (e.data && e.data.type === 'videoPaused' && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.videoPaused)
            window.webkit.messageHandlers.videoPaused.postMessage('paused');
        if (e.data && e.data.type === 'videoPlaying' && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.videoPlaying)
            window.webkit.messageHandlers.videoPlaying.postMessage('playing');
        if (e.data && e.data.type === 'requestPlay') {
            var v = originalVideo || document.querySelector('video');
            if (v) v.play();
        }
        if (e.data && e.data.type === 'requestPause') {
            var v = originalVideo || document.querySelector('video');
            if (v) v.pause();
        }
    });
    function setupVideo(v) {
        if (!v || v.dataset.videoBridge) return;
        if (!originalVideo) originalVideo = v;
        v.dataset.videoBridge = '1';
        v.addEventListener('ended', postEnded);
        v.addEventListener('pause', postPaused);
        v.addEventListener('play', postPlaying);
    }
    function setup() {
        var v = document.querySelector('video');
        setupVideo(v);
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', setup);
    else setup();
    [500, 1000, 2000, 4000].forEach(function(ms) { setTimeout(setup, ms); });
    setInterval(function() {
        var v = originalVideo || document.querySelector('video');
        if (v && v.ended && !v.dataset.reportedEnd) { v.dataset.reportedEnd = '1'; postEnded(); }
    }, 500);
})();
"""

/// Запрос воспроизведения из Swift (кнопка «Возобновить»): postMessage во все фреймы + video.play() в main frame (один вызов).
private let videoRequestPlayScript = """
(function() {
    var msg = { type: 'requestPlay' };
    try { window.postMessage(msg, '*'); } catch (e) {}
    var iframes = document.querySelectorAll('iframe');
    for (var i = 0; i < iframes.length; i++) {
        try {
            if (iframes[i].contentWindow) iframes[i].contentWindow.postMessage(msg, '*');
        } catch (e) {}
    }
    var v = document.querySelector('video');
    if (v) v.play().catch(function() {});
})();
"""

/// Запрос паузы из Swift (кнопка «Пауза»): postMessage во все фреймы + video.pause() в main frame. Не триггерит «следующее видео» VK.
private let videoRequestPauseScript = """
(function() {
    var msg = { type: 'requestPause' };
    try { window.postMessage(msg, '*'); } catch (e) {}
    var iframes = document.querySelectorAll('iframe');
    for (var i = 0; i < iframes.length; i++) {
        try {
            if (iframes[i].contentWindow) iframes[i].contentWindow.postMessage(msg, '*');
        } catch (e) {}
    }
    var v = document.querySelector('video');
    if (v) v.pause();
})();
"""

private struct VideoWebView: UIViewRepresentable {
    let url: URL
    var replayTrigger: Int
    @Binding var videoEnded: Bool
    @Binding var videoPaused: Bool
    var playRequestTrigger: Int
    var pauseRequestTrigger: Int
    var onTap: () -> Void

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
        config.userContentController.add(context.coordinator, name: "videoPlaying")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        // Жест тапа с cancelsTouchesInView = false: WKWebView получает тап (VK-плеер работает),
        // и мы одновременно переключаем видимость контролов.
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.cancelsTouchesInView = false
        webView.addGestureRecognizer(tap)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator
        coord.videoEndedBinding = $videoEnded
        coord.videoPausedBinding = $videoPaused
        coord.onTap = onTap
        if replayTrigger != coord.lastReplayTrigger {
            coord.lastReplayTrigger = replayTrigger
            DispatchQueue.main.async {
                coord.videoEndedBinding?.wrappedValue = false
                coord.videoPausedBinding?.wrappedValue = false
            }
            webView.load(URLRequest(url: url))
        } else if webView.url != url {
            webView.load(URLRequest(url: url))
        }
        if playRequestTrigger != coord.lastPlayRequestTrigger {
            coord.lastPlayRequestTrigger = playRequestTrigger
            webView.evaluateJavaScript(videoRequestPlayScript, completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak webView] in
                webView?.evaluateJavaScript(videoRequestPlayScript, completionHandler: nil)
            }
        }
        if pauseRequestTrigger != coord.lastPauseRequestTrigger {
            coord.lastPauseRequestTrigger = pauseRequestTrigger
            webView.evaluateJavaScript(videoRequestPauseScript, completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak webView] in
                webView?.evaluateJavaScript(videoRequestPauseScript, completionHandler: nil)
            }
        }
        if videoEnded != coord.lastVideoEnded {
            coord.lastVideoEnded = videoEnded
            if videoEnded {
                // Видео закончилось: прогоняем скрипт скрытия рекомендаций несколько раз,
                // пока VK динамически добавляет блоки в DOM.
                [0.0, 0.4, 1.0, 2.0].forEach { delay in
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak webView] in
                        webView?.evaluateJavaScript(hideOverlaysScript, completionHandler: nil)
                    }
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastReplayTrigger: Int = 0
        var lastPlayRequestTrigger: Int = 0
        var lastPauseRequestTrigger: Int = 0
        var lastVideoEnded: Bool = false
        var videoEndedBinding: Binding<Bool>?
        var videoPausedBinding: Binding<Bool>?
        var onTap: (() -> Void)?

        @objc func handleTap() { onTap?() }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "videoEnded" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.videoEndedBinding?.wrappedValue = true
                }
            } else if message.name == "videoPaused" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.videoPausedBinding?.wrappedValue = true
                }
            } else if message.name == "videoPlaying" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.videoPausedBinding?.wrappedValue = false
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
                }
            }
            // Автозапуск: без этого рилсы и длинные видео открываются в паузе.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak webView] in
                webView?.evaluateJavaScript(videoRequestPlayScript, completionHandler: nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak webView] in
                webView?.evaluateJavaScript(videoRequestPlayScript, completionHandler: nil)
            }
        }
    }
}
