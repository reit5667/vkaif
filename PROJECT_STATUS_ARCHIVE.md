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

---

## Ссылки на код (для справки)

- PostCellView: linkRow, pollRow, videoRow, photoGridView; FeedDestination, pollVoteOverrides, onPollVote.
- FullScreenPhotoGalleryView: photoIdsForSaving, onAddToSaved, postCommentsContext, photoCommentsContext.
- VideoPlayerView: VideoWebView, videoBridgeScript, keepVideoVisibleScript, hideOverlaysScript; кнопки в шапке (Возобновить, Повторить).
- VKApiService: newsfeed.get, wall.get, video.get, likes.add/delete, photos.copy, polls.addVote, getFriends, getGroups, photos.getAlbums, photos.get, wall.getComments, photos.getComments.
