import Foundation
import Tokenizers

/// Универсальный загрузчик токенизаторов из бандла через swift-transformers.
/// Требуется macOS 13+, продукт `Tokenizers` из swift-transformers.
struct AppTokenizers {
    /// Загружает токенизатор из папки-фolder reference в бандле.
    static func load(folder: String) async throws -> any Tokenizer {
        // Папки QG/Embedder копируются в бандл как folder references
        // (Contents/Resources/QG, Contents/Resources/Embedder).
        guard let resourceURL = Bundle.main.resourceURL else {
            throw MLError.tokenizerNotFound(folder)
        }
        let url = resourceURL.appendingPathComponent(folder)
        // swift-transformers ожидает папку с tokenizer_config.json + tokenizer.json
        let hasConfig = FileManager.default.fileExists(atPath: url.appendingPathComponent("tokenizer_config.json").path)
        let hasData = FileManager.default.fileExists(atPath: url.appendingPathComponent("tokenizer.json").path)
        guard hasConfig && hasData else {
            throw MLError.tokenizerNotFound(folder)
        }
        return try await AutoTokenizer.from(modelFolder: url)
    }
}

/// Токенизатор QG (mT5).
struct QGTokenizer {
    private let tokenizer: any Tokenizer
    init(_ tokenizer: any Tokenizer) {
        self.tokenizer = tokenizer
    }
    func encode(_ text: String) -> [Int]? {
        tokenizer.encode(text: text)
    }
    func decode(_ tokens: [Int]) -> String {
        tokenizer.decode(tokens: tokens, skipSpecialTokens: true)
    }
}

/// Токенизатор Embedder (DistilBERT multilingual).
struct EmbedTokenizer {
    private let tokenizer: any Tokenizer
    init(_ tokenizer: any Tokenizer) {
        self.tokenizer = tokenizer
    }
    func encode(_ text: String) -> [Int]? {
        tokenizer.encode(text: text)
    }
}