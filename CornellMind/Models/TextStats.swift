import Foundation

/// Живая статистика текста лекции.
struct TextStats {
    let characters: Int
    let words: Int
    let sentences: Int
    let wordsPerSentence: Double
    let duration: TimeInterval

    init(text: String, duration: TimeInterval) {
        characters = text.count
        words = text.split(whereSeparator: \.isWhitespace).count

        var sentenceCount = 0
        var inSentence = false
        for char in text {
            if char.isLetter || char.isNumber {
                inSentence = true
            } else if Self.isSentenceEnd(char) && inSentence {
                sentenceCount += 1
                inSentence = false
            }
        }
        if inSentence { sentenceCount += 1 }
        sentences = sentenceCount
        wordsPerSentence = sentences > 0 ? Double(words) / Double(sentences) : 0
        self.duration = duration
    }

    private static func isSentenceEnd(_ char: Character) -> Bool {
        [".", "!", "?", "…", ";"].contains(String(char))
    }

    func summaryLine() -> String {
        "Символов: \(characters) · Слов: \(words) · Предложений: \(sentences)"
    }
}