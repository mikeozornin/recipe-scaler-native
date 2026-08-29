# Задачи: иллюстрации ингредиентов на iOS

Чеклист по [plan.md](./plan.md).

**P1 закрыт** (2026-07-03, `30552e7`). Ниже — итоговый статус.

## Spec Kit

- [x] `spec.md`
- [x] `plan.md`
- [x] `tasks.md`
- [x] `contracts/yjs-ingredient-illustration.md`
- [x] `contracts/ingredient-grid-thumb.md`
- [~] `layout.md` / `layout-audit.json` / ревью — **waived** (UI принят вручную)

## Фаза 1 — Sync, Core, Yjs — done

- [x] `scripts/sync-ingredient-illustrations.mjs`
- [x] `ingredient-catalog.json` + manifest + JPEG в app bundle
- [ ] `sync --check` для CI (опционально, follow-up)
- [x] Core catalog, search, matcher, layout metrics
- [x] Yjs read/write + partial bindings + tests

## Фаза 2 — Thumb + сетка — done

- [x] Image store, Bowl, thumb, slot 40 pt, view/edit grid, i18n, verify

## Фаза 3 — Picker + lazy-resolve — done

- [x] Picker sheet, edit wiring, lazy-resolve, binding tests, simulator

## Фаза 4 — Docs — done

- [x] `docs/ARCHITECTURE.md`

## Фаза 5 — P2 — done

- [x] Discover — read-only thumbs (via shared `YDocIngredientsSection`)
- [x] Shopping — thumb в строке + copy `illustrationId` при add-from-recipe + label fallback