# Research — 019 Inline description editor

**Дата**: 2026-06-10

## Решение по UX (зафиксировано)

| Вопрос | Решение |
|--------|---------|
| Общий скролл vs отдельный экран | **Общий скролл** в одном Edit |
| Sheet `DescriptionEditorView` | **Deprecated** в пользу inline |
| Toolbar | **Нативный sticky bottom**, команды в Tiptap через мост v2 |
| Длинный текст | **embedded** + порог → **focus** (внутренний скролл WebView) |

## Высота WebView

### Embedded (основной режим)

- `WKWebView.scrollView.isScrollEnabled = false`
- Swift задаёт высоту контейнера = `max(minEmbeddedHeight, contentHeight)`
- Скролл страницы — внешний `ScrollView` `YDocRecipeDetailView`

### Focus (страховка)

- Условие: `contentHeight > embeddedMaxHeight` (стартовое значение **2000 pt**)
- Высота WebView ≈ viewport − `safeAreaInset` панели − keyboard layout guide
- `scrollView.isScrollEnabled = true`
- Пользователь не покидает Edit; ингредиенты доступны скроллом вверх

### Открытые вопросы (проверить при implement)

- Нужен ли `caretRect` для `scrollTo` при появлении клавиатуры (часто решается focus-режимом).
- Retina scale: `contentHeight` из JS — договориться об одной единице (логично CSS px → Swift points через координатор).

## Spike D — нативный rich text без WebView

| Подход | Вердикт |
|--------|---------|
| yrs прямая запись ProseMirror XML | **Нет** API (как в 006) |
| `UITextView` + AttributedString | Удобный ввод, **нет** Timer/Ingredient nodes |
| Генерация XmlFragment из Swift | Высокий риск поломки ProseMirror на вебе |

**Go/no-go:** **NO-GO** для production parity. WebView + Tiptap остаётся единственным путём v3.

## Движок: contentEditable → Tiptap

| | MVP 006 | 019 |
|---|---------|-----|
| JS | contentEditable + ручной XML | Tiptap + Collaboration |
| Toolbar | HTML `#toolbar` | Нативный + `command` |
| Паритет веб | Частичный | Целевой (018 в фазах) |

Сборка: esbuild в монорепо, по возможности общие extension-файлы с `recipe-scaler-web/recipe-scaler/src/components/tiptap-extensions/`.

Оценка размера bundle: ориентир **300–600 KB** gzip в IPA (уточнить после первой сборки); lazy init WebView при первом edit.

## Память и lifecycle

- Один `WKWebView` на активный `recipeId` в edit.
- `dismantle` при `isEditing = false` или `onDisappear` detail.
- Не открывать sheet и inline одновременно.

## Связь с 018

Функции 018 не требуют отдельного UI-решения: ссылки и ноды — те же `command` + нативные pickers. Round-trip тесты — фикстуры в `quickstart.md`.