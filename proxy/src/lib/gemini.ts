import { createHash } from "node:crypto";

import { createGeminiApiClient } from "./gemini-api.js";
import { ensureWavBuffer, estimateDurationMs } from "./wav.js";

export type GeminiClientOptions = {
  apiKey: string;
  ttsModel: string;
  ttsMaxRetries: number;
};

export type TtsSynthesisInput = {
  prompt: string;
  voiceName: string;
};

export type TtsSynthesisResult = {
  wavBuffer: Buffer;
  wavBase64: string;
  wavBytes: number;
  durationMs: number;
  sampleRateHz: number;
  channels: number;
  bitDepth: number;
  convertedFromPcm: boolean;
  rawMimeType: string;
  hashSha256: string;
  ttsAttempts: number;
};

type RetryableError = Error & {
  retryable?: boolean;
};

function createRetryableError(message: string): RetryableError {
  const error = new Error(message) as RetryableError;
  error.retryable = true;
  return error;
}

function readResponseText(response: unknown): string {
  const maybeResponse = response as { text?: unknown };

  if (typeof maybeResponse.text === "string") {
    return maybeResponse.text;
  }

  if (typeof maybeResponse.text === "function") {
    const value = maybeResponse.text();
    return typeof value === "string" ? value : "";
  }

  return "";
}

function extractAudioPart(response: unknown) {
  const parts =
    (response as { candidates?: Array<{ content?: { parts?: Array<unknown> } }> }).candidates?.[0]
      ?.content?.parts ?? [];

  for (const part of parts) {
    const inlineData = (part as { inlineData?: { data?: string; mimeType?: string } }).inlineData;

    if (inlineData?.data) {
      return {
        data: inlineData.data,
        mimeType: inlineData.mimeType,
      };
    }
  }

  const textFallback = readResponseText(response);

  throw createRetryableError(
    `Gemini TTS response did not contain audio data. Text fallback: ${textFallback.slice(
      0,
      300,
    )}`,
  );
}

function shouldRetry(error: unknown): boolean {
  if (typeof error !== "object" || error === null) {
    return false;
  }

  if ("retryable" in error && (error as RetryableError).retryable) {
    return true;
  }

  const maybeApiError = error as { status?: number; message?: string };
  const retryableStatuses = new Set([429, 500, 502, 503, 504]);

  if (maybeApiError.status && retryableStatuses.has(maybeApiError.status)) {
    return true;
  }

  return maybeApiError.message?.includes("audio") ?? false;
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

export function createGeminiClient(options: GeminiClientOptions) {
  const ai = createGeminiApiClient({ apiKey: options.apiKey });

  return {
    ai,
    async synthesizeSpeech(input: TtsSynthesisInput): Promise<TtsSynthesisResult> {
      let lastError: unknown;

      for (let attemptIndex = 0; attemptIndex <= options.ttsMaxRetries; attemptIndex += 1) {
        try {
          const response = await ai.models.generateContent({
            model: options.ttsModel,
            contents: [{ parts: [{ text: input.prompt }] }],
            config: {
              responseModalities: ["AUDIO"],
              speechConfig: {
                voiceConfig: {
                  prebuiltVoiceConfig: {
                    voiceName: input.voiceName,
                  },
                },
              },
            },
          });

          const audioPart = extractAudioPart(response);
          const audioBuffer = Buffer.from(audioPart.data, "base64");
          const ensuredWav = ensureWavBuffer(audioBuffer, audioPart.mimeType);
          const durationMs = estimateDurationMs(audioBuffer.length, ensuredWav.format);
          const wavBase64 = ensuredWav.wavBuffer.toString("base64");

          return {
            wavBuffer: ensuredWav.wavBuffer,
            wavBase64,
            wavBytes: ensuredWav.wavBuffer.length,
            durationMs,
            sampleRateHz: ensuredWav.format.sampleRateHz,
            channels: ensuredWav.format.channels,
            bitDepth: ensuredWav.format.bitsPerSample,
            convertedFromPcm: ensuredWav.convertedFromPcm,
            rawMimeType: ensuredWav.rawMimeType,
            hashSha256: createHash("sha256")
              .update(ensuredWav.wavBuffer)
              .digest("hex"),
            ttsAttempts: attemptIndex + 1,
          };
        } catch (error) {
          lastError = error;

          if (!shouldRetry(error) || attemptIndex >= options.ttsMaxRetries) {
            break;
          }

          await delay((attemptIndex + 1) * 350);
        }
      }

      throw new Error(
        `Gemini TTS failed after ${options.ttsMaxRetries + 1} attempt(s): ${
          lastError instanceof Error ? lastError.message : "unknown error"
        }`,
      );
    },
  };
}
