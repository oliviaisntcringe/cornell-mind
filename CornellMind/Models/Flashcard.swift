import Foundation
import SwiftData

@Model
final class Flashcard {
    @Attribute(.unique) var id: UUID
    var question: String
    var answer: String
    var reviewCount: Int
    var nextReview: Date?
    var note: Note?

    init(question: String = "", answer: String = "") {
        self.id = UUID()
        self.question = question
        self.answer = answer
        self.reviewCount = 0
        self.nextReview = nil
    }
}