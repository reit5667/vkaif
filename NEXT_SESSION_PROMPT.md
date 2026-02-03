# Промпт для следующей сессии

Проект: **CleanFeedVK** (iOS 17+, Swift 6, SwiftUI, MVVM). Спека и дорожная карта — **PROJECT_STATUS.md** в корне.

---

## Что сделано в прошлом диалоге

### Лайки
- **VKApiService:** `likes.add`, `likes.delete` (type=post/comment). Ответ VK: число или `{"likes": N}` — декодирование через `VKLikesAddResponse`.
- **Модели:** `VKPostLikes.userLikes`, `VKCommentLikes.userLikes` (0/1).
- **Пост:** PostCellView — `likesCountOverride`, `isLikedOverride`, `onLike`, `likeInProgress`; кнопка лайка (toggle). ContentView/GroupWallView: `likeToggle(post)`, `postLikeOverrides`, `postLikedOverrides`.
- **Комментарий:** PostCommentsView — toggle лайка комментария (likes.add / likes.delete), `commentLikeOverrides`, `commentLikedOverrides`.

### Комментарии
- Кнопка комментариев на **всех** постах (в т.ч. при 0 комментариев).
- **«Добавить комментарий»** — корневой (wall.createComment без reply_to); **ответ** — wall.createComment(reply_to_comment: id). Модель ответа: `VKWallCreateCommentResponse` (comment_id).
- **AddCommentTarget:** .root / .reply(VKComment); один sheet для корня и ответа.
- Тап по **имени автора** комментария → профиль/группа: programmatic navigation (`authorDestination: CommentAuthorDestination?`, Button вместо NavigationLink(value:)), чтобы не открывался профиль при «Ответить»/«Отправить».
- **Thread:** VKComment.thread (VKCommentThread: count, items); отображение `thread?.items` под комментарием; getWallComments с `thread_items_count=10`.
- **«Подгрузить ещё»:** при append и 0 записей с API — `noMoreTopLevel = true`, кнопка скрывается.

### Профиль (попытки починить вкладки — не помогло)
- **ProfileViewModel:** `loadAlbums(ownerId: Int?, forceRefresh:)` — явный ownerId после loadUserOnce; в loadProfileIfNeeded/refreshAll передаётся `user?.id ?? userId`.
- **ContentView:** один `@StateObject profileViewModel` (init создаёт auth + ProfileViewModel(authService: auth, userId: nil)); таб «Профиль» — `ProfileView(authService: authService, viewModel: profileViewModel)`.
- **ProfileView:** только `init(authService: AuthService, viewModel: ProfileViewModel)`; `@ObservedObject var viewModel` (обязательный), чтобы SwiftUI подписывался на @Published.
- **ProfileViewWrapper(authService: AuthService, userId: Int?):** для профиля друга — внутри `@StateObject viewModel = ProfileViewModel(authService, userId:)`, рендер `ProfileView(authService, viewModel: viewModel)`. Вызовы: лента → пользователь, друзья → друг, комментарии → автор — везде ProfileViewWrapper(authService, userId: id).
- **ProfileView:** `tabContentId` (.id на контенте вкладки), `loadTabIfNeeded` при onChange(selectedTab).
- **Итог:** API возвращает friends (50), groups (22); в UI списки по-прежнему пустые. Причина не найдена.

---

## Текущее состояние (кратко)

- **Лента:** auth, newsfeed.get, фильтр, подгрузка, ячейка (заголовок → группа/профиль, текст, фото 1–10, лайк toggle, комментарии). Фото → fullscreen. Тап по автору → GroupWallView / ProfileViewWrapper(userId).
- **Профиль:** users.get, аватар, имя, статус. Вкладки Фото/Друзья/Группы — данные приходят (логи `friends.get ok count=54 items=50`, `groups.get ok`), **UI пустой** (бэклог).
- **Комментарии:** счётчик, тап → PostCommentsView; «Добавить комментарий», ответ, автор → профиль, лайк комментария, thread, «Подгрузить ещё» при 0.
- **Лайки:** пост и комментарий — ставить/убирать (likes.add / likes.delete).

---

## Задача для следующей сессии

**Приоритет:** разобраться, почему вкладки профиля (Друзья, Группы, Фото) пустые при том что API возвращает данные.

**Идеи для проверки:**
1. Убедиться, что `body` табов (ProfileFriendsTabView, ProfileGroupsTabView, ProfilePhotoTabView) вызывается с непустыми массивами — добавить временный вывод (например, Text("\(viewModel.friends.count)")) или брейкпоинт.
2. Проверить иерархию: Picker + ScrollView + tabContent — возможно, контент вкладки не перерисовывается при изменении viewModel (например, из-за кэширования или идентичности view).
3. Альтернатива: загружать данные вкладки не в loadProfileIfNeeded, а при первом появлении самой вкладки (например, .onAppear у контента выбранной вкладки или по selectedTab).
4. Рассмотреть отказ от Picker в пользу отдельных кнопок/сегментов или другого способа переключения вкладок с явной привязкой к данным.

**Дальше по плану:** пагинация друзей (offset), видео в ленте, дорожная карта (друзья, альбомы, группы, сообщения).

---

## Технические детали

- **ProfileView:** только `init(authService: AuthService, viewModel: ProfileViewModel)`. userId берётся из `viewModel.userId`.
- **ProfileViewWrapper:** `init(authService: AuthService, userId: Int?)`, внутри `@StateObject viewModel = ProfileViewModel(authService: authService, userId: userId)`.
- **Таб «Профиль» в ContentView:** `ProfileView(authService: authService, viewModel: profileViewModel)`; `profileViewModel` — один на приложение.
- **PostCommentsView:** CommentAuthorDestination (user/group), authorDestination: CommentAuthorDestination?, navigationDestination(item: $authorDestination); AddCommentTarget (.root / .reply); VKComment.thread.
- **VKApiService:** likes.add, likes.delete (VKLikesAddResponse); wall.createComment (VKWallCreateCommentResponse); getWallComments(threadItemsCount: 10).
