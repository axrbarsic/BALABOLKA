# BALABOLKA Cloudflare Workers Scaffold

Этот документ описывает актуальный free-first deployment path под Cloudflare Workers. Платный fallback path остаётся через Cloud Run: [`docs/cloud-run-backend.md`](./cloud-run-backend.md).

## Текущее состояние на 2026-04-20

- `proxy/src/server.ts` и Node/Express path сохранены для локального dev и Cloud Run fallback.
- Dedicated Worker entrypoint теперь существует: `proxy/src/worker.ts`.
- `proxy/wrangler.jsonc` уже смотрит на него и готов к `wrangler deploy`.
- Workers path уже реально собран и задеплоен.
- Production URL сейчас: `https://balabolka-proxy.axrbarsic.workers.dev`.
- Подключённый iPhone уже переведён на этот URL вместо старого локального Mac proxy.

## Long-form контракт для Workers

- Workers обслуживает не "один giant-request на весь long-form текст", а обычные proxy-вызовы с ceiling `12000` символов на запрос.
- Product-level long-form до `128000` символов должен собираться приложением как серия последовательных proxy-вызовов к Worker.
- Поэтому для Workers важно валидировать не только один тяжёлый synth, но и end-to-end цепочку из нескольких подряд invocation-ов с суммарным wall-time, retry pressure и накопленным объёмом `audio.base64`.

## Когда Workers здесь уместен

Workers имеет смысл как будущий edge-path, если нужен:

- простой глобальный HTTPS endpoint без контейнеров;
- хранение секретов на стороне Cloudflare;
- единый deploy через `wrangler`;
- возможный будущий rewrite под `fetch(request, env, ctx)`.

Workers всё ещё не является автоматическим silver bullet, потому что текущий proxy по-прежнему держит TTS-ответ целиком в памяти и отдаёт JSON с base64 WAV. В новом контуре risk area смещается с одного огромного пользовательского запроса на серию medium-size synth-запросов и их суммарную надёжность.

## Free vs Paid

### Workers Free

Подходит как бесплатный старт и технический preflight.

- Лимит запросов: `100,000/day`.
- CPU budget: `10 ms` на invocation.
- Скрипт: до `3 MB`.
- Секреты и `workers.dev` доступны.

Честный вывод: для BALABOLKA Free-план реалистичен как основной бесплатный старт, если держать backend максимально тонким и помнить, что даже при ceiling `12000` символов на запрос длинный пользовательский прогон до `128000` символов превращается в серию invocation-ов с накопленным CPU/memory давлением из-за `audio.base64`.

### Workers Paid

Это минимально реалистичный вариант для будущего production migration на Workers.

- Включено `10M` запросов в месяц, далее биллинг по usage.
- Включено `30M` CPU milliseconds в месяц.
- По умолчанию максимум `30 s` CPU на invocation.
- При необходимости предел CPU можно поднять до `5 min`.
- Скрипт: до `10 MB`.

Честный вывод: Paid снимает главное ограничение Free по CPU, но не отменяет архитектурный caveat текущего proxy: каждый вызов всё равно возвращает тяжёлый `audio.base64`, а end-to-end long-form flow надо валидировать и по memory/CPU, и по cumulative latency.

## Главные caveat-ы именно для BALABOLKA

1. Workers runtime имеет memory ceiling `128 MB`, а текущий контракт возвращает целый WAV в base64 внутри JSON для каждого proxy-запроса.
2. TTS в proxy не стримится; каждый отдельный запрос будет буферизоваться целиком.
3. Long-form до `128000` символов теперь означает цепочку нескольких invocation-ов, поэтому кроме одного запроса нужно наблюдать cumulative wall-time, retries и rate-limit pressure.
4. Если текущий "JSON + base64 WAV" контракт без streaming/offload окажется тесным даже при per-request ceiling `12000`, следующий шаг не костыль в iPhone, а либо Workers Paid, либо смена backend-контракта на binary/object URL.

## Файлы scaffold

- `proxy/wrangler.jsonc`
- `proxy/.dev.vars.example`
- `proxy/.gitignore` дополнен только для Workers local state

Эти файлы не вмешиваются в текущий Node path:

- `npm run dev` по-прежнему использует `src/server.ts`;
- `.env.example` и `.env` остаются локальным Node-механизмом;
- `wrangler.jsonc` сейчас служит как заготовка под будущий Worker runtime.

## Подготовка Cloudflare аккаунта

1. Создать или выбрать Cloudflare account.
2. Для интерактивного входа выполнить:

```bash
cd /Users/alex/Developer/BALABOLKA/proxy
npx wrangler@latest login
```

3. Для CI вместо login использовать `CLOUDFLARE_API_TOKEN`.
4. Проверить авторизацию:

