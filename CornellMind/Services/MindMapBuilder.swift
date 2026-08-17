import Foundation

struct MindMapNode: Identifiable {
    let id: UUID = UUID()
    var text: String
    var children: [MindMapNode] = []
}

enum MindMapBuilder {
    /// Максимум ветвей и листьев, чтобы граф оставался быстрым и читаемым.
    static let maxQuestions = 6
    static let maxLeavesPerQuestion = 4

    /// Строит дерево майндмапа из конспекта Корнелла:
    /// центр — тема, ветви первого уровня — ключевые вопросы,
    /// листья — строки заметок.
    static func build(from note: Note) -> MindMapNode {
        let questions = note.questions
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(maxQuestions)

        let noteLines = note.notes
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let title = note.title.isEmpty ? "Конспект без названия" : note.title

        if questions.isEmpty {
            return MindMapNode(text: title, children: [
                MindMapNode(text: "Резюме", children: [
                    MindMapNode(text: note.summary.isEmpty ? "—" : note.summary)
                ])
            ])
        }

        var children: [MindMapNode] = []
        for question in questions {
            let related = noteLines.filter { $0.localizedCaseInsensitiveContains(questionPrefix(question)) }
            let base = related.isEmpty ? noteLines : related
            let leaves = base.prefix(maxLeavesPerQuestion).map { MindMapNode(text: $0) }
            children.append(MindMapNode(text: question, children: Array(leaves)))
        }

        if !note.summary.isEmpty {
            children.append(MindMapNode(text: "Резюме", children: [
                MindMapNode(text: note.summary)
            ]))
        }

        return MindMapNode(text: title, children: children)
    }

    private static func questionPrefix(_ question: String) -> String {
        let cleaned = question
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "—", with: "")
            .trimmingCharacters(in: .whitespaces)
        let words = cleaned.split(separator: " ").prefix(3).joined(separator: " ")
        return words.isEmpty ? question : words
    }
}