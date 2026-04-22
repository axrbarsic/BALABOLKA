# BALABOLKA iOS MVP Architecture

## Текущее состояние на 2026-04-20

- Исходный workspace был пустым SwiftUI-шаблоном Xcode: `BALABOLKAApp.swift` и `ContentView.swift`.
- Существующего `balabolka`-контура, backend-а, истории, render pipeline и iPhone UX в репозитории не было.
- Проект был создан как мультиплатформенный шаблон; для продукта он переведён в iPhone-only направление.

## Внешние опорные факты

- Официальная документация Gemini TTS подтверждает модель `gemini-3.1-flash-tts-preview` и её TTS-режим через `responseModalities=["AUDIO"]`.
- Google отдельно показывает, что модель возвращает PCM, который нужно оборачивать в WAV.
- Официальный speech generation guide разрешает управлять стилем естественным языком и audio tags, а также отдельно рекомендует сначала генерировать transcript другой моделью, а потом отдавать его в TTS.
- Firebase AI Logic прямо рекомендует не класть Gemini API key в мобильное приложение и использовать backend/proxy path.
- На iOS для square video export используется стандартный путь `AVAssetWriter` + pixel buffers; для чтения WAV/PCM подходит `AVAudioFile`.

## Целевая архитектура

### 1. iOS client

- SwiftUI iPhone app.
- Локальное редактирование текста.
- 10 expressive presets как структурированные режимы, а не просто строки.
- Long-form coordinator в клиенте: одна пользовательская генерация поддерживает до `128000` символов через auto-chunking на серию proxy-запросов.
- Локальная история генераций и файловый кэш.
- Playback готового видео.
- Export/share итогового файла.

### 2. Thin proxy / free-first backend

- Хранит Gemini API key только на сервере.
- Принимает plain text + expressive preset + voice + metadata.
- При необходимости сначала вызывает prompt-preprocessor.
- Затем вызывает `gemini-3.1-flash-tts-preview`.
- Возвращает WAV + подготовленный transcript/prompt + metadata.
- Имеет жёсткий service-level ceiling `12000` символов на один входной proxy-запрос.
- Внутри одного proxy-запроса всё ещё может дополнительно дробить текст на TTS-чанки под лимиты Gemini.
- Всё, что можно надёжно считать, рендерить и хранить на iPhone, остаётся на iPhone.
- Удалённый backend нужен только для тех вызовов Gemini API, где нельзя безопасно держать ключ в приложении.
- Free-first deployment target теперь: Cloudflare Workers с dedicated `proxy/src/worker.ts`.
- Платный/fallback path остаётся через Cloud Run, если Workers упрётся в реальные лимиты по CPU/memory на длинных base64 WAV-ответах.

### 3. Media pipeline на устройстве

- Анализирует амплитуду из WAV.
- Строит единый waveform model для playback preview и offline export.
- Рендерит квадратный `720x720` video с белым фоном и синхронной волной.
- Склеивает waveform video + audio в готовый shareable media file.

## Важные инженерные решения

- Финальный артефакт собирается на устройстве, а не на сервере: это сохраняет proxy тонким и уменьшает backend cost.
- Local-first rule: текст, история, кэш, waveform analysis, video render/export, quality variants и save-to-Photos живут на iPhone; сервер не участвует в media pipeline.
- Expressive слой делается двуслойным: preset metadata + server-side prompt preparation. Это лучше, чем тупо дописывать одно слово в текст.
- Если Gemini TTS не вернул audio на первом expressive-pass, proxy обязан делать recovery-pass на deterministic fallback prompt, не перекладывая нестабильность модели на iOS-клиент.
- История хранит не только исходный текст, но и prepared transcript, выбранный preset, voice и пути к локальным аудио/видео файлам.
- Для dev-сценария разрешён local networking, чтобы iPhone Simulator мог ходить в локальный proxy без лишней борьбы с ATS.
- iOS-клиент двигается к более правильной архитектуре через composition root + use-case actors, чтобы можно было безболезненно менять remote/local implementation за узкими seam-ами.
- Официальный лимит `gemini-3.1-flash-tts-preview` — `8192` входных токена и `16384` выходных токена на один TTS-вызов; в продукте это нельзя путать с лимитом всего сценария, потому что proxy делает chunked TTS.
- Новый продуктовый контракт двухступенчатый: `12000` символов — ceiling одного proxy-запроса, `128000` символов — ceiling одной пользовательской генерации.
- Long-form orchestration живёт на клиентском уровне: app сама режет текст на серию proxy-запросов, собирает ответы обратно в одну историю/экспорт и не требует отдельного server-side batch job для диапазона до `128000`.
- Async batch/job mode остаётся следующим шагом только для объёмов выше `128000`, для background/resumable сценариев или если один foreground long-form flow станет слишком хрупким по wall-time.
- Наиболее безопасный визуальный upgrade path без AI image generation — оставить текущий `AVAssetWriter` pipeline и заменить только содержимое кадра на процедурный audio-reactive renderer (`orb + pulse rings`) вместо простой waveform.

