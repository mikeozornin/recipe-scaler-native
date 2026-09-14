# Data model: 076 clipboard import banner

**Spec**: [spec.md](./spec.md)  
**Plan**: [plan.md](./plan.md)

Сервер и Y.Doc **не** участвуют. Модель — in-memory сессия процесса + OS pasteboard.

## ClipboardImportCandidate

Нормализованный набор URL из буфера.

| Поле | Тип | Правила |
|------|-----|---------|
| `urls` | `[String]` | Дедуп и порядок как `ImportContentClassifier.extractUrls`; только `http`/`https` |
| identity | `urls` | Равенство candidate = равенство массива |

Валидность для баннера: `!urls.isEmpty`, `urls.count <= 25`, классификация `isUrlOnly == true`.

`seedText` для sheet: `urls.joined(separator: "\n")`.

## ClipboardImportSessionMemory

| Поле | Тип | Правила |
|------|-----|---------|
| `dismissed` | `Set` identity | Свайп вниз |
| `consumed` | `Set` identity | Успешный импорт этого набора в этой сессии |
| `ignoredChangeCounts` | `Set<Int>` | `UIPasteboard.changeCount` после своих Copy |
| `evaluateGeneration` | `Int` | Bump на logout и на каждый evaluate |

Не Codable. Не UserDefaults. Не App Group.

`isSuppressed(_ candidate)` = в `dismissed` ∪ `consumed`.

## ClipboardImportBannerState

UI-проекция store (одно observable поле достаточно):

```swift
enum ClipboardImportBannerState: Equatable {
    case hidden
    case visible(ClipboardImportCandidate)
}
```

`visible` только если candidate валиден, не suppressed, не own-write, есть сессия, Import sheet закрыт, URL-импорт доступен (тот же optimistic online, что сегмент Text в 010), нет pending Share/file/deep-link входа, нет активного `TransientStatusBanner`.

## ImportPresentation (расширение)

Существующий Identifiable sheet item.

| Поле | Тип | Правила |
|------|-----|---------|
| `id` | `UUID` | Как сейчас, новый на каждое present |
| `seedText` | `String` | Пусто для вкладки Import; иначе seed |
| `autoSubmit` | `Bool` | `true` только с баннера |

См. [contracts/import-presentation.md](./contracts/import-presentation.md).

## Pasteboard snapshot (тестовый порт)

| Поле | Тип | Правила |
|------|-----|---------|
| `changeCount` | `Int` | Монотонный |
| `hasProbableWebURL` | `Bool` | Без чтения строки |
| `plainText` | `String?` | Читать только если hasProbableWebURL |

Продакшен-адаптер читает `UIPasteboard.general`. Тесты подставляют фейк — без UIKit pasteboard.

## State transitions

```text
hidden ──evaluate eligible──► visible
visible ──swipe──► hidden  (identity → dismissed)
visible ──import tap──► hidden  (sheet open; identity ещё не consumed)
sheet success ──► identity → consumed; остаётся hidden
sheet cancel/error ──► identity не consumed; следующий evaluate может снова visible
logout / wipe ──► memory empty, hidden
```
