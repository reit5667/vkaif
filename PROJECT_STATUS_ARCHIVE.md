# CleanFeedVK — архив завершённых задач и фич

Файл для контекста: сюда переносятся выполненные пункты из PROJECT_STATUS.md, чтобы не перечитывать их в новых сессиях. Актуальный статус и открытые задачи — в **PROJECT_STATUS.md**.

---

## Инфраструктура

- MVVM, NetworkService (async/await, DI), AppLogger, Auth (OAuth 2.0, Keychain).
- VKApiService: newsfeed.get, wall.get, video.get, likes.add/delete, photos.copy, photos.delete, photos.makeCover, polls.addVote, getFriends, getGroups, photos.getAlbums, photos.get, wall.getComments, photos.getComments, wall.repost, wallDelete, leaveGroup, messages.getConversations, messages.getHistory, messages.send.
- Модели постов, вложений (photo/video/link/doc/poll), profiles/groups. Фильтр (marked_as_ads, promo, blacklist).
- Авторизация: load в updateUIView, handleRedirect + cancel (без JS/fragment).

## Лента

- LazyVStack, ячейка поста (PostCellView), сетка фото (1–10), ссылки (тап → Safari), видео (превью + плеер).
- Ячейки вынесены в отдельные файлы: FeedPostRowCell.swift (лента), ProfileWallPostCell.swift (стена профиля).
- Лайки: счётчики, likes.add/delete (пост и комментарии). Комментарии: wall.getComments, пагинация 5, «Добавить комментарий», ответ, переход по автору, лайк комментария, thread, «Подгрузить ещё».
- Опросы: отображение, голосование polls.addVote, PollVoteOverride.
- Репосты: VKPostReposts, счётчик + Menu «На свою стену» (wall.repost) и «В личку» (заглушка).
- Автообновление ленты при заходе (scenePhase == .active).
- Качество миниатюр: feedPreviewURL приоритет ["x", "w", "z", "y", "m"].
- Превью фото: одно фото 360pt (singlePhotoMaxHeight), несколько по 120pt. Картинка вписана в экран (2.2).
- Ширина постов: postMaxWidth = screenWidth - 64, .clipped() (2.3).
- Текст постов: JustifiedTextView (UIViewRepresentable + UITextView, .justified), sizeThatFits для корректного переноса строк (2.1).
- Выравнивание постов по центру.
- Удаление поста: wallDelete, меню «три точки» у своих постов.
- Закрепить/открепить пост на своей стене.

## Fullscreen фото (1.1–1.6)

- Zoom: двойной тап (1x ↔ 2.5x), pinch (MagnificationGesture) 1x–4x. Zoom в точку тапа (1.1).
- Свайп вниз для выхода (simultaneousGesture).
- Листание, лайк, комментарии (sheet), стрелки перелистывания.
- Иконки без подписей; «Поделиться» share sheet; только стрелочка (1.2–1.4).
- Выравнивание лайк/комменты/поделиться (1.5).
- Счётчики лайков/комментов/репостов под иконками (1.6).
- Кнопка Репостов: реализован wall.repost из галереи поста (repostObject, onRepostSuccess, обновление счётчика в ленте/профиле/стене группы). При открытии из альбома/чата — кнопка неактивна.
- Двойной тап: только zoom in (сворачивание при scale > 1 отключено). Пан при scale > 1 — simultaneousGesture, чтобы при scale == 1 горизонтальный свайп листал фото (TabView).
- Кнопка закрытия: xmark.circle.fill 36pt, область 56×56. Кнопка «три точки» увеличена до того же размера.
- Меню «три точки»: «Добавить в сохранённые» (photosCopy через vkApi), «Скачать на устройство» (PHPhotoLibrary), «Удалить» для своих фото, «Сделать фото профиля» (photos.makeCover, albumId -6).
- Overlay showActionsOverlay вместо Menu (избежание _UIReparentingView).
- Известная проблема: токен в fullScreenCover может быть пуст при «Сделать фото профиля».

## Профиль и навигация

- users.get, аватар, имя, статус; вкладки Стена / Фото / Друзья / Группы.
- Переход из ленты на группу/профиль (тап по автору).
- Друзья: friends.get (count=5000), заявки, возможные друзья, переход в профиль, поиск по имени.
- Группы: список в профиле (цикл offset), поиск по названию, тап → GroupWallView, «Отписаться» (groups.leave), автообновление списка после отписки.
- Стена: LazyVStack(spacing: 12), отступы, .clipped(). Удалить пост/фото, закрепить/открепить.
- Скролл: стена, группы, друзья — header и контент в одном ScrollView (embeddedInScroll, LazyVStack вместо List) (3.3–3.4).

