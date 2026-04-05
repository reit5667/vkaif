# progress.md

## 2026-04-04

- Закрыты и вручную проверены `TASK-001`, `TASK-002`, `TASK-003`.
- Обновлены `tasks.json`, `PROJECT_STATUS.md`, `PROJECT_STATUS_ARCHIVE.md` и `PRD-CleanFeedVK-2026-04-04.md` под фактическое состояние проекта.
- Отдельная заметка: последний разбор Claude из terminal log относился к `TASK-004`, а не к `TASK-003`.

## 2026-04-05

- Закрыта `TASK-004` — удаление фото из альбома.
- Найден и задокументирован Swift ABI-баг ARM64: `@escaping async` замыкание `(String, Int, Int)` получает мусор в Int-параметрах. Обходное решение: `GalleryDeleteRequest` (ref-type класс), shared через `@State`; photoId записывается синхронно до `await`. Детали — в `TECHNICAL_NOTES.md`.
- Следующий трек: `TASK-005` (justified-текст в постах).
