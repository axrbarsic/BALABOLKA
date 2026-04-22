export const VOICES = [
  { name: "Zephyr", descriptor: "Bright" },
  { name: "Puck", descriptor: "Upbeat" },
  { name: "Charon", descriptor: "Informative" },
  { name: "Kore", descriptor: "Firm" },
  { name: "Fenrir", descriptor: "Excitable" },
  { name: "Leda", descriptor: "Youthful" },
  { name: "Orus", descriptor: "Firm" },
  { name: "Aoede", descriptor: "Breezy" },
  { name: "Callirrhoe", descriptor: "Easy-going" },
  { name: "Autonoe", descriptor: "Bright" },
  { name: "Enceladus", descriptor: "Breathy" },
  { name: "Iapetus", descriptor: "Clear" },
  { name: "Umbriel", descriptor: "Easy-going" },
  { name: "Algieba", descriptor: "Smooth" },
  { name: "Despina", descriptor: "Smooth" },
  { name: "Erinome", descriptor: "Clear" },
  { name: "Algenib", descriptor: "Gravelly" },
  { name: "Rasalgethi", descriptor: "Informative" },
  { name: "Laomedeia", descriptor: "Upbeat" },
  { name: "Achernar", descriptor: "Soft" },
  { name: "Alnilam", descriptor: "Firm" },
  { name: "Schedar", descriptor: "Even" },
  { name: "Gacrux", descriptor: "Mature" },
  { name: "Pulcherrima", descriptor: "Forward" },
  { name: "Achird", descriptor: "Friendly" },
  { name: "Zubenelgenubi", descriptor: "Casual" },
  { name: "Vindemiatrix", descriptor: "Gentle" },
  { name: "Sadachbia", descriptor: "Lively" },
  { name: "Sadaltager", descriptor: "Knowledgeable" },
  { name: "Sulafat", descriptor: "Warm" },
] as const;

export type VoiceName = (typeof VOICES)[number]["name"];
export type RequestedCombineMode = "auto" | "blend" | "sequence";
export type EffectiveCombineMode = RequestedCombineMode | "single";

export type PresetId =
  | "neutral"
  | "quiet"
  | "whisper"
  | "laugh"
  | "cry"
  | "cough"
  | "hoarse"
  | "sarcasm"
  | "anger"
  | "tired"
  | "heavy_breathing";

export type PresetDefinition = {
  id: PresetId;
  label: string;
  description: string;
  defaultVoice: VoiceName;
  style: string;
  pacing: string;
  breathing: string;
  articulation: string;
  scene: string;
  sampleContext: string;
  fallbackOpeningTag?: string;
  fallbackMidTag?: string;
};

