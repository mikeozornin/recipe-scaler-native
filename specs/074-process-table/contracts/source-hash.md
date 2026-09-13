# Contract: sourceHash

Канон: [`recipe-scaler-web/shared/utils/process-table-source-hash.ts`](../../../../recipe-scaler-web/shared/utils/process-table-source-hash.ts).

Native MUST дать тот же hex, что `computeProcessTableSourceHash` / `hashProcessTableFromRecipe`.

## Каноническая строка

UTF-8 JSON **ровно** такого вида (пробелов нет — как `JSON.stringify` объекта с этим порядком ключей):

```json
{"ingredients":[{"id":"<id>","originalAmount":<number|null>,"unit":"<string>"}],"steps":["<plain>"]}
```

- Ингредиенты: document order, без `isSeparator`, только непустой `id`.
- `originalAmount`: finite number, иначе `null` (JSON `null`, не omit).
- `unit`: string, иначе `""`.
- Имена **не** входят.
- Legacy string `amount` **не** входит.
- `steps`: plain text блоков; сначала все `<li>…</li>`, если ни одного — `<p>…</p>`. Теги снять, `&nbsp;`/`&amp;`/`&lt;`/`&gt;`/`&quot;`/`&#39;` как в TS, whitespace collapse trim. Пустой текст блока skip, индекс оставшихся подряд с 0.

Источник HTML: живой description (v1 string / v2 Y.Text / v3 XmlFragment→HTML). Не `descriptionText`, если он опустошён.

`sourceHash` = SHA-256 hex lowercase этой строки (NIST SHA-256, тот же digest что CryptoKit / Node `crypto.createHash('sha256')`).

Проверка: `SHA-256("abc")` = `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`.

## Fixture (стабильность)

Один ingredient `id=flour`, `originalAmount=200`, `unit=g`, steps `Mix dry`, `Bake`:

```
{"ingredients":[{"id":"flour","originalAmount":200,"unit":"g"}],"steps":["Mix dry","Bake"]}
```

Golden SHA-256: `bda43ba6ff1804a016cd2a04899dd1ca49143a12c5fe95d5a295d805f9e6c882`

Rename name не меняет хеш; смена 200→180 меняет.

Таблицы, записанные сломанным hasher'ом до фикса K-таблицы, web считает свежими через `isProcessTableSourceHashCurrent`. Native сравнивает только настоящий SHA-256: после деплоя фикса нужен rebuild, чтобы `sourceHash` в Y.Doc совпал с iOS.
