import { z } from "zod";

import type { GeminiApiClient } from "./gemini-api.js";
import type {
  EffectiveCombineMode,
  PresetDefinition,
  PresetId,
} from "./presets.js";

function normalizeStringList(
  value: unknown,
  options: { maxItems: number; maxLength: number },
): string[] | undefined {
  const collect = (input: unknown): string[] => {
    if (typeof input === "string") {
      return input
        .split(/\n+|[|;,](?=\s|\[|[A-Za-zА-Яа-яЁё])/)
        .map((item) => item.trim())
        .filter(Boolean);
    }

    if (Array.isArray(input)) {
      return input
        .flatMap((item) => collect(item))
        .map((item) => item.trim())
        .filter(Boolean);
    }

    return [];
  };

  const normalized = Array.from(new Set(collect(value))).slice(0, options.maxItems);
  if (normalized.length === 0) {
    return undefined;
  }

  return normalized.map((item) => item.slice(0, options.maxLength));
}

function normalizePlacement(value: unknown): "opening" | "body" | "closing" | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const normalized = value.trim().toLowerCase();

  if (["opening", "open", "start", "intro", "beginning", "lead"].includes(normalized)) {
    return "opening";
  }

  if (["body", "middle", "mid", "center", "core"].includes(normalized)) {
    return "body";
  }

  if (["closing", "close", "end", "ending", "outro", "finish", "final"].includes(normalized)) {
    return "closing";
  }

  return undefined;
}

const TAG_LIST_SCHEMA = z
  .preprocess(
    (value) => normalizeStringList(value, { maxItems: 12, maxLength: 40 }),
    z.array(z.string().trim().min(1).max(40)).max(12).optional(),
  );

const NOTES_LIST_SCHEMA = z
  .preprocess(
    (value) => normalizeStringList(value, { maxItems: 8, maxLength: 240 }),
    z.array(z.string().trim().min(1).max(240)).max(8).optional(),
  );

const SEGMENT_PLAN_SCHEMA = z.object({
  presetId: z.string().trim().min(1).max(80),
  text: z.string().trim().min(1).max(4000),
  audioTags: z
    .preprocess(
      (value) => normalizeStringList(value, { maxItems: 4, maxLength: 40 }),
      z.array(z.string().trim().min(1).max(40)).max(4).optional(),
    ),
  directorNote: z.string().trim().min(1).max(240).optional(),
  placement: z
    .preprocess(
      (value) => normalizePlacement(value),
      z.enum(["opening", "body", "closing"]).optional(),
    ),
});

const MODEL_RESPONSE_SCHEMA = z
  .object({
    audioProfile: z.string().trim().min(1).max(120).optional(),
    scene: z.string().trim().min(1).max(700).optional(),
    style: z.string().trim().min(1).max(900).optional(),
    pacing: z.string().trim().min(1).max(700).optional(),
    breathing: z.string().trim().min(1).max(700).optional(),
    articulation: z.string().trim().min(1).max(700).optional(),
    sampleContext: z.string().trim().min(1).max(700).optional(),
    transcript: z.string().trim().min(1).optional(),
    audioTags: TAG_LIST_SCHEMA,
    notes: NOTES_LIST_SCHEMA,
    segmentPlan: z.array(SEGMENT_PLAN_SCHEMA).max(24).optional(),
  })
  .superRefine((value, context) => {
    if (!value.transcript && !value.segmentPlan?.length) {
      context.addIssue({
        code: "custom",
        message: "Model response must include transcript or segmentPlan.",
      });
    }
  });

export type VoiceDescriptor = {
  name: string;
  descriptor: string;
};

export type PreparedPromptSegment = {
  index: number;
  presetId: PresetId;
  presetLabel: string;
  placement: "opening" | "body" | "closing";
  text: string;
  audioTags: string[];
  directorNote: string;
};

