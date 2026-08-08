# Спецификация: коллекции рецептов (папки / теги)

**Ветка**: `026-recipe-collections`  
**Дата**: 2026-06-07  
**Статус**: 🟢 Реализовано (аудит 2026-06-15 — US9 закрыт: pin перенесён с leading на trailing)  
**Зависимости**: `008-collection-mutations` (индекс рецептов, pin/delete/create), `007-app-shell-navigation`  
**Эталон**: [NATIVE_APP_COLLECTIONS.md](../../recipe-scaler-web/llm/NATIVE_APP_COLLECTIONS.md), веб `recipe-list.tsx`, `collections-view.tsx`, `use-yjs-sync` (folder writes)

## Контракт отображения имени коллекции

`folders[].name` хранится и синхронизируется без изменений, включая ведущую
эмодзи. Native использует `RecipeTitleEmoji` и
`FolderDisplayName.presentation(forStoredName:)`, чтобы получить:

- `leadingEmoji` — отдельный marker для иконки строки, плитки и заголовка;
- `displayName` — имя без ведущей эмодзи или локализованный
  `recipes.no-title`, если после очистки имя пустое.

Пробелы перед ведущей эмодзи игнорируются; ZWJ-последовательности, флаги и
keycap считаются одним marker. Эмодзи внутри и в конце имени не удаляется.
Сортировка использует очищенное имя и затем `id`. Rename редактирует raw name,
поэтому сохранённая эмодзи не теряется.

## Аудит реализации (2026-06-15)

| Область | Статус |
|---------|--------|
| Yjs folders + `folderIds` | ✅ `DocumentManager`, `YjsSyncService` |
| UI: toggle, drill-in, sheets | ✅ `CollectionsRootView`, `CollectionFolderView`, assign/manage sheets |
| Поиск → flat fallback | ✅ `RecipeListView` |
| i18n `collections.*` + tests | ✅ |
| verify script | ✅ `scripts/verify-recipe-collections.sh` |
| US9 жесты (leading pin) | ✅ pin в **leading** группе рядом с cart + collections (фикс 2026-06-15 — `RecipeListView.swift` и `CollectionFolderView.swift`); trailing содержит только delete |

## Контекст

На вебе пользователь группирует рецепты в **коллекции** (many-to-many, один уровень вложенности). Данные живут в том же Y.Doc `{userId}:collection`: массив `folders` и опциональное поле `folderIds` на entry в `recipes`. Сервер не менялся — только CRDT passthrough и `collection_updated`.

iOS уже синхронизирует collection doc и пишет метаданные рецептов (008), но **не читает** `folders` / `folderIds` и показывает только плоский список.

## Цель

Full parity мобильного веба: режимы «По коллекциям» / «Все рецепты», drill-in в папку, назначение рецептов, управление составом коллекции, жесты и меню — с сохранением do-no-harm для старых билдов и веба.

## Пользовательские сценарии

### US1 — Переключение режима списка (P1)

**Когда** пользователь на вкладке «Рецепты», **тогда** в заголовке есть переключатель: плоский список (`collections.view-flat`) и «По коллекциям» (`collections.view-collections`). По умолчанию — коллекции. Выбор сохраняется на устройстве (`recipe-list-view-mode`).

### US2 — Корень коллекций (P1)

**Когда** режим «По коллекциям» и поиск пустой, **тогда** список показывает: виртуальную «Все рецепты», пользовательские коллекции (счётчик рецептов), виртуальную «Без коллекции», строку «Новая коллекция» (inline create). Тап по строке → drill-in.

### US3 — Drill-in в папку (P1)

**Когда** пользователь открывает папку (UUID, `all` или `uncategorized`), **тогда** список рецептов с теми же pin-секциями и сортировкой, что и flat; пустое состояние `collections.empty-folder`. Для пользовательской коллекции — меню ⋮: переименовать, выбрать рецепты, удалить коллекцию.

### US4 — Поиск (P1)

**Когда** в поле поиска есть непустой запрос (после trim), **тогда** всегда показывается **плоский** отфильтрованный список (глобальный поиск), независимо от режима и активной папки. Правила: токены AND, кавычки, NFKD (см. search rules в AGENTS.md).

### US5 — Назначение рецепта в коллекции (P1)

**Когда** пользователь открывает assign sheet (свайп «Коллекции», меню рецепта), **тогда** видит активные коллекции с чекбоксами, может создать коллекцию inline; «Готово» записывает полный набор `folderIds` для рецепта одной транзакцией.

- Список: гайд §8.9, референс `06-assign-sheet.png`, свайп `07-swipe-collections-action.png`.
- Деталь рецепта: §8.10 пункт «Коллекции» в ⋮ → тот же sheet (§8.11), референсы `10-recipe-header-collections.png`, `11-recipe-assign-from-header.png`.

### US6 — Управление составом коллекции (P1)

**Когда** из меню папки выбрано «Выбрать рецепты», **тогда** sheet с поиском по именам и чекбоксами membership только для активной папки; toggle меняет `folderIds` у соответствующего рецепта.

### US7 — CRUD коллекции (P1)

