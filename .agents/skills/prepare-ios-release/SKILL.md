---
name: prepare-ios-release
description: >-
  Черновик What's New для App Store и отдельный DRAFT in-app ноты (спека 077):
  собирает коммиты с последнего тега ios/* и предлагает два разных текста.
  Триггеры: /prepare-ios-release, «что вошло в следующий релиз», «подготовь
  release notes для App Store», «собери изменения с прошлого релиза»,
  «in-app release notes».
---

# Prepare iOS Release (recipe-scaler-native)

Собрать список изменений с последнего iOS-релиза и подготовить **два** DRAFT:

1. What's New для App Store Connect.
2. In-app нота для каталога `IOSReleaseNotesCatalog` (spec 077).

Это разные тексты даже про один релиз. Финальный текст пишет пользователь —
агент только структурирует сырьё. In-app ноту **не класть в каталог** без явной
проверки человеком.

Редполитика: skill `redpolitika`. Тон: новость для человека, «вы», возможность
не команда; не писать «What's New», «для App Store», «веб-баннер».

## Workflow

1. Запустить сборщик:
   ```bash
   bash scripts/collect-ios-release-changes.sh --out store/drafts/next-release.md
   ```
   Если тегов `ios/*` нет — предложить bootstrap (`mark-ios-release.sh <X.Y.Z> --commit <sha>`) и остановиться.
2. Прочитать `store/drafts/next-release.md` и последнюю запись в `store/releases.yaml` (контекст: что уже вышло).
3. Показать пользователю **два блока**, оба пометить **DRAFT — проверьте перед публикацией / перед каталогом**:
   - группированный digest из черновика;
   - **What's New (стор):** 3–5 bullet points (ru; en по просьбе) — короткие пользовательские выгоды, без хешей/scope;
   - **In-app нота (приложение):** `title` + `body` для `ru` и `en`, plain text без HTML. Только то, что появилось **в iOS-приложении**. Пустой title/body не предлагать.
4. Спросить явно, класть ли in-app ноту в `RecipeScalerNative/Services/IOSReleaseNotesCatalog.swift` с `version` = max(текущий)+1 и датой релиза. Без «да, в каталог» — **не коммитить и не править каталог**.
5. Напомнить фиксацию после публикации новой версии в ASC:
   ```bash
   bash scripts/mark-ios-release.sh <X.Y.Z> [--notes-file store/drafts/whats-new-<X.Y.Z>.txt]
   git push origin ios/<X.Y.Z>
   ```

## Ограничения

- Не коммитить и не пушить без явной просьбы.
- Не публиковать ничего в App Store Connect API (вне scope).
- Не переписывать историю и не двигать существующие теги.
- Хром UI (метка баннера, sheet) живёт в `Localizable.xcstrings`, не в каталоге нот.
- Каталог — не веб-релизноты и не What’s New стора.
