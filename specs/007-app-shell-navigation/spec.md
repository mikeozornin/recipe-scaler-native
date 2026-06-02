# Спецификация: оболочка приложения и главная навигация

**Ветка**: `007-app-shell-navigation`  
**Дата**: 2026-06-02  
**Статус**: Draft  
**Зависимости**: 001–004 (авторизованный пользователь + sync)  
**Эталон**: `recipe-scaler-web/recipe-scaler/src/components/bottom-nav.tsx`, `utils/main-nav.ts`

## Контекст

Сейчас `ContentView` показывает только `RecipeListView`. Мобильный веб после логина — **5 равных вкладок**:

1. Discover  
2. Import (sheet, не route)  
3. My recipes (`/`)  
4. Shopping (`/shopping`)  
5. Profile (`/account`)

Без этой оболочки остальные фичи (009–015) не имеют естественной точки входа.

## Цель

`TabView` / custom tab bar с **тем же составом и поведением reset**, что мобильный веб.

## Пользовательские сценарии

### US1 — Пять вкладок (P1)

**Когда** пользователь авторизован, **тогда** внизу 5 вкладок с иконками и подписями (i18n keys как `discover.nav.*` на вебе).

### US2 — Reset nested routes (P1)

**Дано** пользователь на вложенном Discover (`/discover/...`) или публичном профиле, **когда** повторно нажимает вкладку Discover, **тогда** корень Discover (как `shouldResetDiscover` в `bottom-nav.tsx`).

**Дано** открыта деталь `/recipe/:id`, **когда** повторно нажимает «Мои рецепты», **тогда** корень списка (как `shouldResetRecipes`).

### US3 — Import tab (P1)

**Когда** нажата вкладка Import, **тогда** открывается sheet импорта (реализация контента — **010**; здесь только trigger + placeholder до 010).

### US4 — Safe area и таймеры (P2)

**Тогда** контент не перекрывается tab bar + home indicator; при активных таймерах — зарезервировать место под панель таймеров (аналог `TimerPanel variant="mobile"` + CSS vars на вебе).

### US5 — Sync lifecycle (P1)

**Тогда** `YjsSyncService.start` остаётся на уровне shell (один раз на userId), не пересоздаётся при смене вкладки.

## Требования

### FR-NAV-001 — Вкладки

| Вкладка | Root view (placeholder OK) | Spec контента |
|---------|------------------------------|---------------|
| discover | DiscoverRootView | 011 |
| import | sheet only | 010 |
| recipes | RecipeListView (существует) | 008 |
| shopping | ShoppingListRootView | 009 |
| profile | AccountRootView | 013 |

### FR-NAV-002 — Ширина подписей

Подписи могут переноситься на 2 строки; вкладки **равной ширины** (grid 5 cols на вебе).

### FR-NAV-003 — Навигация внутри вкладки

Каждая вкладка — свой `NavigationStack`; deep links на рецепт остаются внутри вкладки recipes.

### FR-NAV-004 — DEBUG / UI-test

Сохранить `DescriptionFixturePreviewView` и launch args без поломки tab shell.

## Вне scope

- Desktop sidebar (только mobile parity)
- Assistant FAB (015 — отдельный launcher поверх shell, как `assistant-sheet` на вебе)

## Критерии успеха

- **SC-001**: Все 5 вкладок переключаются без потери состояния sync.
- **SC-002**: Double-tap Discover/Recipes с вложенного экрана возвращает к корню.
- **SC-003**: VoiceOver объявляет вкладки и selected state.

## Артефакты

- `quickstart.md` — сравнение с веб в 390px viewport