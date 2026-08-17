import Foundation
import SwiftData

@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var title: String
    var questions: String
    var notes: String
    var summary: String
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Flashcard.note)
    var flashcards: [Flashcard]

    init(
        title: String = "",
        questions: String = "",
        notes: String = "",
        summary: String = "",
        tags: [String] = []
    ) {
        self.id = UUID()
        self.title = title
        self.questions = questions
        self.notes = notes
        self.summary = summary
        self.tags = tags
        self.createdAt = .now
        self.updatedAt = .now
        self.flashcards = []
    }
}