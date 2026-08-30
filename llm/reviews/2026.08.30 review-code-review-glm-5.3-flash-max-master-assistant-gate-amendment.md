# Code Review: master (AssistantSheet offline gate amendment)

## Summary

Ревью незакоммиченных изменений: перевод UI-ветки `AssistantSheet` на debounced
`OfflineBannerGate` (`showsOnlineContent = !offlineGate.isVisible`) + amendment
спеки `specs/066-offline-banner-debounce/spec.md` (FR-009a). Root cause и мотивация:
мелькание полноэкранной оффлайн-заглушки при возврате из фона; device-evidence —
окно reconnect ~500мс, глубоко ниже порога 3с.

Области: **Business Logic** и **Architecture** — субагентом
(`[Review](638c81e9-3f66-4bd9-90ff-0663492fe3c4)`); **Standards** — субагентом
(`[Review](3741a624-0c18-4b40-b4a5-4c90a304ca9b)`). Security и Performance
пропущены: дифф не трогает пользовательский ввод/auth/секреты, из performance-
значимых операций только чтение одного observable-свойства.

ВсеFindings ниже отсортированы по приоритету; после написания отчёта findings
1–3 уже исправлены в рабочей копии, сборка перепроверена (BUILD SUCCEEDED).

## Findings (sorted by priority)

### Medium

1. **[standards]** Спека после amendment осталась внутренне противоречивой:
   SC-004 (`spec.md:222`) утверждал «`AssistantSheet` реагирует мгновенно как и
   раньше» — прямое противоречие FR-009a (`spec.md:158`). Плюс неамендированные
   «четыре status-баннера» в Целях (34), User Story 1/2 acceptance (81, 88,
   92, 96), SC-001..003 (219–221) и FR-012 без третьего i18n-ключа (161).
   - Impact: ложные провалы будущих `/verify-this` прогонов против критериев спеки.
   - Recommendation: заменить все упоминания на «пять», SC-004 переформулировать
     через «action-пути AssistantSheet», добавить `assistant.offline.description`
     во FR-012. → **Исправлено** (координатором после ревью).

### Low

2. **[architecture/doc]** Устаревший комментарий single-writer контракта в
   `AppShellView.swift:309–312`: «only status banners read `offlineGate`» +
   `AssistantSheet` в списке мгновенных feature-gating view. Противоречит коду
   и amended спеке.
   - Impact: documentation drift для будущих читателей.
   - Recommendation: обновить формулировку. → **Исправлено**.

3. **[standards]** Doc-комментарий `showsOnlineContent` 5 строк против локальной
   нормы 2–4; последняя строка пересказывала parking-механику `undeliveredPrompt`,
   уже задокументированную у поля и в `send()`.
   - Impact: маргинальная избыточность + drift-риск.
   - Recommendation: сократить до 3 строк, оставить spec-pointer + rationale +
     «action paths stay instant». → **Исправлено**.

4. **[standards]** Размещение computed между `isOnline` и блоком statics слегка
   фрагментирует порядок файла.
   - Impact: косметика.
   - Recommendation (optional): держать рядом с `isOnline`. → Фактически уже
     соответствует целевому состоянию (стоит сразу после `isOnline`); правка не
     требуется.

### Observation (below threshold)

5. Сheet-hosting caveat в `AppShellView.swift:253–255` говорит, что внешние
   environment-сервисы не propagate в sheet content (поэтому там явный
   `.environment(coordinator)`). `offlineGate` инжектится только root-ово через
   `.appEnvironment(container)`. Ревьюер оценил риск non-issue (~70% уверенности):
   `ShoppingListShareSheet` уже читает gate из sheet и работает в проде;
   эмпирически `.sheet` наследует environment всей цепочки. Страховка (опционально):
   разово убедиться, что оффлайн-заглушка ассистента (>3c авиарежим) рендерится
   без crash — покрыто существующим device-подтверждением пользователя («вроде норм»)
   и симуляторной проверкой реального офлайна из плана верификации. Действий не требует.

## Business Logic walkthrough (Approved)

- Окно «gate скрыт, реально офлайн» (первые 3с): `send()` паркует промпт в
  `undeliveredPrompt`, доставка после reconnect — потерь нет; bootstrap при
  `hasTriedSessionRestore == false` перезапускается на flip of `isOnline`.
- Окно «gate виден, соединение восстановилось»: структурно не может сохраняться —
  любой `.connected` форсит `update(false)` от единственного writer'а; stale-case
  возможен только пока shell `.inactive`, но тогда UI не виден, а на `.active`
  гейт корректится немедленно.
- Sheet поверх shell не гасит `onChange(connectionState/scenePhase)` на shell —
  подтверждено эмпирически на устройстве.
- E2E-селектор `assistant_offline_footnote` сохранён (изменится только момент
  появления).

## Verdict

**Approved** — код конформен, единственный blocking item был doc-only (SC-004 vs
FR-009a), исправлен вместе с двумя low сразу после ревью; rebuild зелёный.
Runtime-поведение ранее VERIFIED (build/test-fast/lint-i18n/симулятор/device).
