# Contract: ClipboardImportCandidate

**Owner**: `ImportContentClassifier` + `ClipboardImportStore`  
**Readers**: banner UI, dismiss/consumed sets, Import sheet seed  
**Expiry of literals**: нет user-facing copy здесь.

## Классификация

1. Если pasteboard не содержит вероятного web URL (`detectPatterns` / `hasURLs`) — candidate нет, **строку и `.urls` не читать** (иначе iOS покажет Allow Paste).
2. Баннер можно показать по metadata. Plain text читать только по жесту Import, затем `ImportContentClassifier.classify(_:)`.
3. Импорт стартует только если `isUrlOnly && (1...25).contains(urls.count)`.
4. Identity dismiss/consumed = `changeCount` этого буфера, не raw string.

Ненормализованный raw string **не** ключ dismiss.

## Свои записи

После `AppPasteboard.setString` текущий `changeCount` попадает в `ignoredChangeCounts`. Handler живёт в `AppContainer` (`[weak clipboardImport]`), сбрасывается в `stopForLogout`.

## Consume identity

`markConsumed()` пишет в `consumedChangeCounts` только `pendingConsumeChangeCount` (зафиксирован в `seedTextForImport` на тапе Import) или текущий `visibleChangeCount`. Нельзя fallback на live `pasteboard.changeCount`, иначе фото/файл-импорт или sheet без баннера «съест» чужой буфер.

`seedTextForImport` отменяется в `clearForLogout` и дропает результат, если `evaluateGeneration` сменился.

## Не miller-fallback

Неизвестный / пустой буфер → `hidden`, не «попробуем как текст рецепта».
