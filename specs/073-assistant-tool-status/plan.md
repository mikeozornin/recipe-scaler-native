# План: Assistant tool-status UI — native

**Дата**: 2026-08-27  
**Спека**: [spec.md](./spec.md)  
**Канон**: [`recipe-scaler/specs/073-assistant-tool-status/`](../../../specs/073-assistant-tool-status/spec.md)

> Только native. Web — as-built, код не меняем.

## Задачи

1. **Model** — `AssistantToolStatus`, `metadata.toolStatus` (client-only), `AssistantMessage.optimisticToolStatus`
2. **Stream** — `consumeStream` `toolStart` insert/reorder; error clears all optimistic; remove `streamingToolStatusKey`
3. **UI** — `AssistantToolStatusRow.swift` (status + processing shimmer); branch in `AssistantSheet`
4. **i18n** — `AssistantToolStatusI18n` 1:1 web; `Localizable.xcstrings` keys
5. **Tests** — `AssistantToolStatusI18nTests.swift`
6. **Docs** — `docs/DECISIONS.md`; cross-ref in `021`, `072`

## Verification

- `xcodebuild`
- `bash scripts/lint-i18n.sh`
- Unit + manual simulator
