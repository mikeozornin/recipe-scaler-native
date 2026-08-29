---
name: fix-until-green
description: >-
  Agent loop для recipe-scaler-native: сформулировать falsifiable claim, чинить и проверять локально
  (build, тесты, существующие scripts/verify-*.sh, логи симулятора) до VERIFIED или лимита итераций.
  Триггеры: /fix-until-green, «дочини», «пока не работает», «чинить пока не заработает», «agent loop»,
  «сам проверь и доведи до конца». Не заменяет /debug для первичного root cause — комбинируй при багах.
---

# Fix until green (recipe-scaler-native)

Замыкает цикл «правка → проверка агентом → снова правка» без ожидания «проверь на телефоне», если проверку можно сделать на Mac.

## Когда включать

- Пользователь хочет **довести до рабочего состояния**, а не только «вот diff».
- После `/debug`, когда гипотеза подтверждена и нужен фикс + **подтверждение**.
- Рефакторинг/фича с явным критерием готовности.

Не включать для чисто консультаций («как устроено», «объясни») без изменений кода.

## Шаг 0 — Claim (обязательно, вслух в ответе)

Одна строка в формате:

```text
Claim: <когда> <что видно/измеримо> <порог>
```

Примеры:

- `Claim: после tap в title в edit mode клавиатура видна < 500 ms на симуляторе`
- `Claim: xcodebuild test RecipeScalerNativeTests/TitleSaveTests exit 0`
- `Claim: offline open recipe → ingredientCount ≥ 1 в debug-session.ndjson после loadRecipe`

Без claim — **INCONCLUSIVE**, не «готово».

## Шаг 1 — Baseline (если баг)

Перед правкой зафиксируй, **что сейчас ломается** (одна команда или один лог-фрагмент). Для регрессии после фикса — тот же способ измерения.

## Шаг 2 — Цикл (макс. 5 итераций)

На каждой итерации:

1. Минимальная правка под claim.
2. Прогон проверок снизу вверх — **остановись на первом полном подтверждении claim**:

| Уровень | Действие | Обязательность |
|--------|----------|----------------|
| L0 | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,id=<UDID>' build` | **всегда** |
| L0.5 | `bash scripts/audit-ui-layout.sh specs/<feature>` если есть `layout-audit.json` (Figma UI) | для UI по макету |
| L1 | `xcodebuild … test -only-testing:<Target/Class/method>` если тест есть под claim | если есть |
| L2 | `scripts/verify-<feature>.sh` **только если уже есть** в репо и покрывает область | опционально |
| L3 | Симулятор: NDJSON — `bash scripts/pull-app-logs.sh` или `sim_pull_debug_log`; grep по `message` / `category` | для UI/perf без XCTest |
| L4 | `/check-work` или субагент **layout-reviewer** (UI по `layout.md`) | UI-фичи после L0.5 |
| L5 | `/check-work` или субагент-ревью | только если L0–L4 зелёные, нужен второй взгляд |

3. Claim не выполнен → следующая итерация. После 5-й — **NOT VERIFIED** + что пробовали.

### Симулятор и журнал

В DEBUG журнал в файл **включён по умолчанию** (`AppLog`). Агент забирает лог сам:

```bash
source scripts/sim-verify-lib.sh
sim_build && sim_prepare && sim_install && sim_launch -SkipSplash=1
# … воспроизведение …
bash scripts/pull-app-logs.sh    # → .debug-session.ndjson
rg '"message":"your_event"' .debug-session.ndjson
```

`sim_launch` очищает старый `debug-session.ndjson` в sandbox перед запуском. Путь в sandbox: `Library/Application Support/debug-session.ndjson`. Переопределение на Mac (опционально): `SIMCTL_CHILD_AGENT_DEBUG_LOG=$PWD/.debug-session.ndjson` при `simctl launch`. Подробности — `llm/how-to-debug.md`.

Выключить запись в файл (редко): env `AGENT_DEBUG_LOG_DISABLED=1`.

### Физическое устройство

Агент **не** замыкает UI-loop на iPhone без твоего участия. Варианты: XCTest на симуляторе, или явный `INCONCLUSIVE` + что нужно с устройства.

### Про `scripts/verify-*.sh`

Это **не** требование писать новый скрипт на каждый баг. Это готовые сценарии в репо — запусти, если фича уже покрыта. Новый скрипт — только если одна и та же проверка будет повторяться много раз (команда/CI).

## Шаг 3 — Вердикт (обязательный финал)

```text
VERIFIED | NOT VERIFIED | INCONCLUSIVE
Claim: …

Evidence:
<команда или артефакт>: …

Reasoning:
<один абзац>
```

Правила:

- **VERIFIED** — claim выполнен, L0 зелёный, evidence воспроизводим.
- **NOT VERIFIED** — после лимита итераций claim не выполнен.
- **INCONCLUSIVE** — нет способа измерить на Mac (только device) или среда недоступна.

**Запрещено** при `NOT VERIFIED` / `INCONCLUSIVE` писать «готово», «fixed», «должно работать».

## Связка с другими skills

| Ситуация | Skill |
|----------|--------|
| Неясно почему ломается | `debug` — гипотезы, логи, фикс только по evidence |
| Нужен строгий шаблон evidence | `verify-this` |
| Нужен ревью diff после зелёного build | `check-work` |

Порядок для бага: **debug (root cause) → fix-until-green (довести claim до VERIFIED)**.

## AGENTS.md

- Сборка, web parity, offline — см. корневой `AGENTS.md` и [docs/AGENT-WORKFLOW.md](../../docs/AGENT-WORKFLOW.md).

## Пример вызова пользователя

```text
/fix-until-green title field: tap opens keyboard without 2s freeze on simulator
```

Агент: claim → правки → build → (test или ndjson grep) → VERIFIED или NOT VERIFIED.