**Когда** пользователь создаёт / переименовывает / удаляет коллекцию, **тогда** изменения в `folders` Y.Array; удаление — soft-delete + снятие id со всех рецептов; рецепты не удаляются (диалог `collections.delete-confirm-*`).

### US8 — Навигация и контекст папки (P2)

**Когда** рецепт открыт из drill-in, **тогда** «Назад» возвращает в список папки, если `shouldUseFolderRecipePath` (порт `recipe-folder-routes.ts`). Deep link / Spotlight — без folder context.

### US9 — Жесты строки (P2)

**Паритет нативного UX**: leading swipe — cart (зелёный), collections (оранжевый), pin/unpin (синий); trailing swipe — удаление (красный).

### US10 — Офлайн (P1)

Мутации папок и `folderIds` в офлайне → очередь на doc `collection` (как 008).

### US11 — Оформление корня коллекций (P2, native-only)

**Когда** пользователь в режиме «По коллекциям» и поиск пустой, **тогда** корень может отображаться двумя способами: **список** или **сетка папок** (иконки `folder.fill` в цвете коллекции, 3 колонки; **по умолчанию**). Настройка — «Профиль → Отображение коллекций». Выбор сохраняется в `UserDefaults` (`recipe-collections-root-layout`), отдельно от `recipe-list-view-mode`. В обоих режимах: «Все рецепты» — полноширинная строка, «Без коллекции» — скрыта при пустом списке, inline create — после контента. При непустом поиске — flat list, независимо от layout. Web не затронут.

## Функциональные требования

### FR-026-001 — Do-No-Harm

- Не пересоздавать entry `Y.Map` целиком из struct с известными полями — иначе теряется `folderIds`.
- Не удалять top-level `folders`, не GC tombstones в `recipes` / `folders`.
- Создание рецепта (008) может не писать `folderIds` до первого назначения.

### FR-026-002 — Схема

См. [data-model.md](data-model.md), [contracts/collection-folders-yjs.md](contracts/collection-folders-yjs.md).

### FR-026-003 — Derived index

In-memory индекс как `buildCollectionRecipesIndex` (liveRecipes, uncategorized, countByFolder, folderRecipesById).

### FR-026-004 — CRDT

`folderIds` — last-write-wins на весь массив per recipe; `folders` — Y.Array merge + per-key LWW на map.

### FR-026-005 — i18n

Ключи `collections.*` и `recipes.no-title` для пустого имени папки — см. гайд §11; без хардкода в SwiftUI.

### FR-026-006 — Sync

Без новых REST; `collection_updated` как в [008 contracts](../008-collection-mutations/contracts/collection-sync.md).

### FR-026-007 — Collections root layout (native-only)

Корень коллекций поддерживает два layout: `list` и `folders` (LazyVGrid, 3 колонки; по умолчанию). Настройка хранится в `UserDefaults` по ключу `recipe-collections-root-layout` (тип `CollectionsRootLayout` в `RecipeFolderRoutes`). В сетке цвет плитки = `RecipeFolder.color`, отображается через `RecipeAccentColor`. Клавиатурный toolbar inline-create — в обоих layout.

## Вне scope

- Вложенные папки
- MCP/assistant tools на iOS (мутации с ассистента видны через тот же Y.Doc)
- Смена цвета коллекции в UI (если не на веб mobile — опционально позже)

## Критерии успеха

- **SC-026-001**: Папки, созданные на вебе, видны на iOS с теми же счётчиками после sync ≤ 5 с.
- **SC-026-002**: Create/assign/delete folder на iOS отражается на вебе ≤ 5 с.
- **SC-026-003**: Pin/delete рецепта на iOS **не** сбрасывает `folderIds` (unit + ручная проверка с веб-аккаунтом).
- **SC-026-004**: Поиск в режиме коллекций показывает flat fallback.
- **SC-026-005**: `./scripts/verify-recipe-collections.sh` → build + VERIFIED.

## Визуальные референсы (веб, mobile viewport)

Каталог: `recipe-scaler-web/llm/assets/native-collections/`. Полный список — [NATIVE_APP_COLLECTIONS.md](../../recipe-scaler-web/llm/NATIVE_APP_COLLECTIONS.md) §14.

| Файл | Сцена |
|------|--------|
| `01` … `09` | Корень, flat, drill-in, меню, manage/delete, поиск, свайп |
| `06-assign-sheet.png` | Assign sheet (из списка / свайпа) |
| `10-recipe-header-collections.png` | Деталь — ⋮ с пунктом «Коллекции» |
| `11-recipe-assign-from-header.png` | Assign sheet после «Коллекции» из меню детали |

Пересъёмка: `recipe-scaler/scripts/capture-native-collections-screenshots.mjs`.

## Артефакты

| Файл | Назначение |
|------|------------|
| [spec.md](spec.md) | Этот документ |
| [data-model.md](data-model.md) | Folder, folderIds, виртуальные id |
| [contracts/collection-folders-yjs.md](contracts/collection-folders-yjs.md) | Yjs writes |
| [quickstart.md](quickstart.md) | Ручная проверка |
| [plan.md](plan.md) | План реализации (зеркало Cursor plan) |