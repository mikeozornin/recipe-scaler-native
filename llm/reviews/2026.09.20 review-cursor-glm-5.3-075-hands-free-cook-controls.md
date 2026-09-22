# Code Review: 075-hands-free-cook-controls

- **Commit**: `8cc7f09` (единственный коммит поверх `master`, 45 файлов, +3692/−499)
- **Модель ревью**: GLM-5.3 (max) через Cursor, 5 параллельных субагентов
- **Зоны**: Security & Privacy, Business Logic, Architecture & Async Lifecycle, Performance, Standards
- **Пропущено**: ничего — изменение затрагивает все пять зон

## Summary

Фича структурно зрелая: composition root соблюден (без `.shared`), epoch-дисциплина и weak-captures в основных потоках чистые, scroll-математика и hand-классификатор соответствуют контрактам, i18n/типографика/логирование прошли механические проверки (`lint-i18n.sh`, `verify-translations.sh` — PASS).

Но мерж-блокерами стоят **1 critical + 4 high**:

1. **Каждое естественное моргание скроллит рецепт** (нет 100 мс окна подавления обоих глаз) — face-канал практически неиспользуем.
2. **Teardown-контракт нарушен на краях**: нет `deinit`-стопа ни у одного из трех владельцев + ранний `return` в `onDisappear` при открытом help sheet → камера/микрофон могут пережить UI (logout-ресет, deep-link, permission-await resurrection), `AVAudioSession` не деактивируется.
3. **Voice fire на нестабильных партиалах**: gate `action(from:isFinal:isStablePartial:)` существует, но продакшн-путь его обходит — вызывается только из тестов. Нарушение F3.3 / voice-whitelist fire policy.
4. **Суффиксный матчинг** вместо требуемого контрактом exact-match, и отклонение закреплено тестом (`"please scroll down"` → `.down`). «Calm down», «hands up» и любые фразы, заканчивающиеся на «вверх/вниз», скроллят.
5. **F8.3 dead end**: снапшот разрешений не пересчитывается после возврата из Settings (`refreshPermissions()` только при `.unknown`, нет `willEnterForeground`) — запрещенный канал остается навсегда disabled.

## Findings (sorted by priority)

### Critical

