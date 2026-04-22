import test from "node:test";
import assert from "node:assert/strict";

import {
  resolveCombineMode,
  resolvePreset,
  resolvePresetCollection,
  resolveVoice,
} from "./presets.js";

test("resolvePreset supports russian aliases", () => {
  const whisperPreset = resolvePreset("шёпот");
  const tiredPreset = resolvePreset("усталость");

  assert.equal(whisperPreset.id, "whisper");
  assert.equal(tiredPreset.id, "tired");
});

test("resolveVoice falls back to preset default voice", () => {
  const preset = resolvePreset("сарказм");
  const resolvedVoice = resolveVoice(undefined, preset);

  assert.equal(resolvedVoice.name, "Charon");
});

test("resolveVoice supports case-insensitive lookup", () => {
  const preset = resolvePreset("кашель");
  const resolvedVoice = resolveVoice("enceladus", preset);

  assert.equal(resolvedVoice.name, "Enceladus");
});

test("resolvePresetCollection keeps backward compatibility for single preset", () => {
  const resolved = resolvePresetCollection({ preset: "шёпот" });

  assert.deepEqual(
    resolved.presets.map((preset) => preset.id),
    ["whisper"],
  );
  assert.equal(resolveCombineMode(undefined, resolved.presets.length), "single");
});

test("resolvePresetCollection merges preset and presetIds without duplicates", () => {
  const resolved = resolvePresetCollection({
    preset: "сарказм",
    presetIds: ["усталость", "sarcasm", "злость"],
  });

  assert.deepEqual(
    resolved.presets.map((preset) => preset.id),
    ["sarcasm", "tired", "anger"],
  );
  assert.equal(resolveCombineMode("blend", resolved.presets.length), "blend");
});
