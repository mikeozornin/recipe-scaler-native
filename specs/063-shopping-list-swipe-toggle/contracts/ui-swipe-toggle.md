# Contracts: свайп от левого края для отметки покупки

**Spec**: [spec.md](./spec.md)
**Plan**: [plan.md](./plan.md)

## Контракты, затрагиваемые фичей

Фича **не вводит новых контрактов** и **не меняет существующие**. Раздел фиксирует это явно, чтобы plan-review мог быстро подтвердить отсутствие cross-target/cross-process ограничений.

## UI contract (внутренний, iOS app target)

| Surface | Контракт | Изменение фичей |
|---------|----------|-----------------|
| `ShoppingListView.shoppingRow` | Row view с tap-to-check Button, `.onDelete` trailing, inline-edit для manual items | Добавляется `.swipeActions(edge: .leading, allowsFullSwipe: true)` с action → `handlePurchaseToggle` |
| `ShoppingListView.handlePurchaseToggle(item:phase:)` | Существующая точка мутации: staging ~1с, haptic, syncService call | Без изменений — переиспользуется из swipe-action без дубля |

## Sync contract (без изменений)

Наследуется из спеки 024:
- Y.Doc ключ: `{userId}:shoppingList`, `documentKind: shoppingList`.
- Socket.IO event: `shopping_list_updated`.
- Offline-queue drain при реконнекте.

Фича **не добавляет** новых событий, ключей, documentKind.

## i18n contract (без новых ключей)

| Ключ | Текущее использование | После фичи |
|------|----------------------|------------|
| `shopping.mark-purchased` | accessibility label чекбокса (línea 328) | + accessibility label + visual label swipe-кнопки (toggle в unchecked → checked) |
| `shopping.mark-not-purchased` | accessibility label чекбокса (línea 327) | + accessibility label + visual label swipe-кнопки (toggle в checked → unchecked) |

Оба ключа уже есть в `Localizable.xcstrings` со всеми переводами.

## Accessibility contract

- Swipe-кнопка наследует `accessibilityLabel` через `Label(text, systemImage:)` — SwiftUI автоматически использует текст ключа.
- VoiceOver/Hover/Keyboard navigators: swipe-actions доступны через тот же a11y-API, что и кнопка чекбокса — двойной путь для пользователей без точного тапа.
- a11y-описание отметки покупки **согласованное** между tap и swipe — оба используют один ключ (FR-011 выполнен).

## Cross-process / cross-target

N/A — фича локальна в iOS app target; widgets/watchOS/Live Activity/App Intents не затрагиваются.

## Backward compatibility

N/A — нет форматов/контрактов, требующих версионирования.
