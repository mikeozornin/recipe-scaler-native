# План: коллекции рецептов (026)

Зеркало рабочего плана Cursor: `.cursor/plans/native_collections_parity_59a77fdc.plan.md`  
Интеграционный гайд: [NATIVE_APP_COLLECTIONS.md](../../recipe-scaler-web/llm/NATIVE_APP_COLLECTIONS.md)

## Статус шагов

| Шаг | Содержание | Статус |
|-----|------------|--------|
| 0 | Spec Kit + YJS-SCHEMA + README + verify script (скелет) | ✅ |
| 1 | Swift модели и утилиты (порт shared) | ✅ |
| 2 | DocumentManager / YjsSyncService folders + folderIds | ✅ |
| 3 | ViewModel + UserDefaults view mode | ✅ |
| 4 | RecipesRoute, навигация, новые views | ✅ |
| 5 | UI parity §8 (toggle, sheets, swipe, detail menu) | 🟡 US9 pin side |
| 6 | i18n `collections.*` | ✅ |
| 7 | Тесты + verify-recipe-collections.sh (полный) | ✅ |

## Зависимости между шагами

```mermaid
flowchart LR
  s0[0_SpecKit]
  s1[1_ModelsUtils]
  s2[2_Yjs]
  s3[3_ViewModel]
  s4[4_Navigation]
  s5[5_UI]
  s6[6_i18n]
  s7[7_Verify]
  s0 --> s1
  s1 --> s2
  s2 --> s3
  s3 --> s4
  s4 --> s5
  s6 --> s5
  s5 --> s7
  s2 --> s7
```

## Реализация по шагам (кратко)

Визуальные референсы (веб): `recipe-scaler-web/llm/assets/native-collections/` — полная таблица в [quickstart.md](quickstart.md); assign из детали: `10-recipe-header-collections.png`, `11-recipe-assign-from-header.png`.

См. полный текст в Cursor plan §1–7. Критический claim верификации:

После sync с веб-аккаунтом с папками iOS показывает те же папки/счётчики; create/assign на iOS виден на вебе; pin/delete не удаляет `folderIds`.