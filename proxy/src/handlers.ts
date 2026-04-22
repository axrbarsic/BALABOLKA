import { createHash, randomUUID } from "node:crypto";

import { ZodError, z } from "zod";

import type { RuntimeConfig } from "./config.js";
import { createGeminiClient } from "./lib/gemini.js";
import type { TtsSynthesisResult } from "./lib/gemini.js";
import { buildPromptChunks, preparePrompt } from "./lib/preprocessor.js";
import {
  PRESETS,
  VOICES,
  resolveCombineMode,
  resolvePresetCollection,
  resolveVoice,
} from "./lib/presets.js";
import { concatenateWavBuffers } from "./lib/wav.js";

const PRODUCT_SOURCE_TEXT_MAX_CHARACTERS = 12_000;
const MODEL_TTS_INPUT_TOKEN_LIMIT = 8_192;
const MODEL_TTS_OUTPUT_TOKEN_LIMIT = 16_384;
const TTS_CHUNK_MAX_CHARACTERS = 850;
const TTS_CHUNK_MAX_SEGMENTS = 5;
const TTS_CHUNK_PARALLELISM = 3;

const synthesizeRequestSchema = z.object({
  id: z.string().trim().min(1).max(120).optional(),
  title: z.string().trim().min(1).max(200).optional(),
  text: z.string().trim().min(1).max(PRODUCT_SOURCE_TEXT_MAX_CHARACTERS),
  preset: z.string().trim().min(1).max(80).optional(),
  presetIds: z.array(z.string().trim().min(1).max(80)).min(1).max(6).optional(),
  combineMode: z.enum(["auto", "blend", "sequence"]).optional(),
  voice: z.string().trim().min(1).max(80).optional(),
  usePromptPreprocessor: z.boolean().optional(),
});

export function buildHealthPayload(config: RuntimeConfig) {
  return {
    ok: true,
    authEnabled: Boolean(config.bearerToken),
    ttsModel: config.geminiTtsModel,
    preprocessorModel: config.geminiPreprocessorModel,
    preprocessorFallbackModel: config.geminiPreprocessorFallbackModel,
    promptPreprocessorEnabled: config.enablePromptPreprocessor,
    limits: {
      sourceTextMaxCharacters: PRODUCT_SOURCE_TEXT_MAX_CHARACTERS,
      ttsInputTokenLimit: MODEL_TTS_INPUT_TOKEN_LIMIT,
      ttsOutputTokenLimit: MODEL_TTS_OUTPUT_TOKEN_LIMIT,
      chunkingEnabled: true,
    },
  };
}

export function buildCatalogPayload() {
  return {
    presets: Object.values(PRESETS).map((preset) => ({
      id: preset.id,
      label: preset.label,
      description: preset.description,
      defaultVoice: preset.defaultVoice,
    })),
    combineModes: ["auto", "blend", "sequence"],
    voices: VOICES,
    limits: {
      sourceTextMaxCharacters: PRODUCT_SOURCE_TEXT_MAX_CHARACTERS,
      ttsInputTokenLimit: MODEL_TTS_INPUT_TOKEN_LIMIT,
      ttsOutputTokenLimit: MODEL_TTS_OUTPUT_TOKEN_LIMIT,
      chunkingEnabled: true,
    },
  };
}

async function mapWithConcurrency<TInput, TOutput>(
  values: TInput[],
  concurrency: number,
  mapper: (value: TInput, index: number) => Promise<TOutput>,
): Promise<TOutput[]> {
  const resolvedValues = new Array<TOutput>(values.length);
  let currentIndex = 0;

  async function worker() {
    while (currentIndex < values.length) {
      const index = currentIndex;
      currentIndex += 1;
      const value = values[index];
      if (value === undefined) {
        break;
      }
      resolvedValues[index] = await mapper(value, index);
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(concurrency, values.length) }, () => worker()),
  );

  return resolvedValues;
}

