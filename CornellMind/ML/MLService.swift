import Foundation
import CoreML

/// Обёртка над CoreML-моделями приложения.
/// Загружает Embedder/QGEncoder/QGDecoder из .mlmodelc в бандле.
enum MLError: Error, LocalizedError {
    case modelNotFound(String)
    case tokenizerNotFound(String)
    case tokenizationFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name): return "Не найдена модель \(name) в бандле"
        case .tokenizerNotFound(let name): return "Не найден токенизатор \(name)"
        case .tokenizationFailed: return "Не удалось токенизировать текст"
        }
    }
}

/// Результат тегирования: тег + вес уверенности.
struct TagScore {
    let tag: String
    let score: Double
}

/// Сервис, объединяющий тегирование (Embedder) и генерацию вопросов (T5 QG).
final class MLService: @unchecked Sendable {
    static let shared = MLService()

    private let embedModel: MLModel?
    private let qgEncoder: MLModel?
    private let qgDecoder: MLModel?

    private init() {
        embedModel = Self.load("Embedder")
        qgEncoder = Self.load("QGEncoder")
        qgDecoder = Self.load("QGDecoder")
    }

    private static func load(_ name: String) -> MLModel? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            return nil
        }
        let config = MLModelConfiguration()
        // Только CPU: модель 1 ГБ на Intel/Metal → MPSGraph падает в VM allocation.
        config.computeUnits = .cpuOnly
        return try? MLModel(contentsOf: url, configuration: config)
    }

    /// Все модели загрузились?
    var isReady: Bool {
        embedModel != nil && qgEncoder != nil && qgDecoder != nil
    }

    // MARK: - Embedder (тегирование)

    private static let embedMaxLength = 128
    private static let embedDim = 768

    /// Возвращает mean-pooled эмбеддинг текста (768).
    /// Возвращает nil, если модель недоступна.
    func embedding(for text: String, tokenizer: EmbedTokenizer?) -> [Double]? {
        guard let model = embedModel, let tokenizer, let ids = tokenizer.encode(text) else { return nil }
        let seqLen = min(ids.count, Self.embedMaxLength)
        guard seqLen > 0 else { return nil }

        guard
            let inputIds = MLMultiArray.makeInt32(seqLen, value: 0),
            let attentionMask = MLMultiArray.makeInt32(seqLen, value: 0)
        else { return nil }

        for (i, v) in ids.prefix(seqLen).enumerated() {
            inputIds[i] = NSNumber(value: v)
            attentionMask[i] = 1
        }

        guard
            let provider = try? MLDictionaryFeatureProvider(dictionary: [
                "input_ids": inputIds,
                "attention_mask": attentionMask,
            ]),
            let output = try? model.prediction(from: provider),
            let hidden = output.featureValue(for: "last_hidden_state")?.multiArrayValue
        else { return nil }

        // mean-pool по всем токенам (все реальные — mask=1 на все seqLen)
        var sum = [Double](repeating: 0, count: Self.embedDim)
        for i in 0..<seqLen {
            for j in 0..<Self.embedDim {
                sum[j] += Double(hidden[i * Self.embedDim + j].floatValue)
            }
        }
        let norm = sqrt(sum.reduce(0) { $0 + $1 * $1 })
        guard norm > 1e-9 else { return nil }
        return sum.map { $0 / norm }
    }

    /// Подбирает теги по косинусному расстоянию к кандидатным темам.
    func suggestTags(for text: String, candidates: [String], tokenizer: EmbedTokenizer?, threshold: Double = 0.30) -> [TagScore] {
        guard let noteEmbedding = embedding(for: text, tokenizer: tokenizer) else { return [] }

        var scores: [TagScore] = []
        for candidate in candidates {
            guard let candEmb = embedding(for: candidate, tokenizer: tokenizer) else { continue }
            let dot = zip(noteEmbedding, candEmb).reduce(0.0) { $0 + $1.0 * $1.1 }
            if dot >= threshold {
                scores.append(TagScore(tag: candidate, score: dot))
            }
        }
        return scores.sorted { $0.score > $1.score }
    }

    // MARK: - QG (генерация вопросов)

    private static let qgMaxLength = 128
    private static let qgEncoderDim = 512
    private static let qgVocabSize = 250_112  // mT5
    private static let padTokenId = 0
    private static let eosTokenId = 1
    private static let maxNewTokens = 24

    /// Герерирует вопросы по заметке, разбивая её на абзацы (это сглаживает
    /// ограничение длины энкодера). Возвращает вопросы, либо пустой массив.
    func generateQuestions(from text: String, tokenizer: QGTokenizer?, maxQuestions: Int = 4) -> [String] {
        guard let encoder = qgEncoder, let decoder = qgDecoder, let tokenizer else { return [] }

        let paragraphs = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { String($0.prefix(Self.qgMaxLength - 8)) }

        // Если нет пустых строк — нарезаем по предложениям, чтобы уложить в длину.
        let chunks = paragraphs.isEmpty
            ? [String(text.prefix(Self.qgMaxLength * 4))]
            : paragraphs

        var questions: [String] = []
        var guardCount = 0
        var index = 0

        while questions.count < maxQuestions && index < chunks.count {
            let chunk = chunks[index]
            index += 1

            guard let tokens = tokenizer.encode(chunk), !tokens.isEmpty else { continue }
            let tokensLen = min(tokens.count, Self.qgMaxLength - 2)

            guard let enc = Self.runEncoder(encoder, tokens: Array(tokens.prefix(tokensLen)), tokenizer: tokenizer) else {
                continue
            }

            guard let questionTokens = Self.decodeGreedy(decoder, encoder: enc, tokenizer: tokenizer),
                  !questionTokens.isEmpty
            else {
                guardCount += 1
                if guardCount > maxQuestions * 3 { break }
                continue
            }

            let question = tokenizer.decode(questionTokens)
            let cleaned = question.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty && !questions.contains(cleaned) {
                questions.append(cleaned)
            }
            guardCount += 1
            if guardCount > maxQuestions * 3 { break }
        }
        return questions
    }

    private struct EncoderOutput {
        let hidden: MLMultiArray
        let length: Int
    }

    private static func runEncoder(
        _ model: MLModel,
        tokens: [Int],
        tokenizer: QGTokenizer?
    ) -> EncoderOutput? {
        let len = tokens.count
        guard
            let inputIds = MLMultiArray.makeInt32(Self.qgMaxLength, value: 0),
            let attentionMask = MLMultiArray.makeInt32(Self.qgMaxLength, value: 0)
        else { return nil }

        for (i, v) in tokens.enumerated() {
            inputIds[i] = NSNumber(value: v)
            attentionMask[i] = 1
        }

        guard
            let provider = try? MLDictionaryFeatureProvider(dictionary: [
                "input_ids": inputIds,
                "attention_mask": attentionMask,
            ]),
            let output = try? model.prediction(from: provider),
            let hidden = output.featureValue(for: "last_hidden_state")?.multiArrayValue
        else { return nil }

        return EncoderOutput(hidden: hidden, length: len)
    }

    private static func decodeGreedy(
        _ decoder: MLModel,
        encoder: EncoderOutput,
        tokenizer: QGTokenizer?
    ) -> [Int]? {
        var gen: [Int] = [Self.padTokenId]  // decoder_start_token = <pad>

        for _ in 0..<Self.maxNewTokens {
            let currentLen = gen.count
            guard currentLen <= Self.qgMaxLength else { break }

            guard
                let prediction = autoreleasepool(invoking: { () -> MLFeatureProvider? in
                guard
                    let inputIds = MLMultiArray.makeInt32(Self.qgMaxLength, value: Self.padTokenId),
                    let attentionMask = MLMultiArray.makeInt32(Self.qgMaxLength, value: 0),
                    let encoderAttention = MLMultiArray.makeInt32(Self.qgMaxLength, value: 0)
                else { return nil }

                for (i, v) in gen.enumerated() {
                    inputIds[i] = NSNumber(value: v)
                    attentionMask[i] = 1
                }
                for i in 0..<encoder.length {
                    encoderAttention[i] = 1
                }

                do {
                    let provider = try MLDictionaryFeatureProvider(dictionary: [
                        "decoder_input_ids": inputIds,
                        "decoder_attention_mask": attentionMask,
                        "encoder_last_hidden_state": encoder.hidden,
                        "encoder_attention_mask": encoderAttention,
                    ])
                    return try decoder.prediction(from: provider)
                } catch {
                    return nil
                }
            }),
                let logitsRaw = prediction.featureValue(for: "logits")?.multiArrayValue
            else { return gen }

            // Логиты на позиции текущего токена (последний реальный).
            let row = currentLen - 1
            let offset = row * Self.qgVocabularyStride
            var bestToken = Self.eosTokenId
            var bestScore = -Double.infinity
            for v in 0..<Self.qgVocabSize {
                let score = Double(logitsRaw[offset + v].floatValue)
                if score > bestScore {
                    bestScore = score
                    bestToken = v
                }
            }

            if bestToken == Self.eosTokenId { break }
            gen.append(bestToken)
        }
        return gen
    }

    private static let qgVocabularyStride = 250_112
}

// MARK: - MLMultiArray helper

private extension MLMultiArray {
    static func makeInt32(_ length: Int, value: Int) -> MLMultiArray? {
        guard let arr = try? MLMultiArray(
            shape: [1, NSNumber(value: length)],
            dataType: .int32
        ) else { return nil }
        for i in 0..<length {
            arr[i] = NSNumber(value: value)
        }
        return arr
    }
}