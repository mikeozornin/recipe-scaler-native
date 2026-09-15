# Quickstart: 077 iOS release notes

1. Собрать Debug на симуляторе. Каталог 077 пустой → баннера нет, в Профиле нет строки новостей.
2. Unit: `ReleaseNotesStoreTests` с инжектом каталога 1…4.
3. QA баннера: в тесте или DEBUG подставить catalog max > lastViewed.
4. Перед следующим App Store-релизом: `/prepare-ios-release` → DRAFT in-app (ru+en) отдельно от What’s New; человек проверяет; агент добавляет `IOSReleaseNote` в каталог только после явного «клади в каталог».
