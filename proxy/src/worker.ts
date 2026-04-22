import { isAuthorizedHeader, unauthorizedBody } from "./auth.js";
import { assertRuntimeConfig, buildConfig } from "./config.js";
import {
  buildCatalogPayload,
  buildHealthPayload,
  mapHttpError,
  synthesizeFromBody,
} from "./handlers.js";

type WorkerEnv = Record<string, string | undefined>;

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

export default {
  async fetch(request: Request, env: WorkerEnv): Promise<Response> {
    try {
      const runtimeConfig = buildConfig(env);
      assertRuntimeConfig(runtimeConfig);

      const url = new URL(request.url);

      if (request.method === "GET" && url.pathname === "/healthz") {
        return jsonResponse(buildHealthPayload(runtimeConfig));
      }

      if (url.pathname.startsWith("/v1")) {
        if (
          !isAuthorizedHeader(
            request.headers.get("authorization"),
            runtimeConfig.bearerToken,
          )
        ) {
          return jsonResponse(unauthorizedBody(), 401);
        }
      }

      if (request.method === "GET" && url.pathname === "/v1/tts/catalog") {
        return jsonResponse(buildCatalogPayload());
      }

      if (request.method === "POST" && url.pathname === "/v1/tts/synthesize") {
        const requestBody = await request.json();
        return jsonResponse(await synthesizeFromBody(requestBody, runtimeConfig));
      }

      return jsonResponse(
        {
          error: "NOT_FOUND",
          message: "Unknown endpoint.",
        },
        404,
      );
    } catch (error) {
      const mappedError = mapHttpError(error);
      return jsonResponse(mappedError.body, mappedError.status);
    }
  },
};
