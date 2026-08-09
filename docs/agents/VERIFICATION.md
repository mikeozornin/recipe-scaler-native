# Verification contract

Status: normative
Applies when: пишешь или меняешь `scripts/verify-*.sh`, layout audit, E2E runner,
`test-fast.sh`, quarantine, или доказываешь `VERIFIED` в плане.
Canonical source: этот файл + `scripts/verify-*.sh` + `docs/TESTING.md`.
Owner: tooling (recipe-scaler-native).
Last verified: 2026-08-09.

## Verdict vocabulary

- `CHECKED` — статический contract (наличие файла/структуры/manifest) выполнен.
- `VERIFIED` — свежий behavioral assertion выполнен.
- `INCONCLUSIVE` — среда не позволила проверить claim (нет симулятора, нет
  device, отсутствует backend). Не равносильно `VERIFIED`.
- `FAILED` — assertion нарушен.

Использовать ровно эти слова. «Success» без вида evidence запрещён.

## Что не считается проверкой

(Перекликается с `docs/TESTING.md` §5, но повторено как executable contract.)

- `xcodebuild build` зелёный → это компиляция, не поведение.
- Screenshot без assertion → артефакт для триажа.
- `rg -q '<Symbol>'` → наличие строки, не поведение.
- Stale `.app` или `VERIFY_SKIP_BUILD=1` без matching build manifest → не
  доказывает, что проверялся текущий changeset.
- Запуск с нулевым числом выполненных тестов → всегда `FAILED`.
- Массовый `XCTSkip` без skip budget → `FAILED`.

## Behavioral assertion contract

Каждый `verify-*.sh` обязан:

1. Не глотать exit code: `xcodebuild … | rg … || true` запрещено; `set -o
   pipefail` + проверка `PIPESTATUS`.
2. Иметь хотя бы один runtime/marker/assertion check после запуска приложения.
3. Падать при отсутствии readiness marker (timeout != success).
4. Использовать `resolve-simulator.sh` вместо захардкоженного UDID.
5. Завершаться `VERIFIED …` только после behavioral assertion.

## Build freshness

Reuse через `VERIFY_SKIP_BUILD=1` принимается только при совпадении
content-aware manifest (см. `sim-verify-lib.sh::sim_build_manifest_matches`).
Manifest покрывает Swift-файлы, ресурсы, `project.pbxproj`, `.xcstrings`,
entitlements, plist, extension targets, `Package.resolved`, Xcode version и SDK.
Изменение любого входа → rebuild.

## Verifier self-tests

- `scripts/tests/test-sim-verify-lib.sh` — readiness timeout + marker
  accept/reject.
- `scripts/tests/test-verify-all-lock.sh` — portable atomic-directory lock.

Новый verifier-скрипт обязан добавить fixture-тест, который доказывает, что
скрипт падает на сломанной среде/входе.

## Layout audit

(Подробности в `docs/UI-LAYOUT-FROM-FIGMA.md` и `split-layout-verdicts` slice.)

- Static audit ≠ human acceptance.
- Verdicts: `STATIC PASS`, `ACCEPTANCE PENDING`, `VERIFIED`.
- Manual claim без `reviewer`, `verifiedAt`, `evidencePath` → не `VERIFIED`.
- Изменение hash `layout.md` инвалидирует старую acceptance.

## E2E

- Loopback/controlled backend: register/seed failure → hard failure.
- Prod exploratory: skips допустимы только по reason code и в пределах budget
  (`scripts/e2e-skip-budget.json`).
- Suite с `executed == 0` или `all skipped` всегда красный.
- Менять E2E/`RecipeScalerNativeUITests` только ради зелёного теста — отдельное
  подтверждение пользователя.

## Quarantine

Исключённые тесты (например, `SnapshotTests`) оформляются как bounded
quarantine с owner, reason, expiry/removal condition. Бессрочные suppressions
запрещены; quarantine с истёкшим expiry красный.
