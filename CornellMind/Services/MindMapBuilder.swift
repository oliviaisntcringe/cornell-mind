import Foundation

struct MindMapNode: Identifiable {
    let id: UUID = UUID()
    var text: String
    var children: [MindMapNode] = []
}

enum MindMapBuilder {
    /// Строит дерево майндмапа из конспекта Корнелла:
    /// центр — тема, ветви первого уровня — ключевые вопросы,
    /// листья — строки заметок.
    static func build(from note: Note) -> MindMapNode {
        let questions = note.questions
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

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
            var leaves: [MindMapNode] = []
            let related = noteLines.filter { $0.localizedCaseInsensitiveContains(questionPrefix(question)) }
            if related.isEmpty {
                leaves = noteLines.map { MindMapNode(text: $0) }
            } else {
                leaves = related.map { MindMapNode(text: $0) }
            }
            children.append(MindMapNode(text: question, children: leaves))
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