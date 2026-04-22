import "dotenv/config";

const DEFAULT_PORT = 8787;
const DEFAULT_TTS_MODEL = "gemini-3.1-flash-tts-preview";
const DEFAULT_PREPROCESSOR_MODEL = "gemini-2.5-flash-lite";
const DEFAULT_PREPROCESSOR_FALLBACK_MODEL = "gemini-2.5-flash";

export type RuntimeEnv = Record<string, string | undefined>;
export type RuntimeConfig = {
  port: number;
  geminiApiKey: string;
  bearerToken: string;
  geminiTtsModel: string;
  geminiPreprocessorModel: string;
  geminiPreprocessorFallbackModel: string;
  enablePromptPreprocessor: boolean;
  ttsMaxRetries: number;
};

function readNumberEnv(name: string, fallback: number): number {
  const rawValue = process.env[name];

  if (!rawValue) {
    return fallback;
  }

  const parsedValue = Number.parseInt(rawValue, 10);
  return Number.isFinite(parsedValue) ? parsedValue : fallback;
}

function readBooleanEnv(name: string, fallback: boolean): boolean {
  const rawValue = process.env[name];

  if (!rawValue) {
    return fallback;
  }

  return ["1", "true", "yes", "on"].includes(rawValue.toLowerCase());
}

export function buildConfig(env: RuntimeEnv): RuntimeConfig {
  return {
    port: readNumberEnv("PORT", DEFAULT_PORT),
    geminiApiKey: env.GEMINI_API_KEY ?? env.GOOGLE_API_KEY ?? "",
    bearerToken: env.PROXY_BEARER_TOKEN?.trim() || "",
    geminiTtsModel: env.GEMINI_TTS_MODEL?.trim() || DEFAULT_TTS_MODEL,
    geminiPreprocessorModel:
      env.GEMINI_PREPROCESSOR_MODEL?.trim() || DEFAULT_PREPROCESSOR_MODEL,
    geminiPreprocessorFallbackModel:
      env.GEMINI_PREPROCESSOR_FALLBACK_MODEL?.trim() ||
      DEFAULT_PREPROCESSOR_FALLBACK_MODEL,
    enablePromptPreprocessor: readBooleanEnv("ENABLE_PROMPT_PREPROCESSOR", true),
    ttsMaxRetries: readNumberEnv("TTS_MAX_RETRIES", 2),
  };
}

export const config = buildConfig(process.env as RuntimeEnv);

export function assertRuntimeConfig(runtimeConfig: RuntimeConfig = config): void {
  if (!runtimeConfig.geminiApiKey) {
    throw new Error(
      "Отсутствует GEMINI_API_KEY. Задайте GEMINI_API_KEY или GOOGLE_API_KEY в окружении.",
    );
  }
}
