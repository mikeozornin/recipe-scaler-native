# Plan template (compatibility pointer)

Канонический шаблон плана для новых фич:

[`.specify/templates/overrides/plan-template.md`](../../.specify/templates/overrides/plan-template.md)

Скопируй override в `specs/<feature>/plan.md` и заполни. Обязательные секции
включают **Границы**, **Конституционная проверка**, **Downstream consumers**,
**Positive invariants**, **Async lifecycle**, **Teardown / resource inventory**,
**Verification**.

Исторические планы под `specs/*/plan.md` не требуют массовой миграции.
Validator `scripts/verify-plan-policy.py` применяется к новым/изменённым планам.