## Хронология изменений

- 2026-04-20: проведён аудит пустого шаблона проекта.
- 2026-04-20: подтверждены официальные документы по Gemini 3.1 Flash TTS, prompt control и proxy/mobile path.
- 2026-04-20: проект переведён в iPhone-only конфигурацию и открыт local-networking путь для proxy development.
- 2026-04-20: реализован iPhone SwiftUI MVP-клиент с editor flow, expressive grid, playback, history и share/export.
- 2026-04-20: добавлен `proxy/` на Node/TypeScript c `POST /v1/tts/synthesize`, prompt-preprocessor и WAV normalization.
- 2026-04-20: клиент переведён на фактический proxy-контракт `/v1/tts/synthesize`.
- 2026-04-20: локально подтверждены `xcodebuild` green build, live Gemini TTS smoke test через proxy и успешный launch приложения в iOS Simulator.
- 2026-04-20: media pipeline упрощён до self-contained iOS-реализации без внешнего `BALWaveformCore`, чтобы квадратный `720x720` video export не зависел от удалённых вспомогательных типов.
- 2026-04-20: добавлен proxy recovery-path для flaky TTS-ответов без audio data на expressive-запросах.
- 2026-04-20: end-to-end runtime подтверждён в Simulator: генерация из UI создаёт `balabolka.mp4`, запись сохраняется в history, итоговый asset имеет `720x720 h264` + `aac mono 24 kHz`.
- 2026-04-20: найдена и исправлена незавершённая миграция `project.pbxproj` на `PBXFileSystemSynchronizedRootGroup`: удалён legacy-хвост с ручными app-source references/build files, который создавал `Skipping duplicate build file...` и лишний reconcile в Xcode.
- 2026-04-20: подтверждено, что `~/Documents` на этом Mac идёт через `com.apple.CloudDocs.iCloudDriveFileProvider`; активный workspace вынесен из iCloud-managed `Documents` в `/Users/alex/Developer/BALABOLKA`, а старый путь заменён symlink для совместимости.
- 2026-04-20: прямые `xcodebuild` и device build проверены уже из нового локального пути вне iCloud.
- 2026-04-20: для `proxy/` подготовлен production deployment path через Cloud Run: добавлены `Dockerfile`, `.dockerignore`, `.gcloudignore` и отдельный runbook `docs/cloud-run-backend.md`, чтобы убрать зависимость iPhone-клиента от локального iMac.
- 2026-04-20: добавлен Cloudflare Workers path: `proxy/wrangler.jsonc`, `proxy/.dev.vars.example`, `docs/cloudflare-workers-backend.md` и dedicated `proxy/src/worker.ts`.
- 2026-04-20: free-first deployment policy обновлена: Workers рассматривается как основной бесплатный backend, а Cloud Run остаётся reliability fallback при выходе за лимиты Workers.
- 2026-04-20: iOS composition root вынесен в `AppContainer`, generation/history/export разрезаны на use-case actors, а `BalabolkaAppModel` сделан тоньше и ближе к feature state вместо god object.
- 2026-04-20: живой Cloudflare rollout завершён: `wrangler login` пройден, secret `GEMINI_API_KEY` загружен, script-level `workers.dev` route включён через официальный Cloudflare API, production Worker задеплоен на `https://balabolka-proxy.axrbarsic.workers.dev`.
- 2026-04-20: live smoke против публичного Worker подтверждён для `/healthz`, `/v1/tts/catalog` и `POST /v1/tts/synthesize`; mixed expressive flow после смягчения схемы model-preprocessor перестал аварийно уходить в fallback на базовом кейсе `quiet + sarcasm`.
- 2026-04-20: подключённый iPhone переведён со старого Mac URL `http://192.168.1.155:8787` на публичный Cloudflare backend в app preferences; теперь рабочая цепочка больше не зависит от запущенного iMac proxy.
- 2026-04-20: подтверждён официальный model limit для `gemini-3.1-flash-tts-preview`: `8192` input tokens / `16384` output tokens; для нового long-form контура зафиксирован двухступенчатый контракт `12000` символов на один proxy-request и до `128000` символов на одну app-level generation через auto-chunking.
- 2026-04-20: подтверждён live long-text path через production Worker: запрос примерно на `4284` символа завершился успешно за `136.7s`, backend автоматически сообщил `Long transcript split into 6 TTS chunks.`.
- 2026-04-20: найден preferred next visual path без генерации картинок моделью — локальный процедурный audio-reactive renderer (`reactive orb + pulse rings`) как замена скучной waveform при сохранении существующего export pipeline.
- 2026-04-20: устранён сегодняшний `Xcode-open hang` на cold reopen: root cause оказался составным — `file-provider` metadata на `/Users/alex/Developer/BALABOLKA/BALABOLKA.xcodeproj`, почти полный Data volume (около `3.0 GiB` free до чистки), битая explicit ссылка `Foundation.framework` на `iPhoneOS18.0.sdk` в `project.pbxproj` и старый Xcode user-state; fix включил снятие `com.apple.fileprovider.fpfs#P` с `.xcodeproj`, очистку `DerivedData`/codex/npm transient caches, перевод `Foundation.framework` path на `SDKROOT` и reset user-state через backup+move `plist` и `IDEEditorInteractivityHistory`, после чего cold reopen снова вернул `BALABOLKA.xcodeproj` примерно за `7.84s`.
- 2026-04-20: устранена тихая деградация mixed expressive mode в один primary preset: для multi-preset preprocessor теперь жёстче требует `segmentPlan`, при слабом model-output проверяет фактическое покрытие active preset ids и, если оно недостаточно, принудительно откатывается к детерминированному fallback-распределению по clauses/sentences вместо single-preset collapse.
- 2026-04-20: short-text combine fallback усилен отдельно: preprocessor научен резать мало-предложенийный текст на более мелкие expressive units, а preset `laugh` получил mid-tag fallback (`[giggles]`), чтобы смешанные режимы на коротких текстах давали слышимый эффект, а не только декларативную карточку в UI.
- 2026-04-20: progress UX переработан с hardcoded synthetic-потолка около `72%` на stage-range модель. Теперь общий процент считается по диапазонам стадий, synthetic-progress работает на всех стадиях, а панель генерации показывает и общий процент, и живую substage-активность вместо ощущения “подвисло”.
- 2026-04-20: решения по progress UX опирались на свежие источники: Apple HIG по [progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators/), Apple guidance по [long-running tasks](https://developer.apple.com/documentation/BackgroundTasks/performing-long-running-tasks-on-ios-and-ipados), Google guide по [Gemini speech generation](https://ai.google.dev/gemini-api/docs/speech-generation), плюс community-наблюдения по SwiftUI `ProgressView` и background progress reporting, что псевдо-точный determinate bar без real sub-events воспринимается хуже, чем hybrid determinate + visible activity.
- 2026-04-20: simulator verification после этих правок завершён зелёно: `BALABOLKATests` выполнил `16` тестов с `0 failures`, из них `1` был осознанно `skipped` (`long-form stress opt-in`), включая новый сценарий на пользовательском длинном русском тексте для mixed-mode и монотонного progress pipeline. Итоговый xcresult: `/Users/alex/Library/Developer/Xcode/DerivedData/BALABOLKA-adrubflywksehifyyilqsqmtkjnr/Logs/Test/Test-BALABOLKA-2026.04.20_15-55-42--0400.xcresult`.
- 2026-04-20: user-facing bearer auth убран из production Workers path, потому что схема `secret token в UI iPhone` противоречила целевой архитектуре `iPhone client + thin backend без секрета в приложении`. Production Worker теперь работает без `PROXY_BEARER_TOKEN`, а hardening next step смещён в сторону server-side attestation вместо ручного bearer-поля.
- 2026-04-20: `BalabolkaSettings` переведён на production-first default URL (`https://balabolka-proxy.axrbarsic.workers.dev`), а `SettingsStore` получил миграцию старых `localhost`/private-LAN proxy URL на production Worker, чтобы реальный iPhone не зависел от старого iMac proxy после обновления приложения.
- 2026-04-20: prompt-preprocessor переключён с `gemini-3-flash-preview` / `gemini-3.1-pro-preview` на `gemini-2.5-flash-lite` / `gemini-2.5-flash` после свежей сверки официальных quota/pricing страниц Gemini: для planning/segmenting expressive tags нам важнее throughput и RPD, чем Pro-level reasoning, а `2.5 Flash-Lite` даёт более уместный free/low-cost профиль.
- 2026-04-20: live smoke после этого переключения подтвердил production path без bearer и без preprocessor-quota деградации: `/healthz` показывает `authEnabled=false`, `preprocessorModel=gemini-2.5-flash-lite`, а mixed expressive synth снова возвращает `mode=model` с `promptPreprocessorUsed=true`.
- 2026-04-20: дополнительно закрыт quota-diagnostics gap: production Worker теперь маппит Gemini `429` в `UPSTREAM_QUOTA_EXCEEDED` вместо безликого `INTERNAL_ERROR`, а iPhone-клиент показывает человекочитаемое сообщение о том, что исчерпана именно суточная квота TTS-модели. Повторный live check на длинном mixed smoke подтвердил новый ответ `quotaScope=daily`.
