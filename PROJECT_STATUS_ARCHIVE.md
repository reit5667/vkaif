# CleanFeedVK — архив завершённых задач и фич

Файл для контекста: сюда переносятся выполненные пункты из PROJECT_STATUS.md, чтобы не перечитывать их в новых сессиях. Актуальный статус и открытые задачи — в **PROJECT_STATUS.md**.

---

## Завершённые блоки (кратко)

**Инфраструктура и лента**
- Структура MVVM, NetworkService (async/await, DI), AppLogger, Auth (OAuth 2.0, Keychain).
- VKApiService: newsfeed.get, пагинация; модели постов, вложений (photo/video/link/doc), profiles/groups.
- Фильтр (marked_as_ads, promo, blacklist). Лента: LazyVStack, ячейка поста, сетка фото (1–10), ссылки (тап → Safari).

**Профиль и навигация**
- Профиль: users.get, аватар, имя, статус; вкладки Стена / Фото / Друзья / Группы; TabView Лента | Друзья | Сообщения | Профиль.
- Переход из ленты на группу/профиль (тап по автору). Друзья: friends.get, заявки, возможные друзья, переход в профиль. Группы: страница группы из ленты, список групп в профиле (цикл offset), тап → GroupWallView.

**Альбомы**
- photos.getAlbums, photos.get по 50, подгрузка при скролле, альбом «Сохранённые фото», «Фото профиля», сортировка по дате, fullscreen с лайком и комментариями (photos.getComments), первый тап открывает нужное фото, spacer для скролла после подгрузки.

**Лента: медиа и действия**
- Fullscreen фото: листание, лайк, комментарии (sheet), стрелки перелистывания, меню 3 точки.
- Лайки: счётчики, likes.add/delete (пост и комментарии). Комментарии: wall.getComments, пагинация 5, «Добавить комментарий», ответ, переход по автору, лайк комментария, thread, «Подгрузить ещё» при >5.
- Опросы: отображение (вопрос, варианты, голоса), голосование polls.addVote в ленте, PollVoteOverride после голоса.
- Ссылки в ленте: отображение, тап → Safari.

**Прочее**
- Группы: без filter, цикл offset; кликабельные группы в профиле. Друзья count=5000. Комментарии из fullscreen поверх галереи, «Назад» возвращает на картинку.

**Репосты и операции в ленте (апрув)**
- Репосты: модель VKPostReposts, поле reposts в VKPost; счётчик + Menu «На свою стену» (wall.repost) и «В личку» (заглушка). ContentView, GroupWallView, ProfileWallTabView: postRepostOverrides, repostInProgress, repostToWall(). VKApiService.wallRepost(token, object: "wall{owner_id}_{post_id}").
- «Добавить в сохранённые»: getAccessToken в fullScreenCover, onAddToSaved(token, ownerId, photoId, accessKey) async -> Bool; все вызовы обновлены.
- Галерея: overlay showActionsOverlay вместо Menu (избежание _UIReparentingView).
- Плеер «Возобновить»: document.querySelector('video').play() и клик по video; скрипт с задержками; state из WKScriptMessageHandler через asyncAfter(0.05) / DispatchQueue.main.async при replay.
- Авторизация: load в updateUIView, handleRedirect + cancel (без JS/fragment).

---

## Ссылки на код (для справки)

- PostCellView: linkRow, pollRow, videoRow, photoGridView; FeedDestination, pollVoteOverrides, onPollVote.
- FullScreenPhotoGalleryView: photoIdsForSaving, onAddToSaved, postCommentsContext, photoCommentsContext.
- VideoPlayerView: VideoWebView, videoBridgeScript, keepVideoVisibleScript, hideOverlaysScript; кнопки в шапке (Возобновить, Повторить).
- VKApiService: newsfeed.get, wall.get, video.get, likes.add/delete, photos.copy, polls.addVote, getFriends, getGroups, photos.getAlbums, photos.get, wall.getComments, photos.getComments.