```bash
npx wrangler@latest whoami
```

### Если `wrangler deploy` ругается на `workers.dev subdomain`

У этого аккаунта Cloudflare dashboard-onboarding для `workers.dev` отработал нестабильно: после OAuth `wrangler` был авторизован, но UI-страница subdomain onboarding отдавала ошибку. Проверенный обход через официальный Cloudflare API:

1. Проверить account-level subdomain:

```bash
curl -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  https://api.cloudflare.com/client/v4/accounts/<ACCOUNT_ID>/workers/subdomain
```

2. Включить `workers.dev` именно для script:

```bash
curl -X POST \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H 'Content-Type: application/json' \
  https://api.cloudflare.com/client/v4/accounts/<ACCOUNT_ID>/workers/scripts/<SCRIPT_NAME>/subdomain \
  --data '{"enabled":true,"previews_enabled":true}'
```

3. Сделать обычный redeploy:

```bash
npx wrangler@latest deploy --env ''
```

На BALABOLKA это дало рабочий публичный `workers.dev` URL без ручного копания в dashboard.

## Local dev scaffold

Локальные секреты для Workers path:

```bash
cd /Users/alex/Developer/BALABOLKA/proxy
cp .dev.vars.example .dev.vars
```

Заполнить:

- `GEMINI_API_KEY`
- `PROXY_BEARER_TOKEN`
- при необходимости модели и retry-параметры

Важно:

- `.dev.vars` не коммитится;
- не смешивать `.dev.vars` и `.env` для одного и того же local Workers-run;
- текущий Node dev flow продолжает жить через `.env`, а не через `.dev.vars`.

## Что уже подготовлено в wrangler config

В `proxy/wrangler.jsonc` заранее описано:

- имя Worker;
- `main = "src/worker.ts"` как фактическая точка входа;
- `compatibility_date`;
- `nodejs_compat` как минимальный мост для будущего runtime audit;
- `workers_dev = true` для простого начального деплоя без custom route;
- `staging` и `production` environments.

Это намеренно не ломает текущий Node workflow.

## Что уже реализовано в worker runtime

- `GET /healthz`
- `GET /v1/tts/catalog`
- `POST /v1/tts/synthesize`
- optional bearer auth через `PROXY_BEARER_TOKEN` для legacy/manual режима
- общий runtime config и общее handler-ядро между Node и Workers

Следующий практический шаг уже не написание entrypoint, а live smoke/deploy, проверка одного proxy-request ceiling и end-to-end long-form цепочки на реальных лимитах Workers.

## Секреты в deployed Worker

Когда Worker entrypoint появится, секреты загружаются отдельно:

```bash
cd /Users/alex/Developer/BALABOLKA/proxy
npx wrangler@latest secret put GEMINI_API_KEY
```

`PROXY_BEARER_TOKEN` теперь не обязателен. Для текущего production iPhone path bearer intentionally выключен, чтобы приложение не хранило пользовательский секрет и не требовало ручного ввода токена в UI. Если понадобится временно вернуть legacy bearer-защиту для узкого сценария, секрет можно снова добавить вручную.

Для environment-specific deploy:

```bash
npx wrangler@latest secret put GEMINI_API_KEY --env staging
npx wrangler@latest secret put PROXY_BEARER_TOKEN --env staging
```

Не кладите секреты в `vars` внутри `wrangler.jsonc`.

## Deploy commands

Staging:

```bash
cd /Users/alex/Developer/BALABOLKA/proxy
npx wrangler@latest deploy --env staging
```

Production:

```bash
cd /Users/alex/Developer/BALABOLKA/proxy
npx wrangler@latest deploy --env production
```

Если routing не настроен, Worker будет жить на `*.workers.dev`.

Для top-level worker в этом проекте уже проверен и рабочий деплой через:

```bash
cd /Users/alex/Developer/BALABOLKA/proxy
npx wrangler@latest deploy --env ''
```

## Практический rollout-порядок

1. Авторизовать Wrangler.
2. Залить `GEMINI_API_KEY` и `PROXY_BEARER_TOKEN`.
3. При необходимости включить script-level `workers.dev` через API.
4. Задеплоить Worker.
5. Прогнать `healthz`, `catalog` и короткие synth smoke-тесты.
6. Проверить memory и CPU на одном запросе у ceiling `12000` и на end-to-end long-form прогонах до `128000`.
7. После этого переключить iPhone app на HTTPS URL Worker.

## Итоговая рекомендация

На сегодня Cloudflare Workers для BALABOLKA уже не просто scaffold, а живой бесплатный backend path. Node/Express path всё ещё нужен для локального dev и как запасной Cloud Run fallback, но повседневная iPhone-цепочка теперь может работать напрямую через Workers без участия iMac.
