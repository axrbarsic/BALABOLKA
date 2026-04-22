const DEFAULT_SAMPLE_RATE_HZ = 24000;
const DEFAULT_CHANNELS = 1;
const DEFAULT_BITS_PER_SAMPLE = 16;

export type PcmFormat = {
  sampleRateHz: number;
  channels: number;
  bitsPerSample: number;
};

export function parsePcmFormatFromMimeType(mimeType?: string): PcmFormat {
  const loweredMimeType = mimeType?.toLowerCase() ?? "";
  const rateValue = loweredMimeType.match(/rate=(\d+)/)?.[1];
  const channelValue = loweredMimeType.match(/channels=(\d+)/)?.[1];
  const bitDepthValue = loweredMimeType.match(/l(\d+)/)?.[1];

  return {
    sampleRateHz: rateValue ? Number.parseInt(rateValue, 10) : DEFAULT_SAMPLE_RATE_HZ,
    channels: channelValue ? Number.parseInt(channelValue, 10) : DEFAULT_CHANNELS,
    bitsPerSample: bitDepthValue
      ? Number.parseInt(bitDepthValue, 10)
      : DEFAULT_BITS_PER_SAMPLE,
  };
}

export function isWavBuffer(buffer: Buffer): boolean {
  if (buffer.length < 12) {
    return false;
  }

  return (
    buffer.subarray(0, 4).toString("ascii") === "RIFF" &&
    buffer.subarray(8, 12).toString("ascii") === "WAVE"
  );
}

export function buildWavFromPcm(pcmBuffer: Buffer, format: PcmFormat): Buffer {
  const headerBuffer = Buffer.alloc(44);
  const byteRate = (format.sampleRateHz * format.channels * format.bitsPerSample) / 8;
  const blockAlign = (format.channels * format.bitsPerSample) / 8;

  headerBuffer.write("RIFF", 0, "ascii");
  headerBuffer.writeUInt32LE(36 + pcmBuffer.length, 4);
  headerBuffer.write("WAVE", 8, "ascii");
  headerBuffer.write("fmt ", 12, "ascii");
  headerBuffer.writeUInt32LE(16, 16);
  headerBuffer.writeUInt16LE(1, 20);
  headerBuffer.writeUInt16LE(format.channels, 22);
  headerBuffer.writeUInt32LE(format.sampleRateHz, 24);
  headerBuffer.writeUInt32LE(byteRate, 28);
  headerBuffer.writeUInt16LE(blockAlign, 32);
  headerBuffer.writeUInt16LE(format.bitsPerSample, 34);
  headerBuffer.write("data", 36, "ascii");
  headerBuffer.writeUInt32LE(pcmBuffer.length, 40);

  return Buffer.concat([headerBuffer, pcmBuffer]);
}

export function ensureWavBuffer(audioBuffer: Buffer, mimeType?: string) {
  if (isWavBuffer(audioBuffer)) {
    return {
      wavBuffer: audioBuffer,
      format: parsePcmFormatFromMimeType(mimeType),
      rawMimeType: mimeType ?? "audio/wav",
      convertedFromPcm: false,
    };
  }

  const format = parsePcmFormatFromMimeType(mimeType);

  return {
    wavBuffer: buildWavFromPcm(audioBuffer, format),
    format,
    rawMimeType: mimeType ?? `audio/L${format.bitsPerSample};rate=${format.sampleRateHz}`,
    convertedFromPcm: true,
  };
}

export function estimateDurationMs(byteLength: number, format: PcmFormat): number {
  const bytesPerSecond =
    (format.sampleRateHz * format.channels * format.bitsPerSample) / 8;

  if (!bytesPerSecond) {
    return 0;
  }

  return Math.round((byteLength / bytesPerSecond) * 1000);
}

export function extractPcmFromWavBuffer(wavBuffer: Buffer): Buffer {
  if (!isWavBuffer(wavBuffer)) {
    return wavBuffer;
  }

  let offset = 12;
  while (offset + 8 <= wavBuffer.length) {
    const chunkId = wavBuffer.subarray(offset, offset + 4).toString("ascii");
    const chunkSize = wavBuffer.readUInt32LE(offset + 4);
    const dataStart = offset + 8;
    const dataEnd = dataStart + chunkSize;

    if (chunkId === "data") {
      return wavBuffer.subarray(dataStart, Math.min(dataEnd, wavBuffer.length));
    }

    offset = dataEnd + (chunkSize % 2);
  }

  throw new Error("WAV buffer does not contain a data chunk.");
}

export function concatenateWavBuffers(wavBuffers: Buffer[], format: PcmFormat): Buffer {
  const pcmBuffers = wavBuffers.map((buffer) => extractPcmFromWavBuffer(buffer));
  return buildWavFromPcm(Buffer.concat(pcmBuffers), format);
}