**Удаление поста и фото, меню поста (апрув)**
- Удаление поста: VKApiService.wallDelete(owner_id, post_id). Меню «три точки» в шапке ячейки поста (ellipsis.circle): пункт «Удалить» только для своих постов (owner_id == currentUserId). Лента (ContentView): currentUserId через getUsers при loadFeed, deletePost(), пост убирается из feedPosts. Стена профиля: ProfileViewModel.removeWallPost, ProfileWallTabView isOwnProfile + onDeletePost, PostCellView canDeletePost/onDelete/deleteInProgress.
- Ячейки вынесены в отдельные файлы из-за ограничений компилятора Swift на сложные инициализаторы: FeedPostRowCell.swift (лента), ProfileWallPostCell.swift (стена профиля); типизированные локальные переменные для замыканий и явные приведения nil где нужно.
- Удаление фото: VKApiService.photosDelete. В fullscreen галерее для своих фото (isOwnPhotos/canDeletePost): пункт «Удалить» в меню «три точки»; «Добавить в сохранённые» показывается только для чужих фото (для своих скрыто). PostCellView: onDeletePhoto, fullScreenGalleryView(initialIndex:) с типизированными опционалами.

**Отступы на стене и «Сделать фото профиля» (апрув)**
- Стена: LazyVStack(spacing: 12) в ProfileTabsView (стена профиля) и GroupWallView (стена группы) — посты не накладываются.
- Сделать фото профиля: VKApiService.photosMakeCover(owner_id, photo_id). В FullScreenPhotoGalleryView добавлены isProfileAlbum, onMakeProfilePhoto; пункт «Сделать фото профиля» в меню «три точки» только для своих фото в альбоме «Фото профиля» (-6). AlbumDestination + isOwnProfile; ProfilePhotoTabView isOwnProfile; AlbumPhotosView передаёт в галерею onMakeProfilePhoto при isOwnProfile && albumId == -6.

**Сессия: отступы стены, миниатюры фото, photos.makeCover (частично)**
- Отступы стены: LazyVStack(spacing: 12), padding 12; отказ от List (краш recursive layout). Фикс наложения: .frame(maxWidth), .background, .clipped(). Расстояние между постами регулируется (spacing + padding в ProfileTabsView).
- Превью фото: фиксированная высота — одно фото 360pt (singlePhotoMaxHeight), несколько по 120pt; убрано minHeight, чтобы длинные картинки не заезжали на лайки/след. пост. Иконка меню поста: ellipsis.circle → ellipsis, .symbolRenderingMode(.monochrome).
- photos.makeCover: в API добавлен album_id (VK требует), везде передаём -6. Callback «Сделать фото профиля» возвращает (Bool, String?) — тост с текстом ошибки VK. FullScreenImageView: тосты «Фото установлено…» / «Не удалось…» или текст ошибки; при пустом токене — «Войдите в аккаунт снова». В requestVK при ошибке декода логируется body ответа. ProfileWallPostCell: передача onMakeProfilePhoto в PostCellView напрямую (без environment) из-за сбоя компилятора; явные приведения nil для типа ((String, Int, Int) async -> (Bool, String?))? в ProfileWallPostCell и PostCellView.
- Известная проблема: в fullScreenCover при нажатии «Сделать фото профиля» токен приходит пустой («Нет токена доступа»); приоритет токена при тапе: getAccessToken?() ?? authService?.accessToken ?? capturedTokenForSave — не решено, продолжать в след. сессии.

**«Добавить в сохранённые», «Скачать на устройство», удаление фото из альбомов (апрув)**
- «Добавить в сохранённые»: отказ от closure с параметрами (EXC_BAD_ACCESS в fullScreenCover). Галерея получает vkApi: VKApiService? и сама вызывает photosCopy(token, ownerId, photoId, accessKey) по тапу; токен снимается на main из getAccessToken/authService/initialAccessToken. Родители (лента, профиль, группа, альбом) передают только vkApi. TECHNICAL_NOTES: подход без closure, accessKey как String = "", PhotosCopyResponse с init(from:) под число и объект.
- «Скачать на устройство»: saveImageToPhotoLibrary на @MainActor; в Target → Info нужен NSPhotoLibraryAddUsageDescription.
- Удаление фото из альбомов: в AlbumPhotosView для своих альбомов (isOwnProfile) передаётся onDeletePhoto; deletePhotoFromAlbum вызывает photosDelete, при успехе удаляет фото из photos и закрывает галерею. При пустом токене из галереи используется authService.accessToken в deletePhotoFromAlbum. Создание галереи вынесено в albumGalleryView(urls:item:) с явными типами и без тернарника с async-closure в одном выражении (избежание «ambiguous without a type annotation»).
