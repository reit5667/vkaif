# progress.md

## 2026-04-10

- Закрыта **TASK-027** — UI-кнопки видеоплеера скрываются при воспроизведении. JS `play`-event → `videoPlaying` message; кнопка закрытия всегда видима; `UITapGestureRecognizer(cancelsTouchesInView: false)` вместо `Color.clear`-слоя — VK-плеер получает тапы.
- Закрыта **TASK-034** — pull-to-refresh в ленте + прокрутка к верху. `loadFeed()` возвращает `Task`, `.refreshable` ждёт завершения.
- Закрыта **TASK-032** — puzzle-раскладка фото. `case 3`: большое фото слева + два маленьких справа.
- Внеплановый фикс: одиночное фото в ленте — `scaledToFit` вместо `fill`, `maxHeight: 520`.

## 2026-04-09

- Закрыта **TASK-031** — превью фото в ленте не загружались.
  - Причина: `newsfeed.get` возвращает фото-стабы (только `id`+`owner_id`, без `sizes`/`photo_xxx`). VK отдаёт полные данные только для части фото в посте.
  - Решение: добавлен `VKApiService.photosGetById` и `enrichPhotoStubs` в `ContentView` — после загрузки ленты стабы подгружаются батч-запросом и заменяются в постах.
  - Дополнительно: trimming URL в `urlFromSizes`; placeholder в `repostBlock` (был пустой элемент при nil URL); `.id(photo.id)` на ячейках `AlbumPhotosView`.
- **TASK-033** уже был done в предыдущей сессии; статус обновлён.

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