1. **[logic] Естественное моргание двумя глазами дает ложный скролл — нет 100 мс окна подавления**
   - `AwakeScrollFaceClassifier.swift:10-26` — контракт `gesture-mapping.md` требует «Оба глаза за один кадр / 100 ms → ignore», реализовано только same-frame (`if leftEdge && rightEdge { return nil }`). ARKit отдает якоря на ~60 Гц; естественное моргание пересекает порог 0.6 по глазам обычно в разных кадрах → `.up` срабатывает, потом `.down` (задавлен cooldown'ом, но UI пульсирует).
   - Impact: страница прыгает при каждом моргании в whatever direction — face-канал в кухонном контексте хуже отсутствия фичи. Тест `test_double_blink_ignore` покрывает только same-frame, баг невидим для сьюта.
   - Recommendation: хранить timestamp последнего edge по каждому глазу в `AwakeScrollBlinkState`; если оба глаза дали edge в пределах 100 мс — `nil` и сброс обоих. Тест: left edge в *t*, right edge в *t+50 мс* → `nil`.

### High

2. **[arch+logic] Teardown-контракт нарушен: нет `deinit`-стопа; `onDisappear` с открытым help sheet пропускает disarm**
   - `YDocRecipeDetailView.swift:658-662` — `if showingAwakeScrollHelp { return }` не отличает «шит поверх» от «вью реально ушло». `AwakeScrollController` / `AwakeScrollVoiceEngine` / `AwakeScrollCaptureSession` — ни одного `deinit` (проверено grep). Контракт `permission-teardown.md` требует stop на `deinit`; `data-model.md`: «Deinit view → stop».
   - Конкретные пути утечки: (a) programmatic navigation reset с открытым шитом — logout → `AppContainer.stopForLogout()` / deep-link замена роута: `flags.detailVisible` остается `true`, `stop()` не вызывается, `AVAudioSession` (`.playAndRecord`) никогда не деактивируется → индикатор микрофона висит; (b) permission-await resurrection: `startIfNeeded()` (`AwakeScrollController.swift:169-178`) держит strong self в `Task`, epoch не бампается на этом выходе → после grant'а `beginChannels` стартует mic/camera для несуществующего экрана.
   - Impact: камера/микрофон живут дольше UI — ровно тот класс регрессии, под который писан контракт; батарея + состояние общей `AVAudioSession`.
   - Recommendation: (1) nonisolated-safe `stop()` в `deinit` движков и контроллера; (2) вместо boolean-гарда — реальная проверка liveness (window presence) или безусловный `syncArmState()` в `onDisappear` + сброс `detailVisible` в `onDismiss` шита; (3) дать `stopForLogout()` добраться до фичи (weak registry / перенос ownership наверх).

3. **[logic+security] Voice: fire на нестабильных партиалах — gate обойден продакшн-путем**
   - `AwakeScrollVoiceEngine.swift:112-148` — `considerTranscript` принимает `isFinal`, но использует его только в логе; `match(normalized)` вызывается безусловно, `shouldReportPartialResults = true`. Gate `AwakeScrollVoiceClassifier.action(from:isFinal:isStablePartial:)` (реализующий fire policy контракта) вызывается **только из юнит-тестов** — мертвый код на продакшн-пути.
   - Impact: транзиентные партиалы ambient-речи матчатся («вверхние шаги» стримит партиал «вверх» → скролл до финализации слова). Прямое нарушение F3.3 и `voice-whitelist.md` («Partial: не fire. Stable partial ≥ 300 мс»). Dedup по `lastEmittedAction` не спасает — скролл уже произошел.
   - Recommendation: роутить через `action(from:isFinal:isStablePartial:)` как единственный owner gate; fire только на final либо stable-partial (нормализованный текст неизменен и whitelist-exact ≥ 300 мс). Engine-тест: матчинг-партиал один не эмитит.

4. **[logic+security] Voice: суффиксный матчинг вместо exact-match, закреплен тестом**
   - `AwakeScrollVoiceClassifier.swift:17-28` — после полного совпадения сканируются последние 1–3 токена (`tokens.suffix(n)`). `voice-whitelist.md:13`: «Prefix / contains match запрещён». Тест `AwakeScrollVoiceClassifierTests.swift:38-40` кодифицирует отклонение (`"please scroll down"` → `.down`), контракт в бранче не правился.
   - Impact: «put it down», «calm down», «sit down», «hands up», любые RU-фразы на «вверх/вниз» скроллят вооруженную сессию. Компаундится с находкой 3. Спека называла этот класс риска: «Ложные "up" из речи на кухне».
   - Recommendation: exact-match-only после нормализации; фикс теста на `nil`. Если tolerance ведущих слов — продукт-решение, сначала внести точное правило в `voice-whitelist.md` и тесты одним изменением.

5. **[logic] F8.3 dead end: снапшот разрешений не пересчитывается после возврата из Settings**
   - `AwakeScrollHelpSheet.swift:94-99` — refresh только `if controller.lastPermissions == .unknown`; после deny снапшот `.denied`-типа → повторный показ шита никогда не перечитывает. Других вызовов `refreshPermissions()` нет, `willEnterForeground`-обсервера нет нигде, хотя `data-model.md` его требует.
   - Impact: toggle → mic denied → snapped off + disabled; юзер grants в Settings, возвращается — шит еще открыт, `lastPermissions` все еще `micDenied`, тумблер disabled с оранжевым сабтитлом. Путь восстановления из спеки недостижим.
   - Recommendation: обсерверить `UIApplication.willEnterForegroundNotification` в контроллере (или шите) → `refreshPermissions()`; в `onAppear` шита refresh безусловно. Тест: granted-снапшот после `.denied` ре-енейблит тумблер.

6. **[standards] Help sheet без обязательного `AppSheetChrome` opaque-представления**
   - `AwakeScrollChromeModifier.swift:36-40` — новый большой лист (`AwakeScrollHelpSheet.swift`, 305 строк) нарушает правило sheet chrome из docs/UI.md.
   - Impact: непоследовательный визуал листьев приложения.
   - Recommendation: обернуть в `AppSheetChrome` по образцу остальных листов проекта.

### Medium

7. **[logic] `speechDenied` исключен из кнопки «Открыть параметры»; сабтитл врет**
   - `AwakeScrollArmFlags.swift:69-70` — `showsOpenSettings = micDenied || cameraDenied`; voice-канал требует mic + speech (F1.1), но speech в кнопке нет. `deniedKey` захардкожен в `denied.mic` (`AwakeScrollHelpSheet.swift:44`).
   - Impact: speech denied при granted mic → «доступ к микрофону запрещён» (ложь) + скрытая кнопка Settings → канал disabled без пути восстановления.
   - Recommendation: включить `speechDenied` в `showsOpenSettings`; выводить `denied.mic` vs speech-ключ по факту отказа.

8. **[logic] Рейсы старта: реконфигурация во время in-flight start молча дропается; `stop()` чистит чужой `isStarting`**
   - `AwakeScrollController.swift:127-177` — (1) при `isStarting == true` смена флагов не ресинкается после завершения старта → новый канал не стартует до следующего изменения; (2) `stop()` (строка 148) сбрасывает `isStarting` для еще живущего таска → возможен двойной `beginChannels` (двойные колбэки `onStartChannels`, churn движков; самолечение внутренними `stop()` маскирует).
   - Recommendation: после `beginChannels`/раннего выхода перезапускать `syncArmState()`; сделать `isStarting` epoch-тегированным или гарды `!channelsRunning`.

9. **[security] Строка обещает «on-device speech recognition», код молча допускает серверный fallback**
   - `AwakeScrollVoiceEngine.swift:78` — `requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition`; при отсутствии on-device для `ru_RU` (зависит от iOS/устройства) аудио может уйти серверам Apple. `NSSpeechRecognitionUsageDescription` (`Info.plist:79-80` + RU в `InfoPlist.xcstrings`) утверждает on-device во всех локалях.
   - Impact: неточное privacy-раскрытие (Guideline 5.1.1). Спека говорит «on-device STT default» → mismatch в строке, не в поведении.
   - Recommendation: либо `requiresOnDeviceRecognition = true` + неподдерживаемый распознаватель = unavailable (в духе offline-first), либо убрать «на устройстве» из строки в обеих локалях.

10. **[arch] Services → Views: контроллер зависит от типа из папки Views**
    - `AwakeScrollController.swift:36` — `DetailScrollViewProbeBox` объявлен в `Views/DetailScrollViewProbe.swift:4`, сервис держит и драйвит `UIScrollView`.
    - Recommendation: перенести `DetailScrollViewProbeBox` в `Services/Cooking/` (это сервисный порт «куда скроллить»), в Views оставить только `UIViewRepresentable`-пробу.

11. **[arch] `restartVoiceForLocaleChange` рвет capture epoch без нужды**
    - `AwakeScrollController.swift:100-104` — контракт явно требует «для stop только speech при живой камере — не рвать capture epoch»; реализация останавливает всю сессию и перестраивает камерный пайплайн на speech-only событии.
    - Recommendation: рестартовать только `voiceEngine` (stop + start с текущим epoch), `captureSession` не трогать.

12. **[arch] Тихие отказы старта каналов: UI показывает «работает», пайплайн мертв**
    - `AwakeScrollCaptureSession.swift:77-81` — `guard ... else { return }` без `AppLog` и без смены состояния при недоступности камеры; контроллер уже закоммитил `channelsRunning = true`. Аналогично `AwakeScrollVoiceEngine.swift:85-92` — при throw `setActive` (звонок) ранний выход **мимо** планирования `rearmTask` → voice мертв до цикла тумблера при живом UI-статусе; `recognizer.isAvailable == false` — тот же shape.
    - Recommendation: `start` возвращает результат (`.started / .unavailable(reason)`), лог через `AppLog`, per-channel degraded-состояние для баннера/шита; для audio-failure — отложенный retry.

13. **[arch+logic] Контрактные/спековые тесты не реализованы; у движков нет тестового seam**
    - `permission-teardown.md` §Tests требует assert `startRunning`/`stopRunning` call count — но все тесты идут с `startsRealEngines = false`, а движки — concrete types без протокола → поведение движков нефалифицируемо (и находка 2 структурно нетестируема). Спековые positive invariants не реализованы: `test_voice_off_keeps_hand`, `test_awake_only_no_camera`, cooldown-drop, face-arming (`prefersTrueDepthFace = true`).
    - Recommendation: минимальные `AwakeScrollVoiceEngineProtocol` / `AwakeScrollCaptureSessionProtocol` с инжекцией; тесты stop-call-count и stale-permission-start == 0 дословно по контракту; добавить 4 инвариантных теста.

14. **[perf] Hand-модальность не ограничивает FPS камеры: ~30 fps захват ради 20 fps Vision**
    - `AwakeScrollCaptureSession.swift` — нет `activeVideoMinFrameDuration`/`lockForConfiguration` cap → камера стримит ~30 fps, Vision обрабатывает 20 fps, лишние кадры дропаются. Энергия/термалы в длинной кухонной сессии.
    - Recommendation: cap до 20 fps (или ниже) через `device.activeVideoMinFrameDuration`.

15. **[perf] Face-мода (дефолт на TrueDepth): не-throttled MainActor-хопы на 60 Гц ARKit + дефолтный видеоформат**
    - `AwakeScrollCaptureSession.swift` — каждый face-anchor кадр порождает `Task { @MainActor }` без троттлинга; ARFaceTrackingConfiguration с дефолтным video format.
    - Recommendation: троттлить/коалесцировать MainActor-апдейты; явно выбрать минимальный_supported video format.

16. **[standards] 9 осиротевших rev-3 ключей локализации зашиты в consistency-тест**
    - `Localizable.xcstrings` — rev-3 ключи не используются кодом, но добавлены в `testCriticalKeysResolveInBothLanguages` → тест теперь защищает мусор.
    - Recommendation: удалить ключи и строки теста либо вернуть их в использование.

### Low

17. **[standards] `test_help_sheet_does_not_disarm_flags` вакуозен** — не проверяет заявленный инвариант. Recommendation: зафиксировать реальные assert'ы disarm/keep-armed.
18. **[standards] Два a11y-идентификатора ломают kebab-case** — `screen_awake_help_chip_scrollUp/scrollDown` из camelCase enum rawValues. Recommendation: маппить в kebab-case.
19. **[standards] Мертвый код** — 5 неиспользуемых a11y-идентификаторов + 4 layout-константы, включая дубль 0.75 scroll-fraction vs `AwakeScrollEngine.fraction`. Recommendation: удалить, fraction использовать из engine.
20. **[perf] Аллокации на кадр** — VNImageRequestHandler/requests и `Task` пересоздаются каждый кадр. Recommendation: переиспользовать handler/requests.
21. **[perf] Полный teardown аудио-стека на 55-секундном voice restart** — `AVAudioSession` деактивируется/реактивируется целиком. Recommendation: при restart держать сессию активной.

## Verified clean (по зонам)

- **Security**: permission API корректны (iOS 17+ `AVAudioApplication`, single-resume continuations); кадры/аудио нигде не персистятся/не шлются по сети; транскрипты только в DEBUG NDJSON (ос_log зеркалит без `data`); storage = 3 boolean + миграционный флаг; новых entitlements/background modes нет.
- **Logic**: scroll-математика = `scroll-delta.md` (все 3 фикстуры покрыты); hand-классификатор (dead zone, confidence, thumbs-up gate, 200 мс hold, Vision-flip `1 - y`) = контракту; XOR hand/face на storage и binding слоях; миграция F1.5/F1.9; epoch-hygiene (stale permission/frames/actions дропаются); probe корректно находит UIScrollView и исключает WKWebView.
- **Architecture**: composition root без `.shared` (контроллер экранно-scoped `@State` — допустимо для не-app-level сервиса); все long-lived колбэки `[weak self]`; направление Views→Services правильное (кроме находки 10); `didActivateAudioSession` не трогает сессию ассистента; Sendable-аннотации корректны.
- **Standards**: i18n — все 30 новых ключей с полными en+ru; InfoPlist-строки в обеих локалях; типографика на `AppTypography`/`.appBody()`/`.appFootnote()`; логи через `AppLog` на английском; спеки на русском со всеми секциями плана; pbxproj target membership чистый.

## Recommendation

**Changes Requested.** Находки 1–5 (critical + high) — мерж-блокеры: face-канал активирует ложные скроллы на каждом моргании, teardown-контракт с дырами на deinit/logout-путях, voice fire policy фактически не работает, whitelist расширен до суффиксов, F8.3-восстановление недостижимо. Findings 3 и 4 компаундятся — фиксить только один оставляет ложные срабатывания кухонной речи. 6 (AppSheetChrome) дешево чинится вместе. Остальное — в тот же проход или follow-up.
