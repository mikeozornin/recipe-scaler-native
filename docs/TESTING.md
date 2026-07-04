# Testing: principles

Контекст для coding agents и ревьюеров. Дополняет [AGENT-WORKFLOW.md](./AGENT-WORKFLOW.md)
(процесс сборки/verify-циклов) и `specs/_template/plan.md` (секции
*Downstream consumers* и *Positive invariants*).

---

## 1. Positive invariant vs negative test

**Источник правила:** постмортем инцидента MIK-187 (22 Jun 2026).
`refreshPanelTimers()` делал две вещи — reassign `activeTimers` (для панели) и
`WidgetCenter.reloadTimelines` (cross-process виджет). Имя функции описывало
только первый эффект. Regression-тесты MIK-187 проверяли **отсутствие**
нежелательного поведения (мутация `remainingTime`, reassign `activeTimers`) —
но не проверяли **наличие** нужного. Удаление «лишнего» эффекта прошло сквозь
тесты незамеченным, регрессию поймал только ручной QA виджета через 51 минуту.

### Правило

Для каждого **observable** эффекта функции/API/свойства в коде — хотя бы один
тест, формулирующий поведение через **ожидаемое действие**, не через
**отсутствие нежелательного**.

| ❌ Негативный тест | ✅ Positive invariant |
|-------------------|----------------------|
| «`refreshPanelTimers` не мутирует `remainingTime`» | «после `tickUpdateRunningTimers` значение `TimerSnapshotStore.load()` для running-таймера свежее, чем до тика» |
| «`bootstrap(userId:)` не крашит при nil Keychain» | «после `bootstrap(userId:)`, `AuthService.shared.userId` равен переданному UUID» |
| «`drainOfflineQueue` не удаляет строки сразу» | «после emit строки остаются в очереди до `handleSyncConfirmed`» |
| «вид `isLocalDataLoaded` не ломает render» | «до установки `isLocalDataLoaded=true` тело view показывает ProgressView, после — List» |

### Как выявить observable-эффект

Спроси себя для каждой функции/мутации, которую ты добавляешь или меняешь:

1. **Кто ещё читает это состояние?** См. секцию *Downstream consumers* в
   `plan.md` — каждый consumer это потенциальный invariant.
2. **Что должно произойти, если функция отработала правильно?** Это и есть
   positive invariant — наблюдаемое следствие, не просто «не упало».
3. **Можно ли убрать «лишний» код так, чтобы все негативные тесты остались
   зелёными?** Если да — ты пропустил invariant.

---

## 2. Downstream consumers в плане

Без перечисления всех потребителей состояния регрессии обязательны — мы их
уже получали. Список для каждого шага плана:

- **SwiftUI views** — кто `@Published` / `@State` / `@Environment`-читает.
- **Cross-process consumers** — виджеты, App/Share/Action extensions, watchOS,
  Live Activity.
- **Sync boundaries** — Yjs/CRDT-потребители на web и других платформах.
  Отправляется ли значение на сервер.
- **Persisted state** — SwiftData / UserDefaults / App Group / Keychain.
- **Tests / verify-*.sh** — что обновлять.

Если хотя бы в одной категории есть consumer — добавь для него invariant.

---

## 3. Уровни тестов (что где проверять)

| Уровень | Что проверять | Инструмент |
|---------|--------------|------------|
| **Unit** | Изолированная логика: парсеры, мапперы, локализаторы, pure-функции | `xcodebuild test -only-testing:...` |
| **Integration** | Связка 2–3 сервисов с mock-границами (sync + offline-queue, auth + bootstrap) | XCTest с in-memory mock-ами |
| **Smoke** | app запустилась, дошла до shell, не упала, нет empty flicker | `bash scripts/verify-ui-smoke.sh` |
| **Feature parity** | конкретная фича работает end-to-end на симуляторе | `bash scripts/verify-<feature>.sh` |
| **Manual QA** | UX-нюансы, которых не покрывают тесты (физический iPhone, реальный аккаунт) | человек |

**Правило:** каждый класс регрессий, пойманный на уровне N+1, требует нового
теста на уровне N — иначе он повторится.

---

## 4. DEBUG-конфиг и edge-cases

Несколько инцидентов (auth divergence, `AppTypography` FatalError, `Int(amountValue)` trap)
вылезли потому, что тесты покрывали happy-path Release-сценарий, а баг сидел в
DEBUG-ветке или в edge-case (Double за пределами Int64, nil-unwrapping).

Обязательные тесты:

- **DEBUG auto-login** — после `bootstrap(userId: debugId)` состояние консистентно:
  `AuthService.shared.userId != nil`, sync видит тот же UUID, что и UI.
- **Clamping для Double→Int** — никогда не использовать `Int(doubleValue)` напрямую;
  только `Int(clamping: Int64(doubleValue))`. Тест на Double за пределами Int64.
- **`!` в view-коде** — запрещено вне `#Preview` / тестов. Линтер на `!` после
  optional-выражения — в планах (MIK-188 контейнер).
- **Empty / nil / 0 / very-long** — для каждой view-фичи проверять матрицу
  состояний из `layout.md`.

---

## 5. Что НЕ считать тестом

- **«`xcodebuild build` зелёный»** — это компилируется, не работает.
- **Скриншот без assertion** — пиксель не доказывает поведение. Скриншот в
  verify-*.sh — артефакт для триажа, не pass-criterion.
- **`rg -q '<ComponentName>'`** — проверяет наличие символа в коде, не его
  поведение. Постмортем MIK-187 явно указал на этот anti-pattern.
- **«работает у меня»** — для UX-багов на физическом iPhone валиден только
  ручной QA; для всего остального должен быть тест или verify-скрипт.

---

## 6. Postmortem-дисциплина

Любая регрессия, дошедшая до пользователя (или до `master`), получает
postmortem в `specs/<feature>/` или `docs/DECISIONS.md`. Минимум:

- **Симптом** — что увидел пользователь / QA.
- **Корневая причина** — не «забыли», а какая системная дыра пропустила баг.
- **Какие слои защиты сработали / не сработали** — unit / integration / smoke /
  verify-*.sh / manual.
- **Конкретные invariants и тесты, добавленные в ответ**.

Эталонный постмортем — MIK-187 (widget regression, `specs/030-timer-widget/`).
