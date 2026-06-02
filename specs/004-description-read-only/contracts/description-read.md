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
| `bold` / `italic` / `strike` / `code` | `<strong>` / `<em>` / `<s>` / `<code>` |
| `link` + `href` | `<a href="…">…</a>` |
| прочие | inner HTML детей |

Текстовые узлы: `yxmltext_string`, HTML-escape.

## UI

- `YDocRecipeDetailView`: `if let description = recipe.description, !description.isEmpty { StepsSection(htmlContent: description) }`
- Edit mode: секция описания read-only (без полей ввода).

## Тесты

| Тест | Проверка |
|------|----------|
| `testXmlFragmentHTMLEscapes` | `<>&"` в тексте |
| `testXmlFragmentIngredientReference` | mock ingredients + attrs (если есть fixture) |

Ручной: `quickstart.md`.