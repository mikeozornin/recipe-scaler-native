# Quickstart: Share your feedback

**Spec**: [spec.md](./spec.md)
**Plan**: [plan.md](./plan.md)

## Где смотреть код после реализации

### Native

- `RecipeScalerNative/Views/AccountTipsSection.swift` — второй ряд секции.
- `RecipeScalerNative/Views/AccountFeedbackView.swift` — форма.
- `RecipeScalerNative/Services/AccountAPI.swift` — `submitFeedback`.
- `RecipeScalerCore/Networking/APIClient+Requests.swift` — multipart + text fields.
- `RecipeScalerNative/Views/TransientStatusBanner.swift` — `symbolName`.

### Server

- `recipe-scaler-web/server/src/routes/feedback.ts`
- `recipe-scaler-web/server/src/services/ops-alert.ts` — `sendOpsTelegramDocument`
- `recipe-scaler-web/server/src/__tests__/feedback-route.test.ts`

## Локальная проверка

```bash
# Server
cd ../recipe-scaler-web/server
npx vitest run src/__tests__/feedback-route.test.ts

# Native
cd ../../recipe-scaler-native
SIM_ID="$(bash scripts/resolve-simulator.sh)"
xcodebuild -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  build
bash scripts/lint-i18n.sh
```

### Ручной сценарий

1. Profile → секция Support Recipe Scaler → два пункта.
2. Share your feedback → ввести текст → Send.
3. Зелёный тост, поле пустое, экран не закрылся.
4. Attach → Photo Library и/или Files → имена в списке → Send.
5. Airplane mode → Send disabled.
6. Повторный Send сразу → сообщение подождать минуту.

Ops: в Telegram-чате модерации — текст с userId и вложения.