export type PreparedPrompt = {
  preparedPrompt: string;
  preparedTranscript: string;
  audioProfile: string;
  scene: string;
  style: string;
  pacing: string;
  breathing: string;
  articulation: string;
  sampleContext: string;
  audioTags: string[];
  notes: string[];
  mode: "model" | "fallback";
  preprocessorModel?: string;
  warnings: string[];
  presets: Array<{
    id: PresetId;
    label: string;
    description: string;
  }>;
  combineMode: EffectiveCombineMode;
  segments: PreparedPromptSegment[];
};

export type PreparedPromptChunk = {
  prompt: string;
  transcript: string;
  segments: PreparedPromptSegment[];
};

type PreparePromptInput = {
  ai: GeminiApiClient;
  model: string;
  fallbackModel?: string | undefined;
  presets: PresetDefinition[];
  combineMode: EffectiveCombineMode;
  sourceText: string;
  title?: string | undefined;
  requestId?: string | undefined;
  voice: VoiceDescriptor;
  useModelPreprocessor: boolean;
};

function primaryPreset(presets: PresetDefinition[]): PresetDefinition {
  const firstPreset = presets[0];

  if (!firstPreset) {
    throw new Error("At least one preset is required.");
  }

  return firstPreset;
}

function presetAt(presets: PresetDefinition[], index: number): PresetDefinition {
  return presets[index] ?? primaryPreset(presets);
}

function normalizeText(text: string): string {
  return text.replace(/\r\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
}

function extractTags(transcript: string): string[] {
  return Array.from(new Set(transcript.match(/\[[^\]]+\]/g) ?? []));
}

function cleanModelJson(rawText: string): string {
  const trimmed = rawText.trim();
  const withoutOpeningFence = trimmed.replace(/^```(?:json)?\s*/i, "");
  const withoutClosingFence = withoutOpeningFence.replace(/\s*```$/, "");
  const firstBrace = withoutClosingFence.indexOf("{");
  const lastBrace = withoutClosingFence.lastIndexOf("}");

  if (firstBrace >= 0 && lastBrace > firstBrace) {
    return withoutClosingFence.slice(firstBrace, lastBrace + 1);
  }

  return withoutClosingFence;
}

