# Промпт для следующей сессии

Проект: **CleanFeedVK** (iOS 17+, Swift 6, SwiftUI, MVVM).  
Актуальный статус — **PROJECT_STATUS.md**.  
Архив — **PROJECT_STATUS_ARCHIVE.md** (в контекст по умолчанию не тащить).

---

## Резюме работ в прошлой сессии

### Внесённые правки (оставить в коде)

1. **«Добавить в сохранённые» — передача токена**
   - В fullScreenCover у галереи `authService?.accessToken` был пуст → фото не сохранялось.
   - Добавлен параметр **getAccessToken: (() -> String)?** в FullScreenPhotoGalleryView и PostCellView.
   - Колбэк **onAddToSaved** изменён на **(token, ownerId, photoId, accessKey) async -> Bool**; токен передаётся при тапе из замыкания вызывающей стороны.
   - Обновлены: ContentView, GroupWallView, ProfileTabsView, AlbumPhotosView, PostCellView (все передают getAccessToken и addPhotoToSaved(token:ownerId:photoId:accessKey:)).

2. **Галерея — уход от Menu (устранение _UIReparentingView)**
   - Использование **Menu** в fullScreenCover приводило к _UIReparentingView и поломке иерархии, сохранение могло не срабатывать.
   - Вместо Menu: кнопка «три точки» выставляет **showActionsOverlay = true**; показывается overlay с полупрозрачным фоном и карточкой с кнопками «Добавить в сохранённые» и «Закрыть». Логика сохранения та же.

3. **Плеер — кнопка «Возобновить»**
   - В **videoRequestPlayScript** добавлены: прямой вызов `document.querySelector('video').play()` и dispatch клика по video в main frame (помимо postMessage в iframe).
   - Скрипт по «Возобновить» запускается несколько раз с задержками (0, 0.15, 0.4, 0.8 с).
   - Обновление **videoEnded** / **videoPaused** из WKScriptMessageHandler перенесено в **DispatchQueue.main.asyncAfter(0.05)**; сброс при «Повторить» — в **DispatchQueue.main.async**, чтобы избежать «Modifying state during view update».

4. **Авторизация**
   - Оставлена **исходная** логика: load в updateUIView, в decidePolicyFor — handleRedirect(url) + cancel. Проблема «не входило» была из‑за блокировки со стороны VK, не из‑за кода. Вариант с JS/fragment (didFinish + window.location.hash) не используется.

### Что не трогать / не откатывать

- Порядок параметров: в FullScreenPhotoGalleryView **onAddToSaved** объявлен перед **getAccessToken** (и в init, и в вызовах), иначе ошибка сборки «Argument 'onAddToSaved' must precede argument 'getAccessToken'».

---

## Что ещё нужно сделать (перенос в следующую сессию)

**План на спринт:**
1. **Длинные видео (не рилсы):** тап по видео — вкл/выкл паузу; при появлении рекомендаций тап возвращает к текущему видео (как в рилсах). Сейчас наши кнопки показываются только для рилсов (URL содержит clip/reel/short); для длинных — только родной плеер VK.
2. **Фото профиля в шапке** — при открытии аватара показывать нормальное фото (не миниатюру), см. PROJECT_STATUS.

**Проверить:** «Добавить в сохранённые» — после передачи initialAccessToken при открытии галереи токен не должен быть пуст; при ошибке смотреть логи [CleanFeedVK] Gallery.

**Дорожная карта:** Сообщения (messages.get, messages.getConversations) — в последнюю очередь.

**Бэклог:** репосты — счётчик и wall.repost («На свою стену» + «В личку» заглушка) сделаны. Превью фото в сетке.

---

## Технические ориентиры для кода

- **FullScreenPhotoGalleryView:** onAddToSaved, getAccessToken, **initialAccessToken** (обязательно передавать при открытии галереи — в fullScreenCover иначе пустой токен); showActionsOverlay; isSavedAlbum (альбом −15 — пункт скрыт). Не использовать Menu внутри fullScreenCover.
- **VideoPlayerView:** для рилсов (URL clip/reel/short) — наши кнопки «Пауза/Возобновить» и центральная; автозапуск при загрузке. Для длинных видео кнопки скрыты (isReelsLike по URL).
- **AuthView:** load в updateUIView, decidePolicyFor — handleRedirect(url) + decisionHandler(.cancel). Без JS/fragment.
- **VKApiService:** photosCopy(token, ownerId, photoId, accessKey). Альбом «Сохранённые» — photos.get с album_id = -15, при необходимости pull-to-refresh.
