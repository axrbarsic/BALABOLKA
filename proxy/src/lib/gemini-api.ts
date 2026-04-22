type GenerateContentInput = {
  model: string;
  contents: unknown;
  config?: Record<string, unknown> | undefined;
};

type GenerateContentOutput = {
  text?: string;
  candidates?: Array<{
    content?: {
      parts?: Array<{
        text?: string;
        inlineData?: {
          data?: string;
          mimeType?: string;
        };
      }>;
    };
  }>;
};

export type GeminiApiClient = {
  models: {
    generateContent(input: GenerateContentInput): Promise<GenerateContentOutput>;
  };
};

type GeminiApiClientOptions = {
  apiKey: string;
};

function normalizeContents(contents: unknown): unknown {
  if (typeof contents === "string") {
    return [{ role: "user", parts: [{ text: contents }] }];
  }

  return contents;
}

function extractResponseText(payload: unknown): string {
  const candidates =
    (payload as {
      candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
    }).candidates ?? [];

  const parts = candidates[0]?.content?.parts ?? [];

  return parts
    .map((part) => part.text?.trim())
    .filter((value): value is string => Boolean(value))
    .join("\n")
    .trim();
}

export function createGeminiApiClient(
  options: GeminiApiClientOptions,
): GeminiApiClient {
  return {
    models: {
      async generateContent(input: GenerateContentInput): Promise<GenerateContentOutput> {
        const response = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(
            input.model,
          )}:generateContent`,
          {
            method: "POST",
            headers: {
              "content-type": "application/json",
              "x-goog-api-key": options.apiKey,
            },
            body: JSON.stringify({
              contents: normalizeContents(input.contents),
              generationConfig: input.config,
            }),
          },
        );

        const rawText = await response.text();

        if (!response.ok) {
          const error = new Error(
            `Gemini API ${response.status}: ${rawText.slice(0, 400)}`,
          ) as Error & { status?: number };
          error.status = response.status;
          throw error;
        }

        const parsedPayload = JSON.parse(rawText) as GenerateContentOutput;
        const extractedText = extractResponseText(parsedPayload);

        return extractedText
          ? {
              ...parsedPayload,
              text: extractedText,
            }
          : parsedPayload;
      },
    },
  };
}
