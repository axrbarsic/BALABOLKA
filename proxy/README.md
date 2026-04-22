# BALABOLKA proxy

Тонкий Node/TypeScript proxy для iOS-клиента BALABOLKA. Сервис хранит Gemini key только на сервере, подготавливает expressive prompt, вызывает Gemini TTS и всегда отдаёт клиенту `audio/wav` в base64.

## Что делает

- `POST /v1/tts/synthesize`:
  - принимает `text`, backward-compatible `preset`, а также новый `presetIds[]`, `combineMode`, `voice`, optional `title` и `id`
  - при необходимости прогоняет текст через отдельный prompt-preprocessor
  - вызывает `gemini-3.1-flash-tts-preview`
  - собирает WAV из PCM, если Gemini вернул raw PCM
  - возвращает WAV base64, подготовленный prompt/transcript, structured segment plan и служебные метаданные
- `GET /v1/tts/catalog`:
  - отдаёт список expressive preset-ов и поддерживаемых голосов
- `GET /healthz`:
  - healthcheck без обращения к Gemini

## Почему дизайн именно такой

- По официальной документации Gemini API на 20 апреля 2026 актуальный TTS-модельный код для этой задачи: [`gemini-3.1-flash-tts-preview`](https://ai.google.dev/gemini-api/docs/speech-generation).
- Документация прямо рекомендует задавать performance через `DIRECTOR'S NOTES`, `TRANSCRIPT` и английские audio tags вроде `[whispers]`, `[laughs]`, `[sarcastic]`, `[tired]`, `[gasp]`.
- Там же зафиксированы ограничения, которые учтены в proxy:
  - streaming для TTS не поддерживается
  - у сессии лимит 32k токенов
  - на длинных генерациях качество может деградировать
  - иногда модель возвращает text tokens вместо audio, из-за чего возможен `500`
  - vague prompt может привести к тому, что модель начнёт зачитывать director notes вслух
- Из-за этого proxy:
  - добавляет явный speech preamble и отдельную секцию `TRANSCRIPT`
  - имеет встроенный retry на TTS-вызове
  - нормализует результат в `audio/wav`

## Long-form контракт

- Один `POST /v1/tts/synthesize` должен рассматриваться как service-level unit с ceiling `12000` символов исходного текста.
- Внутри этого одного запроса proxy всё ещё может дополнительно резать transcript на более мелкие TTS-чанки под ограничения Gemini.
- Product-level long-form flow до `128000` символов относится уже не к одному HTTP-вызову, а к orchestration-слою приложения: клиент режет текст на несколько proxy-запросов и потом собирает результат обратно локально.
- Поэтому `12000` в документации backend-а больше не означает "полный лимит приложения"; это только guardrail одного proxy-hop.

## Быстрый старт

```bash
cd /Users/alex/Developer/BALABOLKA/proxy
cp .env.example .env
npm install
npm run dev
```

Сервис по умолчанию поднимется на `http://localhost:8787`.

## Переменные окружения

- `GEMINI_API_KEY`:
  ключ Gemini Developer API. Можно также использовать `GOOGLE_API_KEY`.
- `PROXY_BEARER_TOKEN`:
  если задан, все `/v1/*` эндпоинты требуют `Authorization: Bearer ...`
- `GEMINI_TTS_MODEL`:
  по умолчанию `gemini-3.1-flash-tts-preview`
- `GEMINI_PREPROCESSOR_MODEL`:
  по умолчанию `gemini-3-flash-preview`
- `GEMINI_PREPROCESSOR_FALLBACK_MODEL`:
  optional fallback-модель для prompt-preprocessor, по умолчанию `gemini-3.1-pro-preview`
- `ENABLE_PROMPT_PREPROCESSOR`:
  `true` или `false`
- `TTS_MAX_RETRIES`:
  количество повторов при retryable-ошибках TTS

## Пример запроса

```bash
curl -X POST http://localhost:8787/v1/tts/synthesize \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer local-dev-token' \
  -d '{
    "id": "demo-001",
    "title": "Шепчущий ролик",
    "text": "Это короткий тест. Я проверяю, как сервис готовит текст для шепчущей озвучки.",
    "presetIds": ["шёпот", "усталость"],
    "combineMode": "auto",
    "voice": "Enceladus"
  }'
```

## Формат ответа

```json
{
  "requestId": "demo-001",
  "preset": {
    "id": "whisper",
    "label": "шёпот"
  },
  "presets": [
    { "id": "whisper", "label": "шёпот" },
    { "id": "tired", "label": "усталость" }
  ],
  "combineMode": "auto",
  "voice": {
    "name": "Enceladus",
    "descriptor": "Breathy"
  },
  "prompt": {
    "preparedPrompt": "Please synthesize speech audio ...",
    "preparedTranscript": "[whispers] Это короткий тест...",
    "mode": "model",
    "plan": {
      "combineMode": "auto",
      "segments": [
        {
          "index": 0,
          "presetId": "whisper",
          "placement": "opening",
          "audioTags": ["[whispers]"]
        }
      ]
    }
  },
  "audio": {
    "mimeType": "audio/wav",
    "base64": "UklGR...",
    "sampleRateHz": 24000,
    "channels": 1,
    "bitDepth": 16
  },
  "provider": {
    "ttsModel": "gemini-3.1-flash-tts-preview",
    "preprocessorModel": "gemini-3-flash-preview",
    "ttsAttempts": 1
  }
}
```

## Runbook

1. Заполнить `.env`.
2. Для локальной разработки можно задать `PROXY_BEARER_TOKEN=local-dev-token`.
3. Запустить `npm run dev`.
4. Проверить `GET /healthz`.
5. Проверить `GET /v1/tts/catalog`.
6. Отправить `POST /v1/tts/synthesize`.

## Deployment paths

- Free-first path: Cloudflare Workers.
- Reliability fallback: Cloud Run.

### Cloudflare Workers

- Runbook: [`docs/cloudflare-workers-backend.md`](../docs/cloudflare-workers-backend.md)
- Local dev scaffold:

```bash
cd /Users/alex/Developer/BALABOLKA/proxy
cp .dev.vars.example .dev.vars
npx wrangler@latest login
npx wrangler@latest deploy --dry-run
```

- В репозитории уже есть dedicated Worker entrypoint: `src/worker.ts`.
- Workers подходит под free-first стратегию, но для длинных `audio.base64` ответов надо отдельно проверить реальные CPU/memory лимиты.

### Cloud Run

- Для выноса backend-а из iMac также подготовлен container path через Cloud Run.
- Основные deployment-файлы:
  - `Dockerfile`
  - `.dockerignore`
  - `.gcloudignore`
- Подробный production runbook: [`docs/cloud-run-backend.md`](../docs/cloud-run-backend.md).

Коротко:

```bash
cd /Users/alex/Developer/BALABOLKA/proxy
gcloud run deploy balabolka-proxy --source .
```

Секреты `GEMINI_API_KEY` и `PROXY_BEARER_TOKEN` для production должны приходить из Secret Manager, а не из `.env`.

## Инженерные решения и tradeoff'ы

- Preprocessor сделан отдельным шагом, потому что expressive-плитки не должны быть тупой строковой припиской. Для mixed expressive flow он умеет возвращать structured segment plan, а при ошибке preprocess-сервиса есть deterministic fallback, чтобы proxy не падал полностью.
- Сервер отдаёт JSON с base64 WAV, а не файл-стрим. Для iOS-клиента это проще на MVP-этапе, но на длинных текстах payload будет тяжёлым.
- Для нового long-form контура серверный guardrail остаётся на уровне `12000` символов на запрос; всё до `128000` символов должно оркестрироваться клиентом как серия обычных proxy-вызовов.
- История и локальный кэш должны жить в iOS-клиенте; сервер остаётся тонким stateless-proxy.
