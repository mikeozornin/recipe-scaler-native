# Спецификация: Ассистент — вход через таббар

**Дата**: 2026-08-31
**Статус**: 🟡 В работе
**Зависимости**: `015-assistant` (sheet), `007-app-shell-navigation` (фейк-таб паттерн), `030-timer-panel` (accessory slot)
**Решение**: 2026-08-31 — гибрид по версии ОС; **v3** — iOS 26 отдельная кнопка (`Tab(role: .search)` без morph) + sheet; legacy фейк-таб + sheet. **v3.1 (review fix)**: гейт modern TabView поднят 26.0 → **26.2** — на 26.0/26.1 таймер-панель modern-пути (`tabViewBottomAccessory` / `safeAreaBar`) не существует, без этого она молча пропадает.

## Контекст

Ассистент открывается FAB-кнопкой (поверх контента, над таббаром). Решение 2026-08-31: вход переносится в таббар.

**Итоговая механика (v3.1):**

- **iOS 26.2+**: `Tab(role: .search)` со `sparkles` в отдельном Liquid Glass слоте справа; **без** `.searchable` (нет morph); тап → modal `AssistantSheet`; `selectedTab` не меняется (fake selection).
- **iOS < 26.2 (включая 26.0/26.1)**: фейк-таб `Color.clear` + `sparkles` в tab bar → modal sheet; `selectedTab` не меняется.

## Границы

**В scope:**
- `AppTab.assistant` — fake entry на всех версиях (selection never `.assistant`)
- Dual TabView: `legacyTabView` / `modernTabView`
- Modal `AssistantSheet` с полным `AssistantComposer`
- iOS 26.2+: `Tab(role: .search)` только для **placement** (отдельная кнопка), не search UX
- Programmatic open: `pendingAssistantTabOpen` / `pendingAssistantOpenRequest`
- Удаление Import-таба; import через sheet / Menu «+»

**Вне scope:**
- `AssistantSheet` wire protocol / streaming
- `.searchable`, `tabViewSearchActivation`, inline assistant, morph strip
- Figma layout для иконки

## Конституционная проверка

- HIG: search role для non-search action — осознанное отклонение (product decision). Fake tab → sheet на всех версиях.
- Offline-first: без изменений.

## Решение iOS 26 (v3)

Принято:
- `Tab(value: .assistant, role: .search)` + `Color.clear` content + `AppTabBarLabel(sparkles)`
- **Не** использовать `.searchable`, **не** `tabViewSearchActivation`
- `modernTabSelection` → `handleTabSelection` → `.assistant` sets `pendingAssistantTabOpen` → sheet

Отклонено:
- Search morph + inline chat (overlap, search UX)
- Обычный 5-й таб в bar (нет отделённой кнопки справа)

## Positive invariants

- PI-1: Тап `tab-assistant` → sheet; `selectedTab` unchanged.
- PI-2: Logout clears `pendingAssistantTabOpen`.
- PI-3: Повторный тап после dismiss снова открывает sheet.
- PI-4: Sheet: full composer + nav toolbar (history, new chat).
- PI-5: External open → sheet with payload.
- PI-6: iOS 26.2+: нет search pill / morph field после тапа assistant.
- PI-7: `sparkles` in `AppTab.allCases` UIKit symbol test.

## Downstream consumers

| Consumer | Влияние |
|----------|---------|
| `AppShellView` | iOS 26.2+: search-role tab; legacy: fake tab; `AssistantSheetModifier` |
| `AppShellCoordinator` | `handleTabSelection(.assistant)` |
| `AssistantSheet` | Modal only |
| UI-тесты | `tab-assistant` → `assistant_sheet` |

## Verification

- `xcodebuild build` (RecipeScalerNative-Dev)
- **iOS 26.2+ sim (26.3)**: отдельная sparkles справа; sheet; **no** search morph; таймер-панель через accessory
- **iOS 18 sim**: fake tab in bar; sheet; таймер-панель через safeAreaInset
- **iOS 26.0/26.1** (рантайм опционален): ведут себя как 18.x — legacy бар + фейк-таб; гейт tabView = 26.2
- `bash scripts/lint-i18n.sh`

## Типографика табов

**Осознанный трейд-офф (подтверждено визуально 2026-08-31, iOS 26.3):** на modern-пути (26.2+) подписи табов рендерятся системным шрифтом — новый Tab API игнорирует и `.font` на кастомном `label:`, и `UITabBarItem.appearance().setTitleTextAttributes`. Продукт принял: визуально приемлемо. На legacy-пути (< 26.2) подписи — Martian (appearance-прокси применяется).

Кастомный `label: { AppTabBarLabel(tab:) }` обязателен на modern-пути не ради шрифта, а ради accessibility-идентификаторов (`tab_recipes` и т.д.): при `Tab(title:systemImage:)` система генерирует свои id (`book`, `cart`, `person`), и UI-тесты их не находят.
