# BALABOLKA Cloud Run Backend

Этот runbook выносит текущий `proxy/` в Google Cloud Run и полностью убирает зависимость iPhone-приложения от локального iMac.

## Почему выбран именно Cloud Run

- Текущий backend уже stateless и контейнеризуется без переписывания runtime-кода.
- Gemini API key можно хранить в Secret Manager, а не в iOS-клиенте и не на iMac.
- Cloud Run автоматически даёт HTTPS URL, autoscaling и простой source-based deploy.
- Для чистого API backend-а это прямее и проще, чем тащить Firebase App Hosting поверх Express-сервиса.

Firebase здесь остаётся релевантным как надстройка вокруг клиента:
- App Check для ограничения вызовов с iPhone-клиента.
- Analytics/Crashlytics/Remote Config по желанию.

## Long-form контракт для Cloud Run

- Cloud Run должен принимать обычные proxy-запросы с ceiling `12000` символов на один `POST /v1/tts/synthesize`.
- Product-level long-form до `128000` символов реализуется выше уровнем: приложение само режет исходный текст на серию proxy-запросов и агрегирует результат локально.
- Поэтому для Cloud Run нужно смотреть не только на размер и latency одного запроса, но и на cumulative behaviour последовательности long-form вызовов: concurrency, retry storms и общую стоимость серии synth-операций.

## Что нужно перед деплоем

1. Google Cloud project с включённым billing.
2. Включённые API:
   - `run.googleapis.com`
   - `artifactregistry.googleapis.com`
   - `cloudbuild.googleapis.com`
   - `secretmanager.googleapis.com`
3. Установленный `gcloud` CLI.
4. Gemini Developer API key.

## Секреты

Секреты лучше хранить в Secret Manager, а не в env-файлах.

Пример имён:
- `balabolka-gemini-api-key`
- `balabolka-proxy-bearer-token`

Пример создания:

```bash
printf '%s' 'YOUR_GEMINI_API_KEY' | \
  gcloud secrets create balabolka-gemini-api-key --data-file=-

printf '%s' 'YOUR_RANDOM_BEARER_TOKEN' | \
  gcloud secrets create balabolka-proxy-bearer-token --data-file=-
```

Если секрет уже существует, обновление делается через новую версию:

```bash
printf '%s' 'NEW_VALUE' | \
  gcloud secrets versions add balabolka-gemini-api-key --data-file=-
```

## Рекомендуемая конфигурация сервиса

- Region: `us-central1` либо ближайший к основной аудитории регион.
- CPU: `1`
- Memory: `512Mi`
- Concurrency: `8`
- Timeout: `300s`
- Min instances: `0` для экономии на MVP
- Max instances: `10`
- Новый long-form load shape:
  - сервис должен стабильно переживать один proxy-request у ceiling `12000`;
  - пользовательская генерация до `128000` будет выглядеть как серия обычных запросов, а не один бесконечный HTTP synth.
- Authentication:
  - если backend вызывается только приложением, можно оставить публичный ingress и держать `PROXY_BEARER_TOKEN`;
  - следующим шагом после деплоя стоит добавить server-side проверку App Check token в runtime-коде.

## Деплой из исходников

Вариант без локального Docker daemon:

```bash
cd /Users/alex/Developer/BALABOLKA/proxy

gcloud run deploy balabolka-proxy \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --port 8080 \
  --cpu 1 \
  --memory 512Mi \
  --concurrency 8 \
  --timeout 300 \
  --min-instances 0 \
  --max-instances 10 \
  --set-env-vars=GEMINI_TTS_MODEL=gemini-3.1-flash-tts-preview,GEMINI_PREPROCESSOR_MODEL=gemini-3-flash-preview,ENABLE_PROMPT_PREPROCESSOR=true,TTS_MAX_RETRIES=2 \
  --set-secrets=GEMINI_API_KEY=balabolka-gemini-api-key:latest,PROXY_BEARER_TOKEN=balabolka-proxy-bearer-token:latest
```

Cloud Run сам использует Dockerfile из `proxy/`.

## Smoke check после деплоя

Проверка health endpoint:

```bash
curl https://YOUR_CLOUD_RUN_URL/healthz
```

Проверка каталога:

```bash
curl https://YOUR_CLOUD_RUN_URL/v1/tts/catalog \
  -H 'Authorization: Bearer YOUR_RANDOM_BEARER_TOKEN'
```

Проверка synth:

```bash
curl -X POST https://YOUR_CLOUD_RUN_URL/v1/tts/synthesize \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer YOUR_RANDOM_BEARER_TOKEN' \
  -d '{
    "text": "Это продовый smoke test для BALABOLKA.",
    "preset": "тихо",
    "voice": "Zephyr"
  }'
```

Ожидается JSON с `audio.base64`, `audio.mimeType = "audio/wav"` и `provider.ttsModel`.

Для long-form acceptance отдельно прогонять:

- один запрос около ceiling `12000` символов;
- серию последовательных synth-вызовов, которая суммарно моделирует пользовательский текст до `128000` символов.

## Что поменять в iPhone-приложении после деплоя

- `Proxy Base URL` должен смотреть не на `192.168.x.x`, а на HTTPS URL Cloud Run.
- `Bearer token` в настройках приложения должен совпадать с `PROXY_BEARER_TOKEN`, если auth включён.
- В идеале bearer token потом убрать из пользовательского UI и заменить на штатную серверную проверку App Check.

## Rollback

Cloud Run поддерживает revisions. При неудачном релизе:

```bash
gcloud run revisions list --service balabolka-proxy --region us-central1
gcloud run services update-traffic balabolka-proxy --region us-central1 --to-revisions REVISION_NAME=100
```

## Firebase note

Для этого backend-а Firebase App Hosting не выбран как primary path, потому что у нас не full-stack web app, а отдельный API proxy для iPhone-клиента. Если нужен "Firebase-only" operational story, практичный вариант такой:

- iOS app использует Firebase App Check / Analytics / Crashlytics.
- Тонкий TTS proxy живёт в Cloud Run.
- Custom domain при необходимости можно выдать через Firebase Hosting rewrite или отдельный Load Balancer, но это уже не нужно для MVP.