## Альбомы

- photos.getAlbums, photos.get по 50, подгрузка при скролле.
- Альбом «Сохранённые фото», «Фото профиля», сортировка по дате.
- Fullscreen с лайком и комментариями (photos.getComments), первый тап открывает нужное фото.
- Удаление фото из альбомов (photosDelete, обновление списка, закрытие галереи).
- «Сделать фото профиля»: photosMakeCover, albumId -6, тосты успеха/ошибки.

## Видеоплеер

- VideoPlayerView: VideoWebView, videoBridgeScript, keepVideoVisibleScript, hideOverlaysScript.
- Кнопки «Возобновить» / «Повторить»; скрипт с задержками; state из WKScriptMessageHandler.

## Сообщения (частично)

- Список диалогов (getConversations) с пагинацией.
- Чат (getHistory, send), пагинация старых сообщений, отправка фото.
- Декод getHistory: VKMessage с decodeIfPresent для from_id/peer_id/date; FailableDecode для items (4.5).
- Автоскролл вниз при открытии диалога.
- Подгрузка старых: totalCount при пустом ответе.
- 4.1. Ошибка загрузки фото в диалог: OwnerPhotoUploadResult.init — decodeIfPresent(String) бросал typeMismatch при Int-значении server; исправлено на try?. Выделен uploadMessagesPhotoToServer с HTTP-проверкой и логированием.
- 4.2 (частично): contextMenu по long press — Ответить, Скопировать, Переслать (стаб), Закрепить/Открепить только для бесед (peer_id ≥ 2e9), Удалить (свои). Pinned banner, reply preview (VKReplyMessage). Кнопка «+» с sheet для вложений, кнопка отправки крупнее.
- Фото в сообщениях: VKMessage.attachments ([VKAttachment]), thumbnail в пузырьке (messagePhotoGrid), тап → FullScreenPhotoGalleryView (сохранённые, закрытие).
- Скролл чата: добавлен defaultScrollAnchor(.bottom); по отзыву пользователя при заходе всё ещё открывается посередине — задача 4.2b в статусе.

## Fullscreen 2.1 (пан при зуме)

- При увеличении изображения в fullscreen движения панят по картинке (просмотр деталей), а не листают изображения в посте. Реализовано: в FullScreenImageView при scale > 1 добавлены panOffset и DragGesture (с ограничением по области); опциональный onScaleChange для галереи; в FullScreenPhotoGalleryView при currentPageZoomScale > 1 листание TabView блокируется через highPriorityGesture(DragGesture).

## Профиль 3.2 (полное фото в шапке)

- Шапка профиля: главное фото из альбома «Фото профиля» (photos.get, album_id=-6) в полном размере, не миниатюра из users.get. VKApiService.getProfileMainPhoto, ProfileViewModel.profileMainPhoto, отображение в виде широкого блока с закруглёнными нижними углами (240pt). По тапу — FullScreenPhotoGalleryView (лайки, комментарии, меню), как при открытии фото из ленты.

## Сообщения 4.2, 4.2b, 4.3

- 4.2. Закрепление: для личных диалогов не реализуется (VK API messages.pin только для бесед); пункт в contextMenu показывается при peer_id ≥ 2e9.
- 4.2b. Скролл к последнему сообщению при заходе в диалог: scrollToBottomOnEnter (два отложенных scrollTo) + defaultScrollAnchor(.bottom).
- 4.3. Материалы диалога: вкладки Фото | Видео | Поиск. Пагинация по сообщениям: первая загрузка 200, подгрузка по 150. Поиск — messages.search. Кнопка в шапке чата открывает sheet DialogMaterialsView.

## Остаётся (не в приоритете)

- 4.4. Отображение репостов, стикеров и других сущностей в сообщениях.

---

## Ссылки на код (для справки)

- PostCellView: linkRow, pollRow, videoRow, photoGridView, bodyText (JustifiedTextView); FeedDestination, pollVoteOverrides.
- FullScreenPhotoGalleryView / FullScreenImageView: photoIdsForSaving, vkApi, postCommentsContext, photoCommentsContext, bottomBar.
- VideoPlayerView: VideoWebView, videoBridgeScript.
- VKApiService: все методы выше.
- ProfileTabsView: ProfileWallTabView, ProfileFriendsTabView, ProfileGroupsTabView (embeddedInScroll).
- ChatView: messagesList, loadHistory, loadMoreHistory, scrollToBottom, messageRow (reply preview, messagePhotoGrid), contextMenu, pinnedBanner, attachMenu, fullScreenCover FullScreenPhotoGalleryView.
