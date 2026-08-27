---
name: prepare-ios-release
description: >-
  Черновик What's New / internal digest для следующего App Store релиза:
  собирает коммиты с последнего тега ios/* и предлагает DRAFT-вариант текста.
  Триггеры: /prepare-ios-release, «что вошло в следующий релиз», «подготовь
  release notes для App Store», «собери изменения с прошлого релиза».
---

# Prepare iOS Release (recipe-scaler-native)

Собрать список изменений с последнего iOS-релиза и подготовить DRAFT
What's New для App Store Connect. Финальный маркетинговый текст пишет
пользователь — агент только структурирует сырьё.

## Workflow

1. Запустить сборщик:
   ```bash
   bash scripts/collect-ios-release-changes.sh --out store/drafts/next-release.md
   ```
   Если тегов `ios/*` нет — предложить bootstrap (`mark-ios-release.sh <X.Y.Z> --commit <sha>`) и остановиться.
2. Прочитать `store/drafts/next-release.md` и последнюю запись в `store/releases.yaml` (контекст: что уже вышло).
3. Показать пользователю:
   - группированный digest из черновика;
   - предложение **3–5 bullet points** для What's New ( ru, тон web release notes — короткие пользовательские выгоды, без хешей/scope) — обязательно пометить как **DRAFT — проверьте перед публикацией**;
   - опционально EN-версию, если попросит.
4. Напомнить фиксацию после публикации новой версии в ASC:
   ```bash
   bash scripts/mark-ios-release.sh <X.Y.Z> [--notes-file store/drafts/whats-new-<X.Y.Z>.txt]
   git push origin ios/<X.Y.Z>
   ```

## Ограничения

- Не коммитить и не пушить без явной просьбы.
- Не публиковать ничего в App Store Connect API (вне scope).
- Не переписывать историю и не двигать существующие теги.
- Строки UI-текста не генерировать здесь — если нужен новый in-app текст,
  он идёт через `Localizable.xcstrings` отдельной задачей.