function mergeSynthesisResults(results: TtsSynthesisResult[]): TtsSynthesisResult {
  const firstResult = results[0];

  if (!firstResult) {
    throw new Error("No synthesis results to merge.");
  }

  const mergedWavBuffer = concatenateWavBuffers(
    results.map((result) => result.wavBuffer),
    {
      sampleRateHz: firstResult.sampleRateHz,
      channels: firstResult.channels,
      bitsPerSample: firstResult.bitDepth,
    },
  );

  return {
    wavBuffer: mergedWavBuffer,
    wavBase64: mergedWavBuffer.toString("base64"),
    wavBytes: mergedWavBuffer.length,
    durationMs: results.reduce((sum, result) => sum + result.durationMs, 0),
    sampleRateHz: firstResult.sampleRateHz,
    channels: firstResult.channels,
    bitDepth: firstResult.bitDepth,
    convertedFromPcm: results.some((result) => result.convertedFromPcm),
    rawMimeType: firstResult.rawMimeType,
    hashSha256: createHash("sha256").update(mergedWavBuffer).digest("hex"),
    ttsAttempts: results.reduce((sum, result) => sum + result.ttsAttempts, 0),
  };
}

async function synthesizePreparedPrompt(
  geminiClient: ReturnType<typeof createGeminiClient>,
  preparedPrompt: Awaited<ReturnType<typeof preparePrompt>>,
  voiceName: string,
): Promise<TtsSynthesisResult> {
  const promptChunks = buildPromptChunks(preparedPrompt, {
    maxCharacters: TTS_CHUNK_MAX_CHARACTERS,
    maxSegments: TTS_CHUNK_MAX_SEGMENTS,
  });

  if (promptChunks.length <= 1) {
    return geminiClient.synthesizeSpeech({
      prompt: preparedPrompt.preparedPrompt,
      voiceName,
    });
  }

  const chunkResults = await mapWithConcurrency(
    promptChunks,
    TTS_CHUNK_PARALLELISM,
    async (chunk) =>
      geminiClient.synthesizeSpeech({
        prompt: chunk.prompt,
        voiceName,
      }),
  );

  preparedPrompt.warnings = [
    ...preparedPrompt.warnings,
    `Long transcript split into ${promptChunks.length} TTS chunks.`,
  ];

  return mergeSynthesisResults(chunkResults);
}

export async function synthesizeFromBody(
  inputBody: unknown,
  config: RuntimeConfig,
) {
  const body = synthesizeRequestSchema.parse(inputBody);
  const requestId = body.id ?? randomUUID();
  const resolvedPresetCollection = resolvePresetCollection({
    preset: body.preset,
    presetIds: body.presetIds,
  });
  const presets = resolvedPresetCollection.presets;
  const primaryPreset = presets[0] ?? PRESETS.neutral;
  const combineMode = resolveCombineMode(body.combineMode, presets.length);
  const voice = resolveVoice(body.voice, primaryPreset);
  const useModelPreprocessor =
    body.usePromptPreprocessor ?? config.enablePromptPreprocessor;

  const geminiClient = createGeminiClient({
    apiKey: config.geminiApiKey,
    ttsModel: config.geminiTtsModel,
    ttsMaxRetries: config.ttsMaxRetries,
  });

  let preparedPrompt = await preparePrompt({
    ai: geminiClient.ai,
    model: config.geminiPreprocessorModel,
    fallbackModel: config.geminiPreprocessorFallbackModel,
    presets,
    combineMode,
    sourceText: body.text,
    title: body.title,
    requestId,
    voice,
    useModelPreprocessor,
  });
  let synthesizedAudio;

  try {
    synthesizedAudio = await synthesizePreparedPrompt(
      geminiClient,
      preparedPrompt,
      voice.name,
    );
  } catch (error) {
    const canRetryWithFallbackPrompt = useModelPreprocessor;

    if (!canRetryWithFallbackPrompt) {
      throw error;
    }

    const fallbackPreparedPrompt =
      preparedPrompt.mode === "fallback"
        ? preparedPrompt
        : await preparePrompt({
            ai: geminiClient.ai,
            model: config.geminiPreprocessorModel,
            fallbackModel: config.geminiPreprocessorFallbackModel,
            presets,
            combineMode,
            sourceText: body.text,
            title: body.title,
            requestId,
            voice,
            useModelPreprocessor: false,
          });

    preparedPrompt = {
      ...fallbackPreparedPrompt,
      warnings: [
        ...fallbackPreparedPrompt.warnings,
        `Model-prepared prompt TTS failed, fallback prompt retried: ${
          error instanceof Error ? error.message : "unknown error"
        }`,
      ],
    };

    synthesizedAudio = await synthesizePreparedPrompt(
      geminiClient,
      preparedPrompt,
      voice.name,
    );
  }

  return {
    requestId,
    sourceText: body.text,
    metadata: {
      id: body.id ?? null,
      title: body.title ?? null,
    },
    preset: {
      id: primaryPreset.id,
      label: primaryPreset.label,
      description: primaryPreset.description,
    },
    presets: preparedPrompt.presets,
    combineMode,
    voice,
    prompt: {
      preparedPrompt: preparedPrompt.preparedPrompt,
      preparedTranscript: preparedPrompt.preparedTranscript,
      mode: preparedPrompt.mode,
      preprocessorModel: preparedPrompt.preprocessorModel ?? null,
      audioProfile: preparedPrompt.audioProfile,
      scene: preparedPrompt.scene,
      directorNotes: {
        style: preparedPrompt.style,
        pacing: preparedPrompt.pacing,
        breathing: preparedPrompt.breathing,
        articulation: preparedPrompt.articulation,
        sampleContext: preparedPrompt.sampleContext,
      },
      audioTags: preparedPrompt.audioTags,
      notes: preparedPrompt.notes,
      warnings: preparedPrompt.warnings,
      plan: {
        combineMode: preparedPrompt.combineMode,
        presets: preparedPrompt.presets,
        segments: preparedPrompt.segments,
      },
    },
    audio: {
      mimeType: "audio/wav",
      base64: synthesizedAudio.wavBase64,
      bytes: synthesizedAudio.wavBytes,
      durationMs: synthesizedAudio.durationMs,
      sampleRateHz: synthesizedAudio.sampleRateHz,
      channels: synthesizedAudio.channels,
      bitDepth: synthesizedAudio.bitDepth,
      convertedFromPcm: synthesizedAudio.convertedFromPcm,
      rawMimeType: synthesizedAudio.rawMimeType,
      sha256: synthesizedAudio.hashSha256,
    },
    provider: {
      ttsModel: config.geminiTtsModel,
      preprocessorModel:
        preparedPrompt.mode === "model"
          ? preparedPrompt.preprocessorModel ?? null
          : null,
      ttsAttempts: synthesizedAudio.ttsAttempts,
      promptPreprocessorUsed: preparedPrompt.mode === "model",
      timestamp: new Date().toISOString(),
    },
  };
}

export function mapHttpError(error: unknown) {
  const errorMessage =
    typeof error === "object" &&
    error !== null &&
    "message" in error &&
    typeof (error as { message?: unknown }).message === "string"
      ? (error as { message: string }).message
      : undefined;

  if (error instanceof ZodError) {
    return {
      status: 400,
      body: {
        error: "INVALID_REQUEST",
        details: error.flatten(),
      },
    };
  }

  if (error instanceof Error && error.message.startsWith("Unsupported")) {
    return {
      status: 400,
      body: {
        error: "INVALID_REQUEST",
        message: error.message,
      },
    };
  }

  if (errorMessage) {
    if (errorMessage.includes("Gemini API 429") || /quota exceeded/i.test(errorMessage)) {
      const quotaScope = /per_model_per_day|requests per day|generate_requests_per_model_per_day/i.test(
        errorMessage,
      )
        ? "daily"
        : "burst";

      return {
        status: 429,
        body: {
          error: "UPSTREAM_QUOTA_EXCEEDED",
          quotaScope,
          message: errorMessage,
        },
      };
    }
  }

  return {
    status: 500,
    body: {
      error: "INTERNAL_ERROR",
      message: errorMessage ?? "Unknown server error.",
    },
  };
}
