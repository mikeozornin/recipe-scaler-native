# AGENTS.md — контекст для coding agents

План и технологии: [specs/002-native-editing/plan.md](specs/002-native-editing/plan.md).

## Обязательно при старте

- **Сборка** — после Swift/Xcode правок агент сам прогоняет build (не проси пользователя). Команда и цикл проверок — [docs/AGENT-WORKFLOW.md](docs/AGENT-WORKFLOW.md).
- **Shell** — prefix с `rtk` ([docs/RTK.md](docs/RTK.md)).
- **i18n** — строки только в `RecipeScalerNative/Resources/Localizable.xcstrings`; не хардкодь текст в view; без fallback на дефолтные строки. Подробности — [docs/I18N.md](docs/I18N.md).
- **UI / UX** — `.appBody()` / `.appFootnote()`, web parity, паттерны экранов. Подробности — [docs/UI.md](docs/UI.md).
- **Spec Kit** — артефакты в `specs/<feature>/` на **русском** (`spec.md`, `plan.md`, …).

## Контекст проекта (кратко)

- Monorepo: native здесь, web — `../recipe-scaler-web`, API — `https://recipe-scaler.ru`.
- Offline-first; debug builds auto-login prod debug user.
- Recipes v1/v2 — read-only на iOS; v3 editing и миграция — только web.

## Документация по задаче

| Документ | Когда читать |
|----------|--------------|
| [docs/PROJECT.md](docs/PROJECT.md) | рецепты, sync, Reminders, collections, Spec Kit, платформа |
| [docs/I18N.md](docs/I18N.md) | runtime locale, свизл, navigationTitle, pluralization |
| [docs/UI.md](docs/UI.md) | типографика, HIG, web parity, паттерны экранов |
| [docs/AGENT-WORKFLOW.md](docs/AGENT-WORKFLOW.md) | fix-until-green, verify-скрипты, отладка |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | CRDT, yrs, sync layers |
| [docs/PAID-APPLE-DEVELOPER-REQUIRED.md](docs/PAID-APPLE-DEVELOPER-REQUIRED.md) | TestFlight, extensions, App Groups |
