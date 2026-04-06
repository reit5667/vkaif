# progress.md

## 2026-04-04

- Закрыты и вручную проверены `TASK-001`, `TASK-002`, `TASK-003`.
- Обновлены `tasks.json`, `PROJECT_STATUS.md`, `PROJECT_STATUS_ARCHIVE.md` и `PRD-CleanFeedVK-2026-04-04.md` под фактическое состояние проекта.
- Отдельная заметка: последний разбор Claude из terminal log относился к `TASK-004`, а не к `TASK-003`.

## 2026-04-06

- Закрыта **TASK-025** — фото из репоста открываются в fullscreen.
- Закрыта **TASK-026** — шрифт «Показать ещё» увеличен до .subheadline.
- Закрыта **TASK-028** — свайп снизу-вверх закрывает fullscreen.
- Закрыта **TASK-029** — хитбокс «Показать ещё» исправлен (contentShape + frame maxWidth).
- Закрыта **TASK-030** — ссылки открываются в SFSafariViewController, не в VK-приложении.
- TASK-007 закрыта без реализации — рекомендации VK оставлены как есть.
- Добавлены TASK-028–033 в tasks.json и backlog.md.
- Backlog.md переписан в формат `[x]`/`[ ]`/`[-]`.

## 2026-04-05

- Закрыта `TASK-004` — удаление фото из альбома (Swift ABI ARM64 bug fix, GalleryDeleteRequest).
- Закрыта `TASK-005` — убран JustifiedTextView, заменён на SwiftUI Text + .leading.
- Закрыта `TASK-006` — добавлено время к дате поста (ru_RU DateFormatter).
- Закрыты `TASK-023` + `TASK-024` — исправлен свайп переключения фото в fullscreen-галерее; dismiss-жест перенесён на уровень ячейки и работает только при zoom = 1.
- Перенесён `backlog.md` в корень проекта (из Obsidian Vault).
