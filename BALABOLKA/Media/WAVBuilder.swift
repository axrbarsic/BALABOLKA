import Foundation

enum WAVBuilder {
    static func makeMonoSineWave(
        duration: TimeInterval,
        sampleRate: Int = 24_000,
        frequency: Double = 440,
        amplitude: Float = 0.65
    ) -> Data {
        let clampedDuration = max(duration, 0.1)
        let sampleCount = max(Int(Double(sampleRate) * clampedDuration), 1)
        var pcm = Data(capacity: sampleCount * MemoryLayout<Int16>.size)

        for sampleIndex in 0..<sampleCount {
            let t = Double(sampleIndex) / Double(sampleRate)
            let wave = sin(2 * Double.pi * frequency * t)
            let scaled = max(-1, min(1, Float(wave) * amplitude))
            var pcmSample = Int16(scaled * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &pcmSample) { bytes in
                pcm.append(contentsOf: bytes)
            }
        }

        return wrapMonoPCM16(pcm, sampleRate: sampleRate)
    }

    static func wrapMonoPCM16(_ pcm: Data, sampleRate: Int) -> Data {
        let bitsPerSample = 16
        let channelCount = 1
        let byteRate = sampleRate * channelCount * (bitsPerSample / 8)
        let blockAlign = channelCount * (bitsPerSample / 8)

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(uint32LE(UInt32(36 + pcm.count)))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(uint32LE(16))
        data.append(uint16LE(1))
        data.append(uint16LE(UInt16(channelCount)))
        data.append(uint32LE(UInt32(sampleRate)))
        data.append(uint32LE(UInt32(byteRate)))
        data.append(uint16LE(UInt16(blockAlign)))
        data.append(uint16LE(UInt16(bitsPerSample)))
        data.append("data".data(using: .ascii)!)
        data.append(uint32LE(UInt32(pcm.count)))
        data.append(pcm)
        return data
    }

    static func wrapMonoFloatPCM16(_ samples: [Float], sampleRate: Int) -> Data {
        var pcm = Data(capacity: samples.count * MemoryLayout<Int16>.size)

        for sample in samples {
            let clamped = max(-1, min(1, sample))
            var pcmSample = Int16(clamped * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &pcmSample) { bytes in
                pcm.append(contentsOf: bytes)
            }
        }

        return wrapMonoPCM16(pcm, sampleRate: sampleRate)
    }

    private static func uint16LE(_ value: UInt16) -> Data {
        var littleEndian = value.littleEndian
        return withUnsafeBytes(of: &littleEndian) { Data($0) }
    }

    private static func uint32LE(_ value: UInt32) -> Data {
        var littleEndian = value.littleEndian
        return withUnsafeBytes(of: &littleEndian) { Data($0) }
    }
}
