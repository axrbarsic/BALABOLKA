import express from "express";

import { createBearerAuthMiddleware } from "./auth.js";
import { config } from "./config.js";
import {
  buildCatalogPayload,
  buildHealthPayload,
  mapHttpError,
  synthesizeFromBody,
} from "./handlers.js";

export const app = express();

app.disable("x-powered-by");
app.use(express.json({ limit: "1mb" }));

app.get("/healthz", (_request, response) => {
  response.json(buildHealthPayload(config));
});

app.use("/v1", createBearerAuthMiddleware(config.bearerToken));

app.get("/v1/tts/catalog", (_request, response) => {
  response.json(buildCatalogPayload());
});

app.post("/v1/tts/synthesize", async (request, response, next) => {
  try {
    response.json(await synthesizeFromBody(request.body, config));
  } catch (error) {
    next(error);
  }
});

app.use(
  (
    error: unknown,
    _request: express.Request,
    response: express.Response,
    _next: express.NextFunction,
  ) => {
    const mappedError = mapHttpError(error);
    response.status(mappedError.status).json(mappedError.body);
  },
);
