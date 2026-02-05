# CleanFeedVK — состояние и дорожная карта

Архив завершённых задач: **PROJECT_STATUS_ARCHIVE.md** (не перечитывать в каждой сессии).

---

## 1. Что уже есть (кратко)

- **Лента:** посты с фото, видео, ссылками, опросами; лайки, комментарии, fullscreen фото/видео; тап по автору → группа/профиль.
- **Профиль:** header (users.get), вкладки Стена / Фото / Друзья / Группы; альбомы, «Сохранённые фото», стена группы.
- **Таббар:** Лента | Друзья | Сообщения (заглушка) | Профиль.
- Детали по завершённым фичам — в PROJECT_STATUS_ARCHIVE.md.

---

## 2. Дорожная карта

**Осталось по плану:**
- **Сообщения** — в последнюю очередь (messages.get, messages.getConversations).

**Улучшения ленты (открытые):**
- **«Добавить в сохранённые»** — передача токена через `initialAccessToken` при открытии галереи (в fullScreenCover getAccessToken при тапе часто пуст).
- **Фото профиля в шапке** — при открытии аватара показывается миниатюра; нужно открывать фото в качестве «главной страницы» (из альбома «Фото профиля») или убрать растянутую миниатюру.

---

## 3. Блокеры и TODO (по приоритету)

**Сделано в последней сессии:**
- **Репосты в ленте:** счётчик репостов (модель `VKPostReposts`, поле `reposts` в `VKPost`); кнопка с Menu «На свою стену» (wall.repost) и «В личку» (заглушка — алерт «Скоро»). ContentView, GroupWallView, ProfileWallTabView: `postRepostOverrides`, `repostInProgress`, `repostToWall()`. API: `VKApiService.wallRepost(token, object: "wall{owner_id}_{post_id}")`, ответ `WallRepostResponse` (success, post_id, reposts_count).
- **«Добавить в сохранённые»:** передача токена через `getAccessToken: (() -> String)?` (в fullScreenCover `authService?.accessToken` был пуст). Колбэк `onAddToSaved: (token, ownerId, photoId, accessKey) async -> Bool`. Все вызовы (ContentView, GroupWallView, ProfileTabsView, AlbumPhotosView, PostCellView) обновлены.
- **Галерея:** вместо `Menu` используется overlay (`showActionsOverlay`) с кнопками «Добавить в сохранённые» и «Закрыть», чтобы избежать _UIReparentingView и поломки иерархии в fullScreenCover.
- **Плеер «Возобновить»:** в скрипт добавлен прямой `document.querySelector('video').play()` и клик по video; скрипт запускается с задержками 0, 0.15, 0.4, 0.8 с; обновление state из WKScriptMessageHandler — через `asyncAfter(0.05)` и `DispatchQueue.main.async` при replay, чтобы убрать «Modifying state during view update».
- **Авторизация:** оставлена исходная логика (load в updateUIView, handleRedirect(url) + cancel). Проблема «не входило» была из‑за блокировки со стороны VK, не кода.

**Требуют проверки / доработки:**

1. **Фото профиля**
   - В шапке и при открытии по тапу — **миниатюра**; при fullscreen видна растянутая картинка. Задача: открывать нормальное фото «главной страницы» (например, из альбома «Фото профиля»).

**План на следующий спринт:**
- **Длинные видео (не рилсы):** тап по видео — вкл/выкл паузу; при появлении рекомендаций тап возвращает к текущему видео (как в рилсах). Сейчас наши кнопки «Пауза/Возобновить» и центральная показываются только для рилсов (URL содержит clip/reel/short); для длинных — только родной плеер VK.

**Бэклог (низкий приоритет):**
- Превью фото в сетке не подгружаются (placeholder в ленте/альбомах; fullscreen ок).

---

## 4. Технические заметки

- **Пагинация ленты:** newsfeed.get(start_from: nextFrom).
- **Лайки/комментарии:** likes.add/delete, wall.getComments, overrides счётчиков; PostCommentsView, thread, «Подгрузить ещё».
- **Видео:** VideoPlayerView (WKWebView), videoBridgeScript, keepVideoVisibleScript, hideOverlaysScript. Рилсы (URL clip/reel/short): наши кнопки «Пауза»/«Возобновить» сверху и центральная; автозапуск при загрузке. Длинные видео: наши кнопки скрыты, только родной плеер VK. Кнопка «Повторить» и «Смотреть снова» — для всех.
- **Опросы:** polls.addVote, PollVoteOverride, ключ `ownerId_postId_pollId`.
- **Фото в fullscreen:** FullScreenPhotoGalleryView — photoIdsForSaving, onAddToSaved, getAccessToken, **initialAccessToken** (передавать при открытии галереи, иначе в fullScreenCover токен пуст); showActionsOverlay, isSavedAlbum (альбом −15 — пункт «Добавить в сохранённые» скрыт). При успехе — тост «Фото добавлено в «Сохранённые»».
- **Альбом «Сохранённые фотографии» (VK):** Системный альбом, при чтении через photos.get задаётся как `album_id = -15` (owner_id = текущий пользователь). Метод **photos.copy** не принимает album_id — он всегда копирует фото в этот системный альбом. Переместить фото «в другой альбом» через API нельзя: можно только скопировать в «Сохранённые» (photos.copy). Если после успешного ответа фото не видно в альбоме — сделать pull-to-refresh в экране «Сохранённые»; при ошибке API показываем «Не удалось сохранить».
- **Репосты:** VKPost.reposts (VKPostReposts: count, user_reposted); PostCellView — счётчик + Menu «На свою стену» / «В личку». wall.repost(object: "wall{owner_id}_{post_id}") → WallRepostResponse; после успеха обновляем postRepostOverrides[postId].
- **OAuth scope:** `wall,offline,friends,photos,groups`; после смены scope — перелогин.