export const PRESETS: Record<PresetId, PresetDefinition> = {
  neutral: {
    id: "neutral",
    label: "нейтрально",
    description: "Чистая, естественная дикторская подача без сильной экспрессии.",
    defaultVoice: "Kore",
    style: "Natural, clean and controlled narration without theatrical exaggeration.",
    pacing: "Measured conversational pace with stable rhythm and clear sentence endings.",
    breathing: "Keep breaths subtle and unobtrusive.",
    articulation: "Prioritize clarity and stable diction.",
    scene: "A dry, minimal vocal booth for a clean single-speaker take.",
    sampleContext: "A concise voiceover for a mobile-generated short video.",
  },
  quiet: {
    id: "quiet",
    label: "тихо",
    description: "Тихая, близкая, но не буквальный шёпот.",
    defaultVoice: "Vindemiatrix",
    style: "Soft close-mic delivery with restrained dynamics and intimate presence.",
    pacing: "Slightly slower than normal, with gentle sentence landings.",
    breathing: "Breaths stay soft and close, never dramatic.",
    articulation: "Remain intelligible despite low projection.",
    scene: "Late-night close-mic booth with a calm, private tone.",
    sampleContext: "A minimalist social clip that should feel private and personal.",
  },
  whisper: {
    id: "whisper",
    label: "шёпот",
    description: "Осмысленный разборчивый шёпот, а не просто тихий голос.",
    defaultVoice: "Enceladus",
    style: "Audible whisper delivery with intimate texture and fragile air.",
    pacing: "Slow enough to remain intelligible, avoiding rushed consonants.",
    breathing: "Air is audible and close, but the line stays controlled.",
    articulation: "Keep consonants precise so the whisper remains understandable.",
    scene: "A very close microphone in a silent room.",
    sampleContext: "A whispery single-speaker narration for a stark square video.",
    fallbackOpeningTag: "[whispers]",
  },
  laugh: {
    id: "laugh",
    label: "смех",
    description: "Речь на улыбке со встроенными короткими смешками.",
    defaultVoice: "Puck",
    style: "Smiling, amused delivery with brief natural laughs where they fit.",
    pacing: "Lively and elastic, but never chaotic.",
    breathing: "Breaths can brighten the line after laughs, but should stay clean.",
    articulation: "Keep the words readable; the joke should not swallow the text.",
    scene: "A playful recording take where the speaker is genuinely amused.",
    sampleContext: "An expressive short-form voiceover with light comedic energy.",
    fallbackOpeningTag: "[laughs]",
    fallbackMidTag: "[giggles]",
  },
  cry: {
    id: "cry",
    label: "плач",
    description: "Эмоционально дрожащая речь, не скатывающаяся в неразборчивость.",
    defaultVoice: "Achernar",
    style: "Emotionally strained delivery with trembling control and sadness in the tone.",
    pacing: "Uneven and fragile, with brief hesitations where emotion catches.",
    breathing: "Breaths may shake; crying texture is allowed but should not overwhelm speech.",
    articulation: "Stay understandable even when the voice trembles.",
    scene: "A close, emotionally charged take in an otherwise quiet room.",
    sampleContext: "A dramatic but readable single-speaker narration.",
    fallbackOpeningTag: "[crying]",
    fallbackMidTag: "[trembling]",
  },
  cough: {
    id: "cough",
    label: "кашель",
    description: "Голос с естественными покашливаниями, но без карикатуры.",
    defaultVoice: "Algenib",
    style: "Dry, interrupted delivery with occasional coughs integrated naturally.",
    pacing: "Uneven by design, with brief resets after cough interruptions.",
    breathing: "Breaths can feel slightly irritated or dry.",
    articulation: "Return to intelligible speech immediately after interruptions.",
    scene: "A dry booth take where the speaker is fighting through throat irritation.",
    sampleContext: "An intentionally textured narration where brief coughs are part of the performance.",
    fallbackOpeningTag: "[cough]",
    fallbackMidTag: "[cough]",
  },
  hoarse: {
    id: "hoarse",
    label: "хрипота",
    description: "Сухой, сорванный, немного надтреснутый голос.",
    defaultVoice: "Algenib",
    style: "Raspy hoarse texture with vocal strain, but not a full cough performance.",
    pacing: "Measured pace that respects the strain in the voice.",
    breathing: "Dry, low-energy breathing that supports the rough tone.",
    articulation: "Consonants remain readable even through the rasp.",
    scene: "A tired booth take after the speaker has overused their voice.",
    sampleContext: "A gritty single-speaker read for a stripped-down visual.",
    fallbackOpeningTag: "[serious]",
  },
  sarcasm: {
    id: "sarcasm",
    label: "сарказм",
    description: "Сухая ироничная подача с точечным презрительным акцентом.",
    defaultVoice: "Charon",
    style: "Dry ironic delivery with a clear undercurrent of disbelief.",
    pacing: "Controlled and slightly deliberate, allowing room for eye-roll energy.",
    breathing: "Breaths stay understated and unimpressed.",
    articulation: "Punch key words with crisp emphasis instead of raising volume.",
    scene: "A deadpan studio take recorded by someone who is not buying it.",
    sampleContext: "A minimalist narration driven by irony instead of loud emotion.",
    fallbackOpeningTag: "[sarcastic]",
  },
  anger: {
    id: "anger",
    label: "злость",
    description: "Собранная злость и жёсткая энергия без постоянного крика.",
    defaultVoice: "Fenrir",
    style: "Controlled anger with clipped emphasis and heat under the surface.",
    pacing: "Tight, forward-driving rhythm with sharper attack on stressed words.",
    breathing: "Breaths can be tense, but the delivery should stay intentional.",
    articulation: "Stay precise; anger should feel focused rather than sloppy.",
    scene: "A tense single-speaker take in a booth with no room for softness.",
    sampleContext: "A forceful short-form narration that sounds genuinely irritated.",
    fallbackOpeningTag: "[serious]",
    fallbackMidTag: "[shouting]",
  },
  tired: {
    id: "tired",
    label: "усталость",
    description: "Усталый, выжатый голос без полного распада дикции.",
    defaultVoice: "Schedar",
    style: "Fatigued delivery with low energy and soft emotional drag.",
    pacing: "Slightly slow and heavy, with occasional trailing phrase endings.",
    breathing: "Breaths can feel drained and a bit heavier than normal.",
    articulation: "Words soften, but remain understandable.",
    scene: "An exhausted late-night booth take after a very long day.",
    sampleContext: "A restrained short-form narration with visible fatigue.",
    fallbackOpeningTag: "[tired]",
    fallbackMidTag: "[sighs]",
  },
  heavy_breathing: {
    id: "heavy_breathing",
    label: "тяжёлое дыхание",
    description: "Речь после нагрузки, где дыхание реально присутствует между фразами.",
    defaultVoice: "Enceladus",
    style: "Breath-led delivery that sounds physically taxed without becoming muddy.",
    pacing: "Broken into shorter phrases to make space for recovery breaths.",
    breathing: "Heavy audible breathing is a core part of the performance.",
    articulation: "Protect intelligibility between breaths; avoid slurring the full line.",
    scene: "A close microphone captures someone speaking right after exertion.",
    sampleContext: "A stark, intimate voiceover where breath is part of the texture.",
    fallbackOpeningTag: "[gasp]",
    fallbackMidTag: "[gasp]",
  },
};

