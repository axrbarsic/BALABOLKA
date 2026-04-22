import test from "node:test";
import assert from "node:assert/strict";

import { buildPromptChunks, preparePrompt } from "./preprocessor.js";
import { PRESETS } from "./presets.js";

function createMockAi(
  handler: (input: { model: string; contents: unknown }) => Promise<unknown> | unknown,
) {
  return {
    models: {
      generateContent(input: { model: string; contents: unknown }) {
        return handler(input);
      },
    },
  } as never;
}

const baseInput = {
  sourceText: "Первая фраза. Вторая фраза. Третья фраза.",
  title: "Тест",
  requestId: "req-1",
  voice: {
    name: "Enceladus",
    descriptor: "Breathy",
  },
};

test("preparePrompt keeps single preset fallback behavior", async () => {
  const prepared = await preparePrompt({
    ai: createMockAi(() => {
      throw new Error("should not be called");
    }),
    model: "gemini-3-flash-preview",
    presets: [PRESETS.whisper],
    combineMode: "single",
    useModelPreprocessor: false,
    ...baseInput,
  });

  assert.equal(prepared.mode, "fallback");
  assert.equal(prepared.combineMode, "single");
  assert.equal(prepared.presets.length, 1);
  assert.equal(prepared.presets[0]?.id, "whisper");
  assert.match(prepared.preparedTranscript, /\[whispers\]/);
  assert.equal(prepared.segments.length, 3);
});

test("preparePrompt returns structured segment plan for mixed presets", async () => {
  const prepared = await preparePrompt({
    ai: createMockAi(({ model }) => {
      assert.equal(model, "gemini-3-flash-preview");

      return {
        text: JSON.stringify({
          audioProfile: "Mixed expressive narrator",
          style: "Blend irony with fatigue in a controlled single-speaker read.",
          transcript: "unused fallback transcript",
          segmentPlan: [
            {
              presetId: "sarcasm",
              text: "Первая фраза.",
              audioTags: ["[sarcastic]"],
              directorNote: "Dry and unimpressed opening.",
              placement: "opening",
            },
            {
              presetId: "tired",
              text: "Вторая фраза. Третья фраза.",
              audioTags: ["[tired]"],
              directorNote: "Let the energy sag without losing clarity.",
              placement: "closing",
            },
          ],
        }),
      };
    }),
    model: "gemini-3-flash-preview",
    presets: [PRESETS.sarcasm, PRESETS.tired],
    combineMode: "auto",
    useModelPreprocessor: true,
    ...baseInput,
  });

  assert.equal(prepared.mode, "model");
  assert.equal(prepared.preprocessorModel, "gemini-3-flash-preview");
  assert.equal(prepared.combineMode, "auto");
  assert.deepEqual(
    prepared.segments.map((segment) => segment.presetId),
    ["sarcasm", "tired"],
  );
  assert.match(prepared.preparedTranscript, /\[sarcastic\]/);
  assert.match(prepared.preparedTranscript, /\[tired\]/);
  assert.match(prepared.preparedPrompt, /### PERFORMANCE MAP/);
});

test("preparePrompt falls back to deterministic mixed coverage when model omits segmentPlan", async () => {
  const prepared = await preparePrompt({
    ai: createMockAi(() => ({
      text: JSON.stringify({
        transcript: "Первая фраза. Вторая фраза. Третья фраза.",
      }),
    })),
    model: "gemini-3-flash-preview",
    presets: [PRESETS.laugh, PRESETS.cry, PRESETS.cough],
    combineMode: "auto",
    useModelPreprocessor: true,
    ...baseInput,
  });

  assert.equal(prepared.mode, "model");
  assert.ok(prepared.segments.length >= 3);
  assert.ok(new Set(prepared.segments.map((segment) => segment.presetId)).size >= 2);
  assert.match(prepared.preparedTranscript, /\[(laughs|crying|cough|trembling)\]/);
});

test("preparePrompt distributes mixed presets across short fallback text", async () => {
  const prepared = await preparePrompt({
    ai: createMockAi(() => {
      throw new Error("force fallback");
    }),
    model: "gemini-3-flash-preview",
    presets: [PRESETS.quiet, PRESETS.laugh, PRESETS.cough],
    combineMode: "auto",
    useModelPreprocessor: true,
    sourceText: "Первая фраза, в которой ещё есть место для улыбки. Вторая фраза, после которой слышен сухой кашель.",
    title: "Короткий тест",
    requestId: "req-short",
    voice: baseInput.voice,
  });

  assert.equal(prepared.mode, "fallback");
  assert.ok(new Set(prepared.segments.map((segment) => segment.presetId)).size >= 2);
  assert.match(prepared.preparedTranscript, /\[(laughs|giggles|cough)\]/);
});

test("preparePrompt retries with configured fallback model before deterministic fallback", async () => {
  const calledModels: string[] = [];

  const prepared = await preparePrompt({
    ai: createMockAi(({ model }) => {
      calledModels.push(model);

      if (model === "gemini-3-flash-preview") {
        throw new Error("flash failed");
      }

      return {
        text: JSON.stringify({
          transcript: "Финальная фраза.",
          segmentPlan: [
            {
              presetId: "anger",
              text: "Финальная фраза.",
              audioTags: ["[shouting]"],
            },
          ],
        }),
      };
    }),
    model: "gemini-3-flash-preview",
    fallbackModel: "gemini-3.1-pro-preview",
    presets: [PRESETS.anger, PRESETS.heavy_breathing],
    combineMode: "blend",
    useModelPreprocessor: true,
    ...baseInput,
  });

  assert.deepEqual(calledModels, [
    "gemini-3-flash-preview",
    "gemini-3.1-pro-preview",
  ]);
  assert.equal(prepared.mode, "model");
  assert.equal(prepared.preprocessorModel, "gemini-3.1-pro-preview");
  assert.equal(prepared.segments[0]?.presetId, "anger");
});

test("buildPromptChunks splits oversized single segment into bounded chunks", () => {
  const preparedPrompt = {
    preparedPrompt: "unused",
    preparedTranscript:
      "[quiet] Первое длинное предложение для проверки лимита. Второе длинное предложение для проверки лимита. Третье длинное предложение для проверки лимита.",
    audioProfile: "Quiet narrator",
    scene: "Test scene",
    style: "Controlled",
    pacing: "Measured",
    breathing: "Light",
    articulation: "Clear",
    sampleContext: "Test context",
    audioTags: ["[quiet]"],
    notes: [],
    mode: "fallback" as const,
    warnings: [],
    presets: [
      {
        id: "quiet" as const,
        label: PRESETS.quiet.label,
        description: PRESETS.quiet.description,
      },
    ],
    combineMode: "single" as const,
    segments: [
      {
        index: 0,
        presetId: "quiet" as const,
        presetLabel: PRESETS.quiet.label,
        placement: "opening" as const,
        text:
          "Первое длинное предложение для проверки лимита. Второе длинное предложение для проверки лимита. Третье длинное предложение для проверки лимита.",
        audioTags: ["[quiet]"],
        directorNote: "Stay controlled.",
      },
    ],
  };

  const chunks = buildPromptChunks(preparedPrompt, {
    maxCharacters: 80,
    maxSegments: 2,
  });

  assert.ok(chunks.length >= 2);
  assert.ok(chunks.every((chunk) => chunk.transcript.length <= 80));
  assert.ok(chunks.every((chunk) => chunk.prompt.includes("### TRANSCRIPT")));
});
