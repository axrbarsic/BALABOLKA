import Foundation

struct BALDecodedAudioPCM: Sendable {
    let sourceURL: URL
    let sampleRate: Double
    let channelCount: Int
    let samples: [Float]

    var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / sampleRate
    }
}

enum BALAudioPCMReaderError: LocalizedError {
    case invalidWAVHeader
    case missingFormatChunk
    case missingDataChunk
    case malformedChunk
    case unsupportedAudioFormat(UInt16)
    case unsupportedBitDepth(UInt16)

    var errorDescription: String? {
        switch self {
        case .invalidWAVHeader:
            return "The WAV header is invalid."
        case .missingFormatChunk:
            return "The WAV file is missing the fmt chunk."
        case .missingDataChunk:
            return "The WAV file is missing the data chunk."
        case .malformedChunk:
            return "The WAV file contains a malformed chunk."
        case let .unsupportedAudioFormat(format):
            return "Unsupported WAV format \(format)."
        case let .unsupportedBitDepth(depth):
            return "Unsupported WAV bit depth \(depth)."
        }
    }
}

struct BALAudioPCMReader {
    func readMonoPCM(from url: URL) throws -> BALDecodedAudioPCM {
        let data = try Data(contentsOf: url)
        let parser = try BALWAVParser(data: data)
        let samples = try parser.decodeMonoSamples()

        return BALDecodedAudioPCM(
            sourceURL: url,
            sampleRate: Double(parser.sampleRate),
            channelCount: Int(parser.channelCount),
            samples: samples
        )
    }
}

private struct BALWAVParser {
    private let data: Data
    private let audioFormat: UInt16
    let channelCount: UInt16
    let sampleRate: UInt32
    private let bitsPerSample: UInt16
    private let blockAlign: UInt16
    private let dataRange: Range<Int>

    init(data: Data) throws {
        self.data = data

        guard data.count >= 44 else {
            throw BALAudioPCMReaderError.invalidWAVHeader
        }

        guard Self.string(at: 0, in: data) == "RIFF", Self.string(at: 8, in: data) == "WAVE" else {
            throw BALAudioPCMReaderError.invalidWAVHeader
        }

        var formatChunk: Range<Int>?
        var dataChunk: Range<Int>?
        var offset = 12

        while offset + 8 <= data.count {
            let chunkID = Self.string(at: offset, in: data)
            let chunkSize = Int(Self.uint32LE(at: offset + 4, in: data))
            let chunkStart = offset + 8
            let chunkEnd = chunkStart + chunkSize

            guard chunkEnd <= data.count else {
                throw BALAudioPCMReaderError.malformedChunk
            }

            switch chunkID {
            case "fmt ":
                formatChunk = chunkStart..<chunkEnd
            case "data":
                dataChunk = chunkStart..<chunkEnd
            default:
                break
            }

            offset = chunkEnd + (chunkSize % 2)
        }

        guard let formatChunk else {
            throw BALAudioPCMReaderError.missingFormatChunk
        }
        guard let dataChunk else {
            throw BALAudioPCMReaderError.missingDataChunk
        }
        guard formatChunk.count >= 16 else {
            throw BALAudioPCMReaderError.malformedChunk
        }

        let rawFormat = Self.uint16LE(at: formatChunk.lowerBound, in: data)
        let resolvedFormat: UInt16
        if rawFormat == 0xFFFE, formatChunk.count >= 40 {
            resolvedFormat = Self.uint16LE(at: formatChunk.lowerBound + 24, in: data)
        } else {
            resolvedFormat = rawFormat
        }

        self.audioFormat = resolvedFormat
        self.channelCount = Self.uint16LE(at: formatChunk.lowerBound + 2, in: data)
        self.sampleRate = Self.uint32LE(at: formatChunk.lowerBound + 4, in: data)
        self.blockAlign = Self.uint16LE(at: formatChunk.lowerBound + 12, in: data)
        self.bitsPerSample = Self.uint16LE(at: formatChunk.lowerBound + 14, in: data)
        self.dataRange = dataChunk
    }

    func decodeMonoSamples() throws -> [Float] {
        let channels = Int(channelCount)
        guard channels > 0, sampleRate > 0, blockAlign > 0 else {
            throw BALAudioPCMReaderError.malformedChunk
        }

        let bytesPerFrame = Int(blockAlign)
        let frameCount = dataRange.count / bytesPerFrame
        var mono: [Float] = []
        mono.reserveCapacity(frameCount)

        for frameIndex in 0..<frameCount {
            let frameOffset = dataRange.lowerBound + (frameIndex * bytesPerFrame)
            var mixed: Float = 0

            for channelIndex in 0..<channels {
                let sampleOffset = frameOffset + channelOffset(for: channelIndex)
                mixed += try sampleValue(at: sampleOffset)
            }

            mono.append(max(-1, min(1, mixed / Float(channels))))
        }

        return mono
    }

    private func channelOffset(for channelIndex: Int) -> Int {
        let bytesPerSample = Int(bitsPerSample / 8)
        return channelIndex * bytesPerSample
    }

    private func sampleValue(at offset: Int) throws -> Float {
        switch audioFormat {
        case 1:
            return try integerSampleValue(at: offset)
        case 3:
            return try floatSampleValue(at: offset)
        default:
            throw BALAudioPCMReaderError.unsupportedAudioFormat(audioFormat)
        }
    }

    private func integerSampleValue(at offset: Int) throws -> Float {
        switch bitsPerSample {
        case 8:
            let value = Float(data[offset])
            return (value - 128) / 128
        case 16:
            return Float(Int16(bitPattern: Self.uint16LE(at: offset, in: data))) / Float(Int16.max)
        case 24:
            let b0 = Int32(data[offset])
            let b1 = Int32(data[offset + 1]) << 8
            let b2 = Int32(data[offset + 2]) << 16
            var value = b0 | b1 | b2
            if (value & 0x0080_0000) != 0 {
                value |= ~0x00FF_FFFF
            }
            return Float(value) / 8_388_608
        case 32:
            let value = Int32(bitPattern: Self.uint32LE(at: offset, in: data))
            return Float(value) / 2_147_483_648
        default:
            throw BALAudioPCMReaderError.unsupportedBitDepth(bitsPerSample)
        }
    }

    private func floatSampleValue(at offset: Int) throws -> Float {
        switch bitsPerSample {
        case 32:
            return Float(bitPattern: Self.uint32LE(at: offset, in: data))
        case 64:
            let bitPattern = Self.uint64LE(at: offset, in: data)
            return Float(Double(bitPattern: bitPattern))
        default:
            throw BALAudioPCMReaderError.unsupportedBitDepth(bitsPerSample)
        }
    }

    private static func string(at offset: Int, in data: Data) -> String {
        let range = offset..<(offset + 4)
        let bytes = data[range]
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func uint16LE(at offset: Int, in data: Data) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func uint32LE(at offset: Int, in data: Data) -> UInt32 {
        UInt32(data[offset]) |
        (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) |
        (UInt32(data[offset + 3]) << 24)
    }

    private static func uint64LE(at offset: Int, in data: Data) -> UInt64 {
        UInt64(data[offset]) |
        (UInt64(data[offset + 1]) << 8) |
        (UInt64(data[offset + 2]) << 16) |
        (UInt64(data[offset + 3]) << 24) |
        (UInt64(data[offset + 4]) << 32) |
        (UInt64(data[offset + 5]) << 40) |
        (UInt64(data[offset + 6]) << 48) |
        (UInt64(data[offset + 7]) << 56)
    }
}
