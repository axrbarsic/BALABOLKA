# BALABOLKA

Нативное iPhone-приложение для генерации озвученного квадратного видео `720x720` через Gemini TTS с тонким server-side proxy.

## Что уже есть

- iPhone-native SwiftUI клиент.
- Ввод и редактирование текста.
- 10 expressive-режимов:
  - тихо
  - шёпот
  - смех
  - плач
  - кашель
  - хрипота
  - сарказм
  - злость
  - усталость
  - тяжёлое дыхание
- Генерация речи через proxy.
- Локальная сборка финального видео с белым фоном и реактивной волной.
- Playback результата.
- История и локальный кэш.
- Share/export готового видео.

## Архитектура

- `BALABOLKA/`
  iOS SwiftUI client.
- `proxy/`
  тонкий proxy с двумя runtime-path: Node/TypeScript и Cloudflare Workers. Gemini API key хранится только на серверной стороне.
- `docs/architecture.md`
  зафиксированные инженерные решения и хронология.
- `docs/cloud-run-backend.md`
  production runbook для выноса proxy в Cloud Run без зависимости от iMac.
- `docs/cloudflare-workers-backend.md`
  free-first runbook для Cloudflare Workers.

## Как запускать proxy

```bash
cd /Users/alex/Developer/BALABOLKA/proxy
cp .env.example .env
npm install
npm run dev
```

По умолчанию proxy слушает `http://localhost:8787`.

## Как вынести backend в облако

- Бесплатный first-choice path: Cloudflare Workers.
- Платный fallback path: Google Cloud Run.
- Workers runbook: [`docs/cloudflare-workers-backend.md`](./docs/cloudflare-workers-backend.md).
- Cloud Run runbook: [`docs/cloud-run-backend.md`](./docs/cloud-run-backend.md).

После такого деплоя iPhone-клиенту больше не нужен локальный iMac-proxy: приложение теперь по умолчанию стартует сразу с production Workers URL, а старые `localhost`/LAN-настройки мигрируются автоматически.

На 20 апреля 2026 для этого проекта уже поднят живой Workers backend:

- `https://balabolka-proxy.axrbarsic.workers.dev`

## Как запускать приложение

```bash
cd /Users/alex/Developer/BALABOLKA
xcodebuild -project BALABOLKA.xcodeproj -scheme BALABOLKA -destination 'generic/platform=iOS Simulator' build
```

После этого можно открыть проект в Xcode или установить билд в Simulator.

## Что проверено локально

- `xcodebuild` для iOS Simulator проходит успешно.
- proxy проходит `npm test` и `npm run build`.
- iOS app после архитектурного refactor снова проходит `xcodebuild` build.
- live smoke test к Gemini TTS через локальный proxy проходит успешно и возвращает `audio/wav`.
- recovery-path для flaky expressive-запросов проверен: если первый synth с `usePromptPreprocessor=true` не дал audio, proxy делает recovery-pass на deterministic fallback prompt.
- приложение успешно запускается в iOS Simulator.
- реальная генерация из UI подтверждена в Simulator: создан и сохранён `balabolka.mp4`, запись попала в историю.
- финальный video asset проверен через `ffprobe`: `720x720`, video `h264`, audio `aac 24000 Hz mono`.
- long-text smoke против production Worker подтверждён: запрос с `4284` символами вернулся `HTTP 200` за `136.7s`, а backend автоматически разбил TTS на `6` чанков.
- mixed/combine expressive mode усилен: multi-preset preprocessor больше не должен молча схлопываться в один preset при пустом или слабом `segmentPlan`, а short-text fallback лучше распределяет экспрессию по clauses/sentences.
- progress UX больше не упирается в фальшивую полку около `72%`: процент считается по диапазонам стадий, а панель генерации всегда показывает live activity и substage-progress.
- simulator XCTest после этих правок: выполнено `16` тестов, `0` failures, `1` skipped (`long-form stress opt-in`), включая новый сценарий на длинном пользовательском русском тексте и проверку монотонного progress pipeline.

## Лимиты

- По официальной документации Google для `gemini-3.1-flash-tts-preview` лимит одного TTS-вызова: `8192` входных токена и `16384` выходных токена.
- В BALABOLKA есть два разных уровня chunking, их нельзя смешивать:
  - proxy внутри одного запроса может дополнительно резать текст на TTS-чанки под Gemini;
  - приложение снаружи должно резать long-form текст на несколько proxy-запросов.
- `12000` символов теперь трактуются как ceiling одного `POST /v1/tts/synthesize`, а не как лимит всей пользовательской генерации.
- Продуктовый long-form контур должен поддерживать auto-chunking до `128000` символов исходного текста на одну пользовательскую генерацию.
- UI, документация и operational runbook не должны больше показывать `12000` как полный лимит приложения: это только per-request guardrail для proxy.
- Отдельный async batch/job режим остаётся следующей ступенью только для сценариев за пределами `128000` символов или для resumable/background processing.

## Важный operational note

- Канонический локальный путь проекта: `/Users/alex/Developer/BALABOLKA`.
- Старый путь в `Documents` больше не должен использоваться как рабочая директория для Xcode, потому что `~/Documents` на этом Mac обслуживается через iCloud File Provider.
- Для совместимости старый путь `/Users/alex/Documents/Projects/BALABOLKA` заменён symlink на новый локальный путь.
- Для всех активных dev-проектов на этом Mac лучше использовать `~/Developer` или `~/Code`, а не `~/Documents` и `~/Desktop`.

- Для новых установок дефолтный `proxyBaseURL` уже указывает на production Worker.
- Старые локальные `localhost`/`192.168.*:8787` настройки автоматически переводятся на production Worker при следующем запуске приложения.
- Для Simulator локальный `http://127.0.0.1:8787` остаётся допустимым только как осознанный ручной override.
- Для free-first production сначала пробуем Cloudflare Workers.
- Если Workers покажет плохую надёжность на длинных озвучках из-за CPU/memory/base64 WAV, fallback — Cloud Run.