const PRESET_ALIASES: Record<string, PresetId> = {
  neutral: "neutral",
  "нейтрально": "neutral",
  quiet: "quiet",
  "тихо": "quiet",
  whisper: "whisper",
  "шёпот": "whisper",
  "шепот": "whisper",
  laugh: "laugh",
  "смех": "laugh",
  cry: "cry",
  "плач": "cry",
  cough: "cough",
  "кашель": "cough",
  hoarse: "hoarse",
  "хрипота": "hoarse",
  sarcasm: "sarcasm",
  "сарказм": "sarcasm",
  anger: "anger",
  "злость": "anger",
  tired: "tired",
  "усталость": "tired",
  heavy_breathing: "heavy_breathing",
  "heavy-breathing": "heavy_breathing",
  "тяжёлое дыхание": "heavy_breathing",
  "тяжелое дыхание": "heavy_breathing",
};

const VOICES_BY_NAME = new Map(VOICES.map((voice) => [voice.name.toLowerCase(), voice]));

function normalizePresetAlias(input: string): PresetId {
  const presetId = PRESET_ALIASES[input.trim().toLowerCase()];

  if (!presetId) {
    throw new Error(`Unsupported preset "${input}".`);
  }

  return presetId;
}

export function resolvePreset(input?: string): PresetDefinition {
  if (!input) {
    return PRESETS.neutral;
  }

  return PRESETS[normalizePresetAlias(input)];
}

export function resolvePresetCollection(input: {
  preset?: string | undefined;
  presetIds?: string[] | undefined;
}) {
  const requestedValues = [
    ...(input.preset ? [input.preset] : []),
    ...(input.presetIds ?? []),
  ];

  if (requestedValues.length === 0) {
    return {
      presets: [PRESETS.neutral],
      combineMode: "single" as EffectiveCombineMode,
    };
  }

  const orderedPresetIds = Array.from(
    new Set(requestedValues.map((value) => normalizePresetAlias(value))),
  );

  return {
    presets: orderedPresetIds.map((presetId) => PRESETS[presetId]),
    combineMode:
      orderedPresetIds.length > 1 ? ("auto" as EffectiveCombineMode) : ("single" as EffectiveCombineMode),
  };
}

export function resolveCombineMode(
  input: RequestedCombineMode | undefined,
  presetCount: number,
): EffectiveCombineMode {
  if (presetCount <= 1) {
    return "single";
  }

  return input ?? "auto";
}

export function resolveVoice(input: string | undefined, preset: PresetDefinition) {
  const requestedVoiceName = input?.trim();

  if (!requestedVoiceName) {
    return VOICES_BY_NAME.get(preset.defaultVoice.toLowerCase())!;
  }

  const resolvedVoice = VOICES_BY_NAME.get(requestedVoiceName.toLowerCase());

  if (!resolvedVoice) {
    throw new Error(`Unsupported voice "${input}".`);
  }

  return resolvedVoice;
}