function toResponseText(response: unknown): string {
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

function dedupeTags(tags: string[]): string[] {
  return Array.from(new Set(tags));
}

function splitSentences(text: string): string[] {
  return normalizeText(text).split(/(?<=[.!?…])\s+/).filter(Boolean);
}

function splitExpressiveUnits(text: string, targetCount: number): string[] {
  const normalized = normalizeText(text);
  const sentenceUnits = splitSentences(normalized);

  if (sentenceUnits.length >= targetCount || sentenceUnits.length >= 3) {
    return sentenceUnits;
  }

  const clauseUnits = normalized
    .split(/(?<=[.!?…;:])\s+|(?<=,)\s+(?=[\p{Lu}\d"«(])/u)
    .map((value) => normalizeText(value))
    .filter(Boolean);

  if (clauseUnits.length >= targetCount && clauseUnits.length > sentenceUnits.length) {
    return clauseUnits;
  }

  return sentenceUnits.length > 0 ? sentenceUnits : [normalized];
}

function packTextUnits(units: string[], maxCharacters: number): string[] {
  const chunks: string[] = [];
  let currentChunk = "";

  for (const unit of units.map((value) => normalizeText(value)).filter(Boolean)) {
    if (unit.length > maxCharacters) {
      if (currentChunk) {
        chunks.push(currentChunk);
        currentChunk = "";
      }

      const words = unit.split(/\s+/).filter(Boolean);
      let currentWordChunk = "";

      for (const word of words) {
        const candidate = currentWordChunk ? `${currentWordChunk} ${word}` : word;

        if (candidate.length <= maxCharacters) {
          currentWordChunk = candidate;
          continue;
        }

        if (currentWordChunk) {
          chunks.push(currentWordChunk);
          currentWordChunk = "";
        }

        if (word.length <= maxCharacters) {
          currentWordChunk = word;
          continue;
        }

        for (let offset = 0; offset < word.length; offset += maxCharacters) {
          chunks.push(word.slice(offset, offset + maxCharacters));
        }
      }

      if (currentWordChunk) {
        chunks.push(currentWordChunk);
      }

      continue;
    }

    const candidate = currentChunk ? `${currentChunk} ${unit}` : unit;
    if (candidate.length <= maxCharacters) {
      currentChunk = candidate;
      continue;
    }

    if (currentChunk) {
      chunks.push(currentChunk);
    }
    currentChunk = unit;
  }

  if (currentChunk) {
    chunks.push(currentChunk);
  }

  return chunks;
}

function splitOversizedSegment(
  segment: PreparedPromptSegment,
  maxCharacters: number,
): PreparedPromptSegment[] {
  const tagPrefix = segment.audioTags.join(" ").trim();
  const availableCharacters = Math.max(
    24,
    maxCharacters - (tagPrefix ? tagPrefix.length + 1 : 0),
  );
  const sentenceUnits = splitSentences(segment.text);
  const units = sentenceUnits.length > 0 ? sentenceUnits : [segment.text];
  const textChunks = packTextUnits(units, availableCharacters);

  if (textChunks.length <= 1) {
    return [segment];
  }

  return textChunks.map((text, index) => ({
    ...segment,
    index: segment.index + index,
    text,
  }));
}

function toPlacement(index: number, total: number): "opening" | "body" | "closing" {
  if (index === 0) {
    return "opening";
  }

  if (index === total - 1) {
    return "closing";
  }

  return "body";
}

function materializeSegmentText(segment: Pick<PreparedPromptSegment, "text" | "audioTags">): string {
  const prefix = segment.audioTags.join(" ").trim();
  return [prefix, segment.text].filter(Boolean).join(" ").trim();
}

function materializeTranscript(segments: Array<Pick<PreparedPromptSegment, "text" | "audioTags">>): string {
  return segments.map((segment) => materializeSegmentText(segment)).join(" ").trim();
}

function combinePresetDescriptions(
  presets: PresetDefinition[],
  field: keyof Pick<
    PresetDefinition,
    "scene" | "style" | "pacing" | "breathing" | "articulation" | "sampleContext"
  >,
  combineMode: EffectiveCombineMode,
): string {
  if (presets.length === 1) {
    return primaryPreset(presets)[field];
  }

  const modePrefix =
    combineMode === "sequence"
      ? "Move through these preset traits in order as the text progresses"
      : combineMode === "blend"
        ? "Blend these preset traits into one coherent performance"
        : "Intelligently distribute and blend these preset traits across the performance";

  return `${modePrefix}: ${presets
    .map((preset) => `${preset.label}: ${preset[field]}`)
    .join(" | ")}`;
}

function defaultSegmentDirectorNote(preset: PresetDefinition): string {
  return `${preset.label}: ${preset.style}`;
}

function tagText(text: string, preset: PresetDefinition, placement: "opening" | "body" | "closing") {
  const tags: string[] = [];

  if (placement === "opening" && preset.fallbackOpeningTag) {
    tags.push(preset.fallbackOpeningTag);
  }

  if (placement !== "opening" && preset.fallbackMidTag) {
    tags.push(preset.fallbackMidTag);
  }

  return {
    text,
    audioTags: dedupeTags(tags),
  };
}

function selectPresetForSentence(
  sentenceIndex: number,
  sentenceCount: number,
  presets: PresetDefinition[],
  combineMode: EffectiveCombineMode,
): PresetDefinition {
  if (presets.length === 1 || combineMode === "single") {
    return primaryPreset(presets);
  }

  if (combineMode === "sequence") {
    const bucket = Math.min(
      presets.length - 1,
      Math.floor((sentenceIndex * presets.length) / Math.max(sentenceCount, 1)),
    );
    return presetAt(presets, bucket);
  }

  if (combineMode === "blend") {
    return presetAt(presets, sentenceIndex % presets.length);
  }

  if (sentenceCount <= presets.length) {
    return presetAt(presets, sentenceIndex);
  }

  if (sentenceIndex === 0) {
    return primaryPreset(presets);
  }

  return presetAt(presets, (sentenceIndex - 1) % presets.length);
}

function buildFallbackSegments(
  sourceText: string,
  presets: PresetDefinition[],
  combineMode: EffectiveCombineMode,
): PreparedPromptSegment[] {
  const firstPreset = primaryPreset(presets);
  const units =
    presets.length > 1
      ? splitExpressiveUnits(sourceText, Math.min(presets.length, 3))
      : splitSentences(sourceText);
  const safeSentences = units.length > 0 ? units : [normalizeText(sourceText)];

  return safeSentences.map((sentence, index) => {
    const preset = selectPresetForSentence(index, safeSentences.length, presets, combineMode);
    const placement = toPlacement(index, safeSentences.length);
    const tagged = tagText(sentence, preset, placement);

    return {
      index,
      presetId: preset.id,
      presetLabel: preset.label,
      placement,
      text: tagged.text,
      audioTags: tagged.audioTags,
      directorNote:
        presets.length === 1
          ? defaultSegmentDirectorNote(firstPreset)
          : `${defaultSegmentDirectorNote(preset)} Keep the transition coherent with the surrounding segments.`,
    };
  });
}

function hasSufficientPresetCoverage(
  segments: PreparedPromptSegment[],
  presets: PresetDefinition[],
  combineMode: EffectiveCombineMode,
): boolean {
  if (presets.length <= 1 || combineMode === "single") {
    return true;
  }

  const usedPresetIds = new Set(segments.map((segment) => segment.presetId));
  const minimumCoverage = Math.min(2, presets.length, segments.length);
  return usedPresetIds.size >= minimumCoverage;
}

function buildPreparedPrompt(input: {
  title?: string | undefined;
  requestId?: string | undefined;
  transcript: string;
  audioProfile: string;
  scene: string;
  style: string;
  pacing: string;
  breathing: string;
  articulation: string;
  sampleContext: string;
  segments: PreparedPromptSegment[];
}) {
  const performanceMap =
    input.segments.length > 1
      ? [
          "### PERFORMANCE MAP",
          ...input.segments.map((segment) =>
            [
              `- Segment ${segment.index + 1} [${segment.placement}]`,
              `preset=${segment.presetId}`,
              segment.audioTags.length ? `tags=${segment.audioTags.join(", ")}` : undefined,
              `note=${segment.directorNote}`,
            ]
              .filter(Boolean)
              .join("; "),
          ),
        ]
      : [];

  return [
    "Please synthesize speech audio for the following single-speaker performance.",
    "Speak only the text inside the TRANSCRIPT section.",
    "Do not read titles, ids, notes, headings or metadata aloud.",
    "",
    `# AUDIO PROFILE: ${input.audioProfile}`,
    input.title ? `## "${input.title}"` : undefined,
    input.requestId ? `## REQUEST ID: ${input.requestId}` : undefined,
    "## THE SCENE",
    input.scene,
    "### DIRECTOR'S NOTES",
    `Style: ${input.style}`,
    `Pacing: ${input.pacing}`,
    `Breathing: ${input.breathing}`,
    `Articulation: ${input.articulation}`,
    "Accent: Match the natural language and pronunciation of the transcript. Do not translate.",
    "### SAMPLE CONTEXT",
    input.sampleContext,
    ...performanceMap,
    "### TRANSCRIPT",
    input.transcript,
  ]
    .filter(Boolean)
    .join("\n");
}

function buildFallbackPreparedPrompt(
  input: Omit<PreparePromptInput, "ai" | "model" | "fallbackModel" | "useModelPreprocessor">,
): PreparedPrompt {
  const firstPreset = primaryPreset(input.presets);
  const segments = buildFallbackSegments(input.sourceText, input.presets, input.combineMode);
  const preparedTranscript = materializeTranscript(segments);
  const audioProfile =
    input.presets.length === 1
      ? `${firstPreset.label} single-speaker narrator`
      : `Mixed expressive single-speaker narrator: ${input.presets
          .map((preset) => preset.label)
          .join(" + ")}`;
  const scene = combinePresetDescriptions(input.presets, "scene", input.combineMode);
  const style = `${combinePresetDescriptions(
    input.presets,
    "style",
    input.combineMode,
  )} Use the ${input.voice.descriptor.toLowerCase()} character of the ${input.voice.name} voice to support the expressive mix when it fits naturally.`;
  const pacing = combinePresetDescriptions(input.presets, "pacing", input.combineMode);
  const breathing = combinePresetDescriptions(input.presets, "breathing", input.combineMode);
  const articulation = combinePresetDescriptions(input.presets, "articulation", input.combineMode);
  const sampleContext = combinePresetDescriptions(
    input.presets,
    "sampleContext",
    input.combineMode,
  );

  return {
    preparedPrompt: buildPreparedPrompt({
      title: input.title,
      requestId: input.requestId,
      transcript: preparedTranscript,
      audioProfile,
      scene,
      style,
      pacing,
      breathing,
      articulation,
      sampleContext,
      segments,
    }),
    preparedTranscript,
    audioProfile,
    scene,
    style,
    pacing,
    breathing,
    articulation,
    sampleContext,
    audioTags: dedupeTags(segments.flatMap((segment) => segment.audioTags)),
    notes: ["Fallback prompt used because model preprocessing was skipped or failed."],
    mode: "fallback",
    warnings: [],
    presets: input.presets.map((preset) => ({
      id: preset.id,
      label: preset.label,
      description: preset.description,
    })),
    combineMode: input.combineMode,
    segments,
  };
}

function sanitizeModelSegments(
  rawSegments: z.infer<typeof SEGMENT_PLAN_SCHEMA>[] | undefined,
  presets: PresetDefinition[],
  transcriptFallback: string,
  combineMode: EffectiveCombineMode,
): PreparedPromptSegment[] {
  const presetById = new Map(presets.map((preset) => [preset.id, preset]));
  const firstPreset = primaryPreset(presets);
  const fallbackSegments = buildFallbackSegments(transcriptFallback, presets, combineMode);

  const segmentsSource =
    rawSegments?.length && rawSegments.some((segment) => normalizeText(segment.text).length > 0)
      ? rawSegments
      : null;

  if (!segmentsSource) {
    return fallbackSegments;
  }

  const sanitizedSegments = segmentsSource.map((segment, index) => {
    const resolvedPreset =
      presetById.get(segment.presetId as PresetId) ?? firstPreset;

    return {
      index,
      presetId: resolvedPreset.id,
      presetLabel: resolvedPreset.label,
      placement:
        segment.placement ?? toPlacement(index, segmentsSource.length),
      text: normalizeText(segment.text),
      audioTags: dedupeTags(segment.audioTags ?? []),
      directorNote: segment.directorNote ?? defaultSegmentDirectorNote(resolvedPreset),
    };
  });

  if (!hasSufficientPresetCoverage(sanitizedSegments, presets, combineMode)) {
    return fallbackSegments;
  }

  return sanitizedSegments;
}

async function runModelPreprocessor(
  input: PreparePromptInput,
  model: string,
): Promise<PreparedPrompt> {
  const firstPreset = primaryPreset(input.presets);
  const preprocessingPrompt = [
    "You prepare expressive single-speaker text for Gemini TTS.",
    "Return only one JSON object with keys: audioProfile, scene, style, pacing, breathing, articulation, sampleContext, transcript, audioTags, notes, segmentPlan.",
    "Rules:",
    "- Keep the same spoken language as the source text. Never translate.",
    "- Preserve meaning. Rewrite only to improve spoken delivery.",
    "- Use English audio tags in square brackets when useful, because Gemini TTS recommends English tags even for non-English transcripts.",
    "- Use tags sparingly. Usually 0 to 3 tags are enough globally, unless a mixed preset flow truly needs more.",
    "- Transcript must contain only the words that should be spoken plus inline audio tags.",
    "- Do not include section headings or markdown in transcript.",
    "- segmentPlan is optional only for a single preset.",
    "- When more than one preset is active, segmentPlan is required.",
    "- When segmentPlan is present, each item must contain presetId, text, optional audioTags, optional directorNote, optional placement.",
    "- segmentPlan must preserve spoken order and cover the full delivery without inventing new meaning.",
    "- Each segment presetId must be one of the active preset ids listed below.",
    "- When more than one preset is active, segmentPlan must audibly distribute at least two active preset ids whenever the text is long enough for multiple segments.",
    "- Make the expressive mix audible through pacing, breathing and emotional color, not only through one inserted tag.",
    "",
    `Combine mode: ${input.combineMode}`,
    `Active preset ids: ${input.presets.map((preset) => preset.id).join(", ")}`,
    ...input.presets.flatMap((preset, index) => [
      `Preset ${index + 1}: ${preset.id} / ${preset.label}`,
      `Preset description: ${preset.description}`,
      `Preferred style: ${preset.style}`,
      `Preferred pacing: ${preset.pacing}`,
      `Preferred breathing: ${preset.breathing}`,
      `Preferred articulation: ${preset.articulation}`,
      `Preferred scene: ${preset.scene}`,
      `Sample context: ${preset.sampleContext}`,
      "",
    ]),
    `Voice: ${input.voice.name} (${input.voice.descriptor})`,
    input.title ? `Title: ${input.title}` : undefined,
    input.requestId ? `Request ID: ${input.requestId}` : undefined,
    "",
    "Source text:",
    normalizeText(input.sourceText),
  ]
    .filter(Boolean)
    .join("\n");

  const response = await input.ai.models.generateContent({
    model,
    contents: preprocessingPrompt,
    config: {
      responseMimeType: "application/json",
      temperature: 0.4,
    },
  });

  const parsedPayload = MODEL_RESPONSE_SCHEMA.parse(
    JSON.parse(cleanModelJson(toResponseText(response))),
  );

  const segments = sanitizeModelSegments(
    parsedPayload.segmentPlan,
    input.presets,
    normalizeText(parsedPayload.transcript ?? input.sourceText),
    input.combineMode,
  );
  const preparedTranscript = materializeTranscript(segments);
  const audioProfile =
    parsedPayload.audioProfile ??
    (input.presets.length === 1
      ? `${firstPreset.label} single-speaker narrator`
      : `Mixed expressive single-speaker narrator: ${input.presets
          .map((preset) => preset.label)
          .join(" + ")}`);
  const scene =
    parsedPayload.scene ?? combinePresetDescriptions(input.presets, "scene", input.combineMode);
  const style =
    parsedPayload.style ?? combinePresetDescriptions(input.presets, "style", input.combineMode);
  const pacing =
    parsedPayload.pacing ??
    combinePresetDescriptions(input.presets, "pacing", input.combineMode);
  const breathing =
    parsedPayload.breathing ??
    combinePresetDescriptions(input.presets, "breathing", input.combineMode);
  const articulation =
    parsedPayload.articulation ??
    combinePresetDescriptions(input.presets, "articulation", input.combineMode);
  const sampleContext =
    parsedPayload.sampleContext ??
    combinePresetDescriptions(input.presets, "sampleContext", input.combineMode);

  return {
    preparedPrompt: buildPreparedPrompt({
      title: input.title,
      requestId: input.requestId,
      transcript: preparedTranscript,
      audioProfile,
      scene,
      style,
      pacing,
      breathing,
      articulation,
      sampleContext,
      segments,
    }),
    preparedTranscript,
    audioProfile,
    scene,
    style,
    pacing,
    breathing,
    articulation,
    sampleContext,
    audioTags:
      parsedPayload.audioTags?.length
        ? dedupeTags(parsedPayload.audioTags)
        : dedupeTags(segments.flatMap((segment) => segment.audioTags)),
    notes: parsedPayload.notes ?? [],
    mode: "model",
    preprocessorModel: model,
    warnings: [],
    presets: input.presets.map((preset) => ({
      id: preset.id,
      label: preset.label,
      description: preset.description,
    })),
    combineMode: input.combineMode,
    segments,
  };
}

export async function preparePrompt(input: PreparePromptInput): Promise<PreparedPrompt> {
  const fallbackPreparedPrompt = buildFallbackPreparedPrompt(input);

  if (!input.useModelPreprocessor) {
    return fallbackPreparedPrompt;
  }

  const modelsToTry = Array.from(
    new Set([input.model, input.fallbackModel].filter((value): value is string => Boolean(value))),
  );
  const errors: string[] = [];

  for (const model of modelsToTry) {
    try {
      return await runModelPreprocessor(input, model);
    } catch (error) {
      errors.push(
        `${model}: ${error instanceof Error ? error.message : "unknown error"}`,
      );
    }
  }

  return {
    ...fallbackPreparedPrompt,
    warnings: [`Prompt preprocessor fallback activated: ${errors.join(" | ")}`],
  };
}

export function buildPromptChunks(
  preparedPrompt: PreparedPrompt,
  options: {
    maxCharacters?: number;
    maxSegments?: number;
  } = {},
): PreparedPromptChunk[] {
  const maxCharacters = options.maxCharacters ?? 900;
  const maxSegments = options.maxSegments ?? 6;

  if (
    preparedPrompt.segments.length <= 1 &&
    preparedPrompt.preparedTranscript.length <= maxCharacters
  ) {
    return [
      {
        prompt: preparedPrompt.preparedPrompt,
        transcript: preparedPrompt.preparedTranscript,
        segments: preparedPrompt.segments,
      },
    ];
  }

  const normalizedSegments = preparedPrompt.segments.flatMap((segment) =>
    materializeSegmentText(segment).length > maxCharacters
      ? splitOversizedSegment(segment, maxCharacters)
      : [segment],
  );

  const groups: PreparedPromptSegment[][] = [];
  let currentGroup: PreparedPromptSegment[] = [];
  let currentLength = 0;

  for (const segment of normalizedSegments) {
    const segmentLength = materializeSegmentText(segment).length;
    const projectedLength = currentLength + segmentLength + (currentGroup.length === 0 ? 0 : 1);
    const exceedsBudget =
      currentGroup.length > 0 &&
      (projectedLength > maxCharacters || currentGroup.length >= maxSegments);

    if (exceedsBudget) {
      groups.push(currentGroup);
      currentGroup = [];
      currentLength = 0;
    }

    currentGroup.push(segment);
    currentLength += segmentLength + (currentGroup.length > 1 ? 1 : 0);
  }

  if (currentGroup.length > 0) {
    groups.push(currentGroup);
  }

  return groups.map((group) => {
    const normalizedGroup = group.map((segment, index) => ({
      ...segment,
      index,
      placement: toPlacement(index, group.length),
    }));
    let transcript = materializeTranscript(normalizedGroup);
    if (!transcript) {
      transcript = preparedPrompt.preparedTranscript;
    }

    return {
      prompt: buildPreparedPrompt({
        title: undefined,
        requestId: undefined,
        transcript,
        audioProfile: preparedPrompt.audioProfile,
        scene: preparedPrompt.scene,
        style: preparedPrompt.style,
        pacing: preparedPrompt.pacing,
        breathing: preparedPrompt.breathing,
        articulation: preparedPrompt.articulation,
        sampleContext: preparedPrompt.sampleContext,
        segments: normalizedGroup,
      }),
      transcript,
      segments: normalizedGroup,
    };
  });
}
