# Tasks: DocumentManager readers extraction (#037)

Чек-лист для sequential execution.

- [x] T1. Создать `specs/037-documentmanager-readers-extraction/` (spec.md, plan.md, tasks.md)
- [ ] T2. Создать `RecipeScalerNative/Services/YjsSync/RecipeYjsCodec.swift` со всеми 13 static func + `SearchIngredientProjection` struct
- [ ] T3. Зарегистрировать `RecipeYjsCodec.swift` в `RecipeScalerNative.xcodeproj/project.pbxproj`
- [ ] T4. Схлопнуть `RecipeReader.swift`: переиспользует `RecipeYjsCodec`, `preferArray: true` для readIngredients
- [ ] T5. Переключить 6 call-сайтов в `DocumentManager.swift` на `RecipeYjsCodec.*` (L212, L257, L321, L332, L554, L700)
- [ ] T6. Удалить 13 приватных парсеров из `DocumentManager.swift` (включая `SearchIngredientProjection`)
- [ ] T7. `xcodebuild build` зелёный (через `docs/AGENT-WORKFLOW.md`)
- [ ] T8. `xcodebuild test` зелёный
- [ ] T9. Если падает — `.agents/skills/fix-until-green/SKILL.md` loop
- [ ] T10. Commit в `master`
- [ ] T11. Закрыть Linear MIK-177/178/180/181
