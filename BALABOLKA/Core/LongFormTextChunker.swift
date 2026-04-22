import Foundation

struct LongFormTextChunk: Equatable, Sendable {
    let index: Int
    let text: String
}

enum LongFormTextChunker {
    static func makeChunks(
        from sourceText: String,
        targetCharacters: Int = BalabolkaLimits.longFormChunkTargetCharacters,
        hardLimitCharacters: Int = BalabolkaLimits.proxyRequestMaxCharacters
    ) -> [LongFormTextChunk] {
        let normalizedSource = normalize(sourceText)
        guard !normalizedSource.isEmpty else { return [] }
        guard normalizedSource.count > hardLimitCharacters else {
            return [LongFormTextChunk(index: 0, text: normalizedSource)]
        }

        let paragraphUnits = splitIntoParagraphs(normalizedSource)
        let packedParagraphs = packUnits(paragraphUnits, preferredLimit: targetCharacters, hardLimit: hardLimitCharacters)

        return packedParagraphs.enumerated().map { index, text in
            LongFormTextChunk(index: index, text: text)
        }
    }

    private static func splitIntoParagraphs(_ text: String) -> [String] {
        let paragraphs = normalize(text)
            .components(separatedBy: "\n\n")
            .map(normalize)
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else { return [text] }
        return paragraphs
    }

    private static func splitIntoSentences(_ text: String) -> [String] {
        let sentences = normalize(text)
            .split(separator: "\n")
            .flatMap { line in
                line.split(separator: ".", omittingEmptySubsequences: false)
            }

        let rebuilt = sentences
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }

        if rebuilt.isEmpty {
            return normalize(text).split(whereSeparator: \.isNewline).map { normalize(String($0)) }.filter { !$0.isEmpty }
        }

        return rebuilt.map { sentence in
            let hasTerminalPunctuation = sentence.last.map { ".!?…".contains($0) } ?? false
            return hasTerminalPunctuation ? sentence : "\(sentence)."
        }
    }

    private static func splitOversizedUnit(_ text: String, hardLimit: Int) -> [String] {
        let normalizedText = normalize(text)
        guard normalizedText.count > hardLimit else { return [normalizedText] }

        let sentenceUnits = splitIntoSentences(normalizedText)
        if sentenceUnits.count > 1 {
            let packedSentences = packUnits(
                sentenceUnits,
                preferredLimit: max(hardLimit - 800, hardLimit / 2),
                hardLimit: hardLimit
            )
            if packedSentences.allSatisfy({ $0.count <= hardLimit }) {
                return packedSentences
            }
        }

        return splitByWords(normalizedText, hardLimit: hardLimit)
    }

    private static func splitByWords(_ text: String, hardLimit: Int) -> [String] {
        let words = normalize(text).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }

        var chunks: [String] = []
        var current = ""

        for word in words {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            if candidate.count <= hardLimit {
                current = candidate
                continue
            }

            if !current.isEmpty {
                chunks.append(current)
            }

            if word.count <= hardLimit {
                current = word
                continue
            }

            var start = word.startIndex
            while start < word.endIndex {
                let end = word.index(start, offsetBy: hardLimit, limitedBy: word.endIndex) ?? word.endIndex
                chunks.append(String(word[start..<end]))
                start = end
            }
            current = ""
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private static func packUnits(
        _ units: [String],
        preferredLimit: Int,
        hardLimit: Int
    ) -> [String] {
        var chunks: [String] = []
        var current = ""

        for rawUnit in units {
            let normalizedUnit = normalize(rawUnit)
            guard !normalizedUnit.isEmpty else { continue }

            if normalizedUnit.count > hardLimit {
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                }
                chunks.append(contentsOf: splitOversizedUnit(normalizedUnit, hardLimit: hardLimit))
                continue
            }

            let joiner = current.isEmpty ? "" : "\n\n"
            let candidate = current + joiner + normalizedUnit
            if candidate.count <= preferredLimit || current.isEmpty {
                if candidate.count <= hardLimit {
                    current = candidate
                    continue
                }
            }

            if !current.isEmpty {
                chunks.append(current)
                current = normalizedUnit
            } else {
                chunks.append(normalizedUnit)
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
