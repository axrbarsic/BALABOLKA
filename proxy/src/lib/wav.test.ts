import test from "node:test";
import assert from "node:assert/strict";

import {
  buildWavFromPcm,
  ensureWavBuffer,
  estimateDurationMs,
  isWavBuffer,
  parsePcmFormatFromMimeType,
} from "./wav.js";

test("parsePcmFormatFromMimeType reads sample rate and bit depth", () => {
  const parsed = parsePcmFormatFromMimeType("audio/L16;rate=24000;channels=1");

  assert.deepEqual(parsed, {
    sampleRateHz: 24000,
    channels: 1,
    bitsPerSample: 16,
  });
});

test("buildWavFromPcm wraps PCM into RIFF/WAVE container", () => {
  const pcmBuffer = Buffer.from([0, 0, 255, 127, 0, 128, 0, 0]);
  const wavBuffer = buildWavFromPcm(pcmBuffer, {
    sampleRateHz: 24000,
    channels: 1,
    bitsPerSample: 16,
  });

  assert.equal(isWavBuffer(wavBuffer), true);
  assert.equal(wavBuffer.subarray(0, 4).toString("ascii"), "RIFF");
  assert.equal(wavBuffer.subarray(8, 12).toString("ascii"), "WAVE");
  assert.equal(wavBuffer.readUInt32LE(24), 24000);
  assert.equal(wavBuffer.readUInt32LE(40), pcmBuffer.length);
});

test("ensureWavBuffer preserves existing wav payload", () => {
  const pcmBuffer = Buffer.from([0, 0, 255, 127]);
  const wavBuffer = buildWavFromPcm(pcmBuffer, {
    sampleRateHz: 24000,
    channels: 1,
    bitsPerSample: 16,
  });
  const ensured = ensureWavBuffer(wavBuffer, "audio/wav");

  assert.equal(ensured.convertedFromPcm, false);
  assert.equal(ensured.wavBuffer.equals(wavBuffer), true);
});

test("estimateDurationMs is derived from raw PCM payload size", () => {
  const durationMs = estimateDurationMs(48000, {
    sampleRateHz: 24000,
    channels: 1,
    bitsPerSample: 16,
  });

  assert.equal(durationMs, 1000);
});
