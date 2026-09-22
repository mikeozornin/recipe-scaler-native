# Contract: scroll delta ±75%

**Owner**: `AwakeScrollEngine`  
**Consumers**: `AwakeScrollController` (единственный writer offset)

## Формула

```text
delta = fraction * boundsHeight
fraction = 0.75

maxOffset = max(-adjustedInsetTop, contentHeight - boundsHeight + adjustedInsetBottom)
minOffset = -adjustedInsetTop

up:   y' = max(minOffset, y - delta)
down: y' = min(maxOffset, y + delta)
```

`y` — `contentOffset.y`.

Если `boundsHeight <= 0` → `y' = y`.

## Анимация

`scrollView.setContentOffset(CGPoint(x: contentOffset.x, y: y'), animated: true)`  
Не менять `x`. Не вызывать, если `abs(y' - y) < 0.5`.

## Источник ScrollView

Только `DetailScrollViewProbe.host`. Запрещено считать Hands-free успешным через nested `WKWebView.scrollView`.

## Тесты

Фикстуры без UIKit: struct чисел. `400 / 0 / 0 / 0 / 0` + down → `300`.  
Контент `500`, bounds `400` → maxOffset `100`; down с `0` → `100` не `300`.  
С top inset `88` и bottom `34` maxOffset = `500 - 400 + 34` = `134`, **без** прибавления top (иначе жест уезжает ниже пальцевого края).
