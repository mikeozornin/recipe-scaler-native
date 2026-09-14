# Contract: ImportPresentation seed + auto-submit

**Owner**: `AppShellCoordinator`  
**Readers**: `ImportRecipeSheet`, `AppShellView.sheet(item:)`

## Present

| Вызов | seedText | autoSubmit | consumesClipboard |
|-------|----------|------------|-------------------|
| Таб Import / CTA 040 | `""` | `false` | `false` |
| Баннер «Импортировать» | URL через `\n` | `true` | `true` |

`RecipeImportAPI.importURLs` / `importText` / `importImages` используют `APIClient.llmRequestTimeout` (180s), как rebuild process table: серверный import LLM до 120s, nginx 300s. Дефолтные 15s `requestTimeout` рвут URL-импорт (прод: nginx **499** через ~15s после `Starting recipe import from URL`).

Один `.sheet(item: $coordinator.importPresentation)`. Не второй sheet.

Share / UL / файл: `inboundClipboardSuppressed` (и pending recipe id) держат баннер скрытым до посадки inbound, затем `endInboundClipboardSuppression` + evaluate. Не опираться на `hasPendingRecipeId()` после `consumePendingRecipeId()`.

## Sheet onAppear (порядок обязателен)

1. Существующий `resetState()` (офлайн fallback сегментов без изменений).
2. Если `seedText` не пустой: `mode = .text` (через system-mode, чтобы не стереть ошибку позже), `bodyText = seedText`.
3. Если `autoSubmit` и `canSubmit` и online-гейт Text: синхронно `isProcessing = true` (textarea / сегменты disabled, web parity), затем `importTask = Task { await submit() }` — тот же `submit()`, что кнопка `import.lets-go`.
4. Screenshot capture / debug: не автосабмитить, если это ломает About shots (`DebugLaunchOptions.screenshotCapture` → как ручной sheet).

## Завершение

- Успех: существующий `completeImport` + тост. Store: `markConsumed()` **только если** `presentation.consumesClipboard`.
- Отмена / ошибка: sheet dismiss как сейчас; store **не** dismissed и **не** consumed.

Повторный тап баннера, пока sheet открыт: баннер не виден (FR-010), второго present нет.
