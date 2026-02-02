# CleanFeedVK — состояние и дорожная карта

## 1. Что уже есть (MVP ленты — готово)

| Компонент | Статус |
|-----------|--------|
| Структура MVVM | ✅ Models, Views, ViewModels, Services (Network, Auth, Persistence), Utilities |
| NetworkService | ✅ async/await, URLSession, DI-протокол |
| AppLogger | ✅ Уровни, категории, os_log |
| Auth | ✅ OAuth 2.0 Implicit (Kate Mobile), Keychain |
| VKApiService | ✅ newsfeed.get, пагинация (start_from) |
| Модели VK | ✅ newsfeed.get, посты, вложения (photo/video/link/doc), profiles/groups |
| Фильтр | ✅ marked_as_ads, promo, blacklist (ключевые слова) |
| Лента UI | ✅ LazyVStack, подгрузка в конец, ячейка поста |
| Ячейка поста | ✅ Заголовок (аватар, имя, дата), текст с «Показать ещё», **сетка фото (1–10)** |
| Офлайн-кэш | ❌ Не в плане (исключён по решению) |

---

## 2. Дорожная карта (дальше)

Приоритет по желанию:

1. **Профиль** — свой профиль и профиль друзей (users.get, аватар, имя, статус, возможно стена).
2. **Друзья** — список друзей (friends.get), переход в профиль.
3. **Альбомы** — фотоальбомы пользователя и групп, в т.ч. **сохранённые фото** (photos.get, photos.getAlbums, saved).
4. **Группы** — список групп пользователя, страница группы (groups.get, wall группы).
5. **Сообщения** — в последнюю очередь (messages.get, messages.getConversations; сложнее по API и модерации VK).

Цель — «всё необходимое для сервинга ВК»: лента ✅, профили, друзья, альбомы, группы, затем сообщения.

---

## 3. Диагностика

- Консоль Xcode: префикс `[CleanFeedVK]`, категории Network, Auth, VKApi, Keychain.
- Console.app: фильтр по subsystem (bundle id).

---

## 4. Технические заметки

- **Картинки в постах:** из `attachments[].photo.sizes` берётся URL (приоритет x → m → s), отображается в `LazyVGrid` (1 фото — во всю ширину, 2 — два столбца, 3+ — до 3 столбцов).
- **Пагинация ленты:** при достижении конца списка вызывается `newsfeed.get(start_from: nextFrom)`, посты и авторы мержатся в текущие массивы.
