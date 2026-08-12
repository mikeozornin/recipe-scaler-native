# Quickstart: свайп от левого края для отметки покупки

**Spec**: [spec.md](./spec.md)
**Plan**: [plan.md](./plan.md)

## Где смотреть код после реализации

- `RecipeScalerNative/Views/ShoppingListView.swift` — `shoppingRow(...)` (líneas ~305-344) — добавлен `.swipeActions(edge: .leading, allowsFullSwipe: true)` с зелёной галочкой.
- `scripts/verify-shopping-list-ui-polish.sh` — расширен assert-блоком `assert-leading-swipe-toggle`.

## Что НЕ меняется

- Схема Y.Doc, sync-события, контракты с вебом.
- Существующий tap-to-check в `shoppingRow` (líneas 314-322).
- Существующий trailing swipe-delete через `.onDelete` (líneas 148, 162).
- Inline-edit для ручных пунктов (`inlineEditRow`, líñas 268-284).
- i18n-ключи — переиспользуем `shopping.mark-purchased`/`shopping.mark-not-purchased`.

## Локальная проверка

### Минимальный цикл

```bash
# 1. Build
xcodebuild -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# 2. Smoke (sync + add flows из 024 — должны быть зелёными)
bash scripts/verify-shopping-list-smoke.sh

# 3. UI-polish с новым swipe assert
bash scripts/verify-shopping-list-ui-polish.sh

# 4. i18n lint (новых ключей нет, должно быть без новых предупреждений)
bash scripts/lint-i18n.sh
```

### Ручной сценарий

1. Открыть вкладку Shopping с непустым списком «Купить».
2. Свайпнуть строку от левого края — должна появиться зелёная галочка.
3. Отпустить на полном свайпе — пункт должен переехать в «Куплено» (через staging ~1с + haptic).
4. Повторить для строки в «Куплено» — пункт вернётся в «Купить».
5. Свайпнуть справа — должна появиться красная delete-кнопка из 024.
6. Активировать inline-edit ручного пункта — leading swipe должен быть недоступен.

## Известные ограничения

- В DBG-сборке auto-login prod debug user — сценарий проверяется на реальном списке покупок пользователя (как в 024).
- Свайп не автоматизирован в unit-тестах — только в UI verify-скрипте (через `xcrun simctl` swipe gesture).
- Staging-animation не изменён — те же ~1с + haptic, что и в 024.
