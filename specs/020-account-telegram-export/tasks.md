# Задачи: 020 — Telegram и export/import файлов аккаунта

**Вход**: `/specs/020-account-telegram-export/`

**Аудит**: 2026-06-15.

## Формат: `[ID] [P?] [Story] Описание`

---

## Фаза 1: Telegram

- [x] T001 [US1] `TelegramConnectionView` + `TelegramAPI.connect` (выполнено в 013)
- [x] T002 [US2] `TelegramAPI.disconnect` + статус-poll (выполнено в 013)
- [x] T003 i18n `telegram.*` (выполнено в 013)

---

## Фаза 2: Account data section — placeholder

- [x] T004 [US3, US4] Заглушка `account.data.coming-soon` показывается в `AccountView.dataSection` (фикс 2026-06-15 — раскомментирован вызов `dataSection` в теле `AccountView.body`)
- [x] T005 Локализационный ключ `account.data.coming-soon` и `account.section.data` в `Localizable.xcstrings` (ru/en)

---

## Фаза 3: Export / Import — deferred (требует серверной реализации)

- [ ] T006 [US3] Export: проверить, отдаёт ли backend готовый `.zip` v1.3; если да — `ShareLink` + URL с токеном; если нет — собрать JSON из Y.Doc локально
- [ ] T007 [US4] Import: расширить `ImportRecipeSheet` (010) точкой входа из `AccountView.dataSection`; pipeline = `RecipeImportAPI.importText` / `ThirdPartyRecipeImportService`
- [ ] T008 [US5] Offline gate: дизейблить кнопки когда `viewModel.isOnline == false`
- [ ] T009 SC-002 / SC-003: quickstart — round-trip export на iOS → import на веб и наоборот

**Блокер**: backend endpoint для export ещё не закрыт — код-side сейчас только placeholder. Когда API появится, эти задачи тривиально закрываются поверх существующей инфраструктуры 010.
