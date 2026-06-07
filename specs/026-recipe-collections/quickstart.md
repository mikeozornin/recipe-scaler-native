# Quickstart: коллекции рецептов (026)

## Автоматическая проверка

Создать `scripts/verify-recipe-collections.sh` (копия логики `verify-collection-mutations.sh` + проверка spec-файлов; `rg` на символы 026 — после шагов 1–2). Добавить в `scripts/verify-all.sh` строку `verify-recipe-collections.sh`.

```bash
chmod +x scripts/verify-recipe-collections.sh
./scripts/verify-recipe-collections.sh
```

Шаблон тела скрипта:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"
SHOT_DIR="$ROOT/specs/026-recipe-collections/screenshots"
mkdir -p "$SHOT_DIR"
test -f "$ROOT/specs/026-recipe-collections/spec.md"
test -f "$ROOT/specs/026-recipe-collections/contracts/collection-folders-yjs.md"
sim_build >/dev/null
sim_prepare && sim_install && sim_launch -SkipSplash=1
sim_wait_ready 6
sim_screenshot "$SHOT_DIR" "recipe-collections"
echo "VERIFIED recipe-collections"
```

Ожидание: успешный `xcodebuild`, симулятор, `VERIFIED recipe-collections`.

## Ручные проверки (full parity)

Предпочтительно один аккаунт с вебом (`recipe-scaler.ru`) или симулятор + веб в браузере.

1. **View toggle** — «По коллекциям» по умолчанию; переключение на «Все рецепты» сохраняется после перезапуска приложения.
2. **Синк с веба** — папки и счётчики совпадают ≤ 5 с после открытия списка.
3. **Drill-in** — тап в пользовательскую коллекцию; pin-секции; пустое состояние для пустой папки.
4. **Новая коллекция** — inline на корне; Enter/ blur с именем создаёт строку на вебе.
5. **Assign** — свайп «Коллекции» или меню рецепта → чекбоксы → Готово; membership на вебе.
6. **Manage** — меню папки «Выбрать рецепты» → toggle membership.
7. **Delete folder** — confirm; рецепты остаются, пропадают из папки на вебе.
8. **Поиск** — в режиме коллекций при вводе запроса показывается плоский список.
9. **Do-no-harm** — pin/unpin рецепта в коллекции не снимает его из папок (проверить на рецепте с `folderIds` с веба).
10. **Офлайн** — создать папку / assign в airplane mode → reconnect → веб ≤ 10 с.

## Скриншоты-референсы (веб)

`recipe-scaler-web/llm/assets/native-collections/` — [гайд §14](../../recipe-scaler-web/llm/NATIVE_APP_COLLECTIONS.md#14-screenshot-appendix).

| Файл | Сцена |
|------|--------|
| `01-view-toggle-collections-root.png` | Корень «По коллекциям» |
| `02-view-toggle-flat.png` | «Все рецепты» |
| `03-folder-drill-in.png` | Пользовательская коллекция |
| `04-folder-menu.png` | Меню ⋮ папки |
| `05-manage-recipes-sheet.png` | Выбрать рецепты |
| `06-assign-sheet.png` | Assign (список / свайп) |
| `07-swipe-collections-action.png` | Свайп «Коллекции» |
| `08-search-flat-fallback.png` | Поиск → flat |
| `09-delete-collection-confirm.png` | Удаление коллекции |
| `10-recipe-header-collections.png` | Деталь — пункт «Коллекции» в ⋮ |
| `11-recipe-assign-from-header.png` | Assign sheet из меню детали |

Ручная проверка US5/детали: открыть рецепт → ⋮ → «Коллекции» — UI как на `10` + `11`.

Локальные скриншоты iOS после verify: `specs/026-recipe-collections/screenshots/`.

## Ключевые символы (после реализации)

- `DocumentManager.readFolders` / `createFolder` / `renameFolder` / `deleteFolder` / `setRecipeFolders`
- `YjsSyncService` — `@Published folders`, мутации для UI
- `CollectionRecipesIndex.build`, `CollectionVirtualFolders`, `RecipeFolderRoutes`
- Views: `CollectionsRootView`, `CollectionFolderView`, `CollectionAssignSheet`, `ManageCollectionRecipesSheet`
- `RecipesRoute` в `RecipeListView`

## i18n

Все строки — ключи `collections.*` в `Localizable.xcstrings` (en/ru), см. гайд §11.