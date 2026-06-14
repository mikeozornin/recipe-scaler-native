---
id: assistant-form-visual-fix
title: Fix assistant form visually
priority: high          # low | medium | high | critical
parallel: false           # true → may run alongside other parallel:true tasks
type: code                # code | research | mixed
---

# Task

В проекте есть Ассистент.
Нужно сделать его визуальную часть как в вебе.
Базовый план: .cursor/plans/assistant-full-021_89edd1fb.plan.md

## Context
https://www.figma.com/design/rVzFwMDS5SECfIq4HRLHya/Untitled?node-id=59-116&t=hBjVVQcYxKvFRkz9-4

Визуальные замечания по форме:
1. Поле ввода сообщения, кнопка отправки, кнопка аттачей выглядят без стиля, кнопка не такая, глянь как в вебе.

я собрал тебе скелет, это не pixel perfect макет
https://www.figma.com/design/rVzFwMDS5SECfIq4HRLHya/Untitled?node-id=59-116&t=hBjVVQcYxKvFRkz9-4

нужно обращать внимание: расположение кнопок, иконки, компоновка, подход к растягиванию
не нужно: конкретные кегли и размеры

## Acceptance criteria

- [ ] Поле ввода сообщения, кнопка отправки, кнопка аттачей и отправки войсов по компоновке совпадают с макетом
- [ ] Конкретные стили и размеры задаются как в приложении ios, а не вебе