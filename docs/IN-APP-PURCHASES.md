# Локализация покупок поддержки

Метаданные продуктов задаются в App Store Connect, а не в
`Localizable.xcstrings`. В строках подменю `AccountTipsView` показываются
локализованные `Product.displayName` и `Product.displayPrice`; описание продукта
остаётся метаданными StoreKit и не повторяется в списке.

В профиле отображается пункт `Send a tip`. Внутри него идут две секции:
`One-time tips` ($1, $2, $5, $10) и `Monthly` ($1).

## Продукты

| Product ID | Тип | Цена | English — Display Name | Русский — Название |
| --- | --- | ---: | --- | --- |
| `ru.recipescaler.tip.1` | Consumable | $1 | Espresso | Эспрессо |
| `ru.recipescaler.tip.2` | Consumable | $2 | Double espresso | Двойной эспрессо |
| `ru.recipescaler.tip.5` | Consumable | $5 | Specialty v60 cup | V60 |
| `ru.recipescaler.tip.10` | Consumable | $10 | Coffee and cheesecake pie | Кофе и чизкейк |
| `ru.recipescaler.support.monthly` | Auto-renewable subscription | $1/month | Regular tip | Регулярная поддержка |

### Описания

Для четырёх разовых продуктов:

- English: `A one-time tip to support Recipe Scaler`
- Русский: `Чаевые в поддержку Recipe Scaler`

Для подписки:

- English: `Support Recipe Scaler every month`
- Русский: `Поддерживать Recipe Scaler каждый месяц`

Цена и период подписки отображаются StoreKit в формате текущей витрины App
Store. После сохранения локализаций продуктам нужно дать время появиться в
Sandbox.
