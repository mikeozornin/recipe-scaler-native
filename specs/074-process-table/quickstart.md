# Quickstart: 074 process-table

Не писать SwiftUI экраны, пока [layout.md](./layout.md) не принят человеком.

## Decode / hash (можно до layout review)

1. Порт канона из [contracts/source-hash.md](./contracts/source-hash.md).
2. Fixture Y.Doc: валидный JSON v1 в `processTable` → decode.
3. Битая строка → UI как без ключа, ключ в map после `updateIngredient`.
4. Сверить hex с `computeProcessTableSourceHash` на той же паре ingredients/steps.

## После human review layout

1. `ProcessTableLayout.swift` + примитивы + `#Preview` на stub из layout.md (merge, wrap, 8 колонок).
2. CTA в строке заголовка шагов → `fullScreenCover` + системный landscape.
3. `bash scripts/audit-ui-layout.sh specs/074-process-table`
4. `bash scripts/lint-i18n.sh`
5. Build по [docs/AGENT-WORKFLOW.md](../../docs/AGENT-WORKFLOW.md).

## Ручная кухня

- Portrait iPhone: тап CTA справа от шагов → системный landscape; Close → карточка portrait. Поворот телефона вертикально готовку не закрывает.
- iPad: без forced rotate.
- Owner online: испортить amount → stale в готовке → rebuild.
