# Контракт: чтение описания (iOS)

**Статус**: draft (2026-06-02)  
**Эталон (web, полный HTML)**: `recipe-scaler-web/.../utils/xml-fragment-to-html.ts` — **не** обязателен для iOS в 004; используется как ориентир структуры нод.

## API чтения

```text
XmlFragmentToHTML.html(
  doc: YDoc*,
  txn: YTransaction*,
  ingredients: [IngredientData]
) -> String?   // HTML или nil если fragment пуст
```

Вызывается из `DocumentManager.readDescription` при `version == v3`.

## Маппинг ProseMirror → HTML (минимальный)

| XML tag (yxmlelem_tag) | HTML |
|------------------------|------|
| `paragraph` | `<p>…</p>` |
| `heading` + attr `level` | `<h{n}>…</h{n>` |
| `bulletList` | `<ul>…</ul>` |
| `orderedList` | `<ol>…</ol>` |
| `listItem` | `<li>…</li>` |
| `blockquote` | `<blockquote>…</blockquote>` |
| `codeBlock` | `<pre>…</pre>` |
| `hardBreak` | `<br/>` |
| `timer` | span с форматированной длительностью |
| `ingredient` | текст количества + имя ингредиента |
| `bold` / `italic` / `strike` / `code` / `highlight` | `<strong>` / `<em>` / `<s>` / `<code>` / `<mark>` (element nodes) |
| `link` + `href` | `<a href="…">…</a>` |
| прочие | inner HTML детей |

**Inline marks на `Y.XmlText` delta-чанках** (ProseMirror хранит bold/italic/strike/code/highlight как `attributes` на чанках, а не только как element nodes). `renderXmlText` через `ytext_chunks` → `wrapWithInlineMarks`: bold → italic → strike → code → highlight (parity с `description-editor-bridge.js:renderXmlText`). Link приоритетнее — не вкладывается в strong/em.

Текстовые узлы: `ytext_chunks` + inline marks, fallback `yxmltext_string` + HTML-escape.

## UI

- `YDocRecipeDetailView`: `if let description = recipe.description, !description.isEmpty { StepsSection(htmlContent: description) }`
- Edit mode: секция описания read-only (без полей ввода).

## Тесты

| Тест | Проверка |
|------|----------|
| `testXmlFragmentHTMLEscapes` | `<>&"` в тексте |
| `testXmlFragmentIngredientReference` | mock ingredients + attrs (если есть fixture) |
| `testXmlFragmentPreservesInlineBoldMarksFromYjsState` | bold mark на delta-чанках (fixture `recipe-adjaruli-yjs.bin`): `<h1>`, `<strong>ри му</strong>`, `<strong>Пеки аджарули</strong>`, parser `.heading` + `.strong` runs |
| `testDescriptionParserHeadingWithInlineBold` | чистый парсер: `<h1>Бе<strong>ри му</strong>ку</h1>` → `.heading(level:1)` + `.strong("ри му")` + `.plain` |

Ручной: `quickstart.md`.