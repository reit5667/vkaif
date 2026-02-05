# Сообщения (Messages) — структура реализации

Оценка и план для таба «Сообщения» в CleanFeedVK. Документация VK: https://dev.vk.com/method/messages (при необходимости актуализировать по актуальной версии API).

---

## Сложность реализации

**Умеренная (средняя).** Основная работа — UI (список диалогов, экран чата, ввод и отправка), а не сложная серверная логика. API VK для сообщений линейное.

**Что усложняет:**
- Нужен scope **messages** в OAuth; после добавления — перелогин пользователей.
- Длинный список диалогов и история чата — пагинация (offset/count или start_message_id).
- Опционально: Long Poll (messages.getLongPollServer, Bots Long Poll API) или периодический messages.get для «живых» обновлений — добавляет сложность.

**Что упрощает:**
- Методы messages.getConversations и messages.get — стандартные, ответы с profiles/groups для подстановки имён и аватаров.
- Отправка: messages.send с peer_id (user_id или 2000000000 + chat_id). Без вложений для MVP достаточно.

**Рекомендуемый порядок:** сначала список диалогов (getConversations) и просмотр истории (get), затем отправка (send). Long Poll или автообновление — после стабильного MVP.

---

## API (минимальный набор)

| Метод | Назначение |
|-------|------------|
| **messages.getConversations** | Список диалогов (чаты и личные). Параметры: count, offset, filter (all/unread и т.д.). Extended=1 → items (conversation, last_message), profiles, groups. |
| **messages.getHistory** | История сообщений с пользователем или в беседе. Параметры: peer_id (user_id или 2000000000+chat_id), count, offset (или start_message_id). Extended=1 → profiles, groups. |
| **messages.send** | Отправить сообщение. Параметры: peer_id, message (текст), random_id (уникальный для дедупликации). |
| **messages.getLongPollServer** (опц.) | Сервер для Long Poll — обновления в реальном времени. Использовать после MVP. |

**Идентификация диалога:** в conversation может быть peer: { id, type }, в last_message — from_id, text, date. Для ответа и отправки используется **peer_id** (id пользователя или 2000000000 + chat_id для беседы).

---

## Структура экранов и данных

1. **Таб «Сообщения»** (сейчас заглушка)
   - Заменить заглушку на экран со списком диалогов.
   - Данные: getConversations → массив элементов (conversation + last_message); для отображения — имя/аватар из profiles/groups по peer_id.
   - Ячейка: аватар, имя, превью последнего сообщения, время, непрочитанность (если есть в ответе).
   - Тап по ячейке → переход к экрану чата с peer_id.

2. **Экран чата**
   - Заголовок: имя собеседника/беседы (из profiles/groups).
   - Список сообщений: getHistory(peer_id) → отображение в обратном порядке (новые снизу) или с переворотом списка.
   - Под списком: поле ввода + кнопка «Отправить» → messages.send(peer_id, message, random_id).
   - Пагинация: подгрузка старых сообщений (offset или start_message_id).

3. **Модели (примерно)**
   - `VKConversation`, `VKLastMessage` — по полям ответа getConversations.
   - `VKMessage` — id, from_id, peer_id, text, date; для вложений при расширении — attachments.
   - Ответы методов обёрнуты в Decodable так же, как для ленты/стены.

4. **Сервис**
   - В VKApiService: getConversations(token, count, offset, filter), getHistory(token, peerId, count, offset), sendMessage(token, peerId, text, randomId).
   - Ошибки и логи — в том же стиле, что и для wall/photos.

---

## Зависимости

- Добавить scope **messages** в запрос OAuth (AuthService / URL при логине). Обновить TECHNICAL_NOTES.md (OAuth).
- Текущий пользователь: id доступен из users.get или из ответов API (например, из getConversations при необходимости).

---

## Порядок реализации (чеклист)

- [ ] Изучить актуальную документацию messages.getConversations, messages.getHistory, messages.send (поля ответов, коды ошибок).
- [ ] Добавить scope `messages` в OAuth.
- [ ] Модели: декодирование ответов getConversations и getHistory.
- [ ] VKApiService: методы getConversations, getHistory, send.
- [ ] Экран списка диалогов: загрузка, ячейки, переход в чат по peer_id.
- [ ] Экран чата: загрузка истории, отображение, ввод, отправка, пагинация вверх.
- [ ] (Опционально) Long Poll или таймер для обновления списка диалогов и чата.
