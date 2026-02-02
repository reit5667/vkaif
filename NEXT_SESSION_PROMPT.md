# Промпт для следующей сессии

Проект: CleanFeedVK (iOS, SwiftUI, MVVM). Спека и дорожная карта — PROJECT_STATUS.md в корне.

Текущее состояние:
- Лента: Auth (OAuth Kate Mobile, Keychain), newsfeed.get, фильтр (ads/promo/blacklist), LazyVStack с подгрузкой (next_from), ячейка поста (заголовок с тапом → группа/профиль, текст «Показать ещё», сетка фото 1–10, счётчики лайков/комментариев под постом). Фото поста открываются на полный экран с пролистыванием (FullScreenPhotoGalleryView). Тап по автору поста → GroupWallView (groups.getById + wall.get) или ProfileView(userId) — работает.
- Профиль: users.get, аватар, имя, статус; вкладки Фото/Друзья/Группы — API возвращает данные, но списки в UI пустые (в бэклоге). Тап по аватару → fullscreen. ProfileViewModel: Composition, независимая загрузка секций, hasStartedInitialLoad.
- Альбомы: photos.getAlbums, photos.get; экран альбома — сетка фото, тап → fullscreen.
- Комментарии: ✅ счётчик под постом, тап по счётчику → PostCommentsView (sheet, wall.getComments, пагинация по 5, «Подгрузить ещё»). Работает в ленте и на стене группы. Экран показывает автора (profiles/groups), дату, текст, счётчик лайков комментария. В бэклоге: тап по автору комментария → профиль, лайк на комментарий (likes.add, type=comment), ответить на комментарий (wall.createComment, reply_to_comment).
- API: разбор ошибки VK для friends.get, photos.getAlbums, groups.get, wall.get, groups.getById, wall.getComments; логирование. OAuth scope: wall,offline,friends,photos,groups.
- Лайки под постом: показываются (VKPost.likes.count). Ставить лайки (likes.add) пока нет.

Стек: iOS 17+, Swift 6, SwiftUI, URLSession, Keychain. Новые экраны — расширять VKApiService, модели/Views/ViewModels по MVVM.

План дальше: улучшения комментариев (переход на автора, лайк, ответ), лайки на посты (likes.add), пагинация друзей, видео в ленте. Дорожная карта: друзья, альбомы, группы (страница из ленты есть), сообщения.

Технические детали:
- PostCommentsView: использует CommentsLoadState (private enum), .onAppear(perform:) с явной функцией performInitialLoadIfNeeded(), if case .idle = loadState для pattern matching (enum не Equatable из-за case failed(Error)).
- PostCellView: опциональный onTapComments: (() -> Void)?, по тапу на счётчик комментариев вызывается замыкание.
- ContentView и GroupWallView: @State var commentsContext: PostCommentsContext?, .sheet(item: $commentsContext) { PostCommentsView(context: $0, authService: authService) }.
- VKApiService.getWallComments: owner_id, post_id, offset, count (по 5), sort=asc, need_likes=1, extended=1 для profiles/groups.
