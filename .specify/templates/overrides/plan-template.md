# План: <название фичи>

**Дата**: YYYY-MM-DD  
**Спека**: [spec.md](./spec.md)

> Канонический project template для Recipe Scaler Native. Артефакт пишется на
> русском. Для завершённых исторических планов обратная миграция не требуется.

## Границы

- **В scope**: …
- **Вне scope**: …
- **STOP conditions**: …

## Конституционная проверка

| Gate | Статус | Evidence / обоснование |
|------|--------|------------------------|
| CRDT-first | PASS / N/A | … |
| Web parity | PASS / N/A | … |
| Offline-first | PASS / N/A | … |
| Native UI | PASS / N/A | … |
| Phased delivery | PASS / N/A | … |
| i18n | PASS / N/A | … |
| Documentation | PASS / N/A | … |

## Очерёдность

1. **<шаг>** — почему первым; зависимости: …
2. …

## Изменения

| Файл | Действие | Почему |
|------|----------|--------|
| `…` | Создать / изменить / удалить | … |

## Downstream consumers

Перечисли всех потребителей изменяемого состояния/API. Если категория не
применима, напиши `N/A — причина`, а не оставляй секцию пустой.

- **SwiftUI views**: …
- **Cross-process**: widgets, extensions, watchOS, Live Activity, App Intents — …
- **Sync boundaries**: Yjs/CRDT, web, серверный contract — …
- **Persisted state**: SQLite, SwiftData, UserDefaults, App Group, Keychain — …
- **Tests / verify scripts**: …

## Positive invariants

| Observable effect | Положительный инвариант | Test/verifier ID |
|-------------------|-------------------------|------------------|
| `…` | После действия происходит `X` | `RecipeScalerNativeTests/…` или `verify-…:assert-…` |

Негативная формулировка «не должно сломаться» сама по себе недостаточна.

## Async lifecycle

Для каждого `Task`, callback, stream, continuation или queued operation,
содержащего suspension point или переживающего scope, заполни таблицу. Для
чистого синхронного шага укажи `N/A — нет async side effects`.

| Операция | Captured identity | Re-check после await | Cancellation owner | Stale completion test |
|----------|-------------------|---------------------|-------------------|-----------------------|
| `…` | session/epoch, user, resource/document | … | … | … |

Single-flight guard ставится до первого `await` и снимается через `defer`.

## Teardown / resource inventory

| Entry path | In-memory | Tasks/streams | Persisted state | Cross-process / OS surface | Positive postcondition |
|------------|-----------|---------------|-----------------|---------------------------|-------------------------|
| logout | … | … | … | … | … |
| account switch | … | … | … | … | … |
| stale session / cold start | … | … | … | … | … |
| reconnect / partial failure | … | … | … | … | … |

## Cross-target contracts

- **Canonical owner**: …
- **Writer/reader targets**: …
- **Validator/normalizer**: …
- **Raw literal exceptions**: только с reason/owner/expiry.

## Locale / theme consumers

- SwiftUI environment: …
- UIKit / notification categories / scheduled content: …
- Widgets / Live Activities / App Intents: …
- Cached or generated assets: …
- `.system` effective value: …

## Compatibility / migration

- Current format/contract: …
- Previous supported format: …
- Missing version/default behavior: …
- Unknown future version/ID behavior: …
- Required legacy fixture tests: …

## Unknown IDs and fallback policy

- DEBUG/CI: unknown scene/route/manifest/server code → hard failure.
- Release: safe user-facing state + structured log.
- Legacy aliases: explicit mapping in one adapter; prefix-based semantic fallback запрещён.

## Generated resources

| Resource | Manifest | Source output | Installed path | Built `.app`/`.appex` assertion |
|----------|----------|---------------|----------------|---------------------------------|
| `…` | … | … | … | … |

## Human gates

- [ ] `layout.md` reviewed by human, если задача Figma-driven.
- [ ] `layout-audit.json` static audit passed.
- [ ] Human acceptance artifact актуален для hash `layout.md`.
- [ ] Отдельный review-agent выполнен; self-review не считается заменой.

## Verification

- `bash scripts/verify-plan-state.sh` — …
- `xcodebuild … build` — …
- `xcodebuild … test` — …
- `bash scripts/verify-<feature>.sh` — …
- `bash scripts/lint-i18n.sh` — если применимо.
- Expected evidence and exit codes: …

## Rollback / maintenance

- Как откатить: …
- Что будет взаимодействовать с изменением в будущем: …
- Временные allowlist/quarantine: owner, reason, expiry/removal condition.
