# План: watchOS Companion — Timers v1

**Spec**: [spec.md](./spec.md)
**Линейная задача**: [MIK-184](https://linear.app/mikeozornin/issue/MIK-184/watchos-companion-app-prosmotr-tajmerov-i-pauseresume)

## Порядок реализации

1. **Spec Kit setup** — артефакты создаются по мере выполнения задач.
2. **Layout** — [layout.md](./layout.md), аудит: `bash scripts/audit-ui-layout.sh specs/039-watchos-timers`.
3. **Core refactor #1** — вынести `ServerActiveTimer` + Codables в Core.
4. **Core refactor #2** — вынести view-примитивы в `RecipeScalerCore/TimerViews/`.
5. **watchOS target** — создать `RecipeScalerNativeWatch`.
6. **iOS bridge** — `WatchCredentialsBridge` + wire-up в `AuthService`.
7. **watch creds** — `WatchCredentialsStore` + `WatchCredentialsBridge` на watchOS.
8. **watch service** — `WatchTimerService` (refresh, pause, resume, delete).
9. **watch haptics** — `WatchHaptics`.
10. **watch UI** — `TimerListView` + state views + SettingsRow.
11. **i18n** — `watch.timer.*` ключи в `Localizable.xcstrings`.
12. **Layout audit** — `audit-ui-layout.sh` + layout-reviewer subagent.
13. **Manual QA** — paired simulator.
14. **Финал** — build green для обоих таргетов, коммит, закрыть MIK-184.

Полное содержание плана и дизайнерские решения — в [управляемом плане](../../../.cursor/plans/watchos_timers_v1_31856632.plan.md) (рабочий документ агента).
