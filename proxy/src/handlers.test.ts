import test from "node:test";
import assert from "node:assert/strict";

import { mapHttpError } from "./handlers.js";

test("mapHttpError exposes Gemini quota exhaustion as 429", () => {
  const mapped = mapHttpError(
    new Error(
      'Gemini TTS failed after 3 attempt(s): Gemini API 429: {"error":{"message":"Quota exceeded for metric: generativelanguage.googleapis.com/generate_requests_per_model_per_day, limit: 100"}}',
    ),
  );

  assert.equal(mapped.status, 429);
  assert.equal(mapped.body.error, "UPSTREAM_QUOTA_EXCEEDED");
  assert.equal(mapped.body.quotaScope, "daily");
});
