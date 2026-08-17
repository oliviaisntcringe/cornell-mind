import SwiftUI
import SwiftData

/// Режим лекции: большой лист для письма, живые счётчики,
/// по завершении — сводка и генерация Cornell-конспекта + Mind Map.
struct LectureView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Binding var isPresented: Bool
    var onNoteCreated: (Note) -> Void

    @State private var text = ""
    @State private var showSummary = false
    @State private var isGenerating = false
    @State private var generatedNote: Note?
    @State private var generationError: String?

    @State private var startedAt = Date()

    private var stats: TextStats {
        TextStats(text: text, duration: Date().timeIntervalSince(startedAt))
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Режим лекции")
                    .font(.headline)
                Spacer()
                Button("Отмена") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }

            TextEditor(text: $text)
                .font(.body)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.3))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                CounterView(label: "Символов", value: stats.characters)
                Divider().frame(height: 26)
                CounterView(label: "Слов", value: stats.words)
                Divider().frame(height: 26)
                CounterView(label: "Предложений", value: stats.sentences)
                Spacer()

                Button(action: finishLecture) {
                    if isGenerating {
                        HStack { ProgressView().controlSize(.small); Text("Генерация…") }
                    } else {
                        Label("Лекция окончена", systemImage: "checkmark.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
            }
            .padding(.horizontal, 4)
        }
        .padding(16)
        .sheet(isPresented: $showSummary) {
            LectureSummaryView(
                stats: stats,
                note: generatedNote,
                errorMessage: generationError,
                onClose: { isPresented = false },
                onOpen: { note in
                    isPresented = false
                    onNoteCreated(note)
                }
            )
            .frame(width: 520, height: 420)
        }
    }

    private func finishLecture() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isGenerating = true
        Task {
            do {
                let note = try await generateCornellNote(from: text)
                isGenerating = false
                generatedNote = note
                showSummary = true
            } catch {
                isGenerating = false
                generationError = error.localizedDescription
                showSummary = true
            }
        }
    }

    /// Создаёт Note из текста лекции, заполняет вопросы/теги/резюме через ML.
    private func generateCornellNote(from text: String) async throws -> Note {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = Note()
        note.title = makeTitle(from: trimmed)
        note.notes = trimmed

        // ML-часть выполняется в фоне и не должна падать, если модели нет.
        await populateML(note)

        // Резюме: первые 2 предложения, если ML не заполнил.
        if note.summary.isEmpty {
            note.summary = makeSummary(from: trimmed)
        }
        // Статистика как тег-метка.
        note.tags.insert("лекция \(stats.words) слов", at: 0)
        note.updatedAt = .now

        modelContext.insert(note)
        try modelContext.save()
        return note
    }

    private func populateML(_ note: Note) async {
        let ml = MLService.shared
        guard ml.isReady else { return }

        // Токенизаторы загружаются асинхронно.
        guard let qg = try? await AppTokenizers.load(folder: "QG"),
              let embed = try? await AppTokenizers.load(folder: "Embedder")
        else { return }

        let qgTokenizer = QGTokenizer(qg)
        let embedTokenizer = EmbedTokenizer(embed)

        // Вопросы — по заметке.
        if note.questions.isEmpty {
            let questions = ml.generateQuestions(from: note.notes, tokenizer: qgTokenizer, maxQuestions: 5)
            note.questions = questions.joined(separator: "\n")
        }

        // Теги.
        let candidates = Self.defaultTopics
        let tags = ml.suggestTags(for: note.notes, candidates: candidates, tokenizer: embedTokenizer, threshold: 0.25)
        for tag in tags.prefix(3) {
            if !note.tags.contains(tag.tag) {
                note.tags.append(tag.tag)
            }
        }
    }

    private func makeTitle(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let words = firstLine.split(separator: " ").prefix(6).joined(separator: " ")
        return words.isEmpty ? "Лекция \(stats.duration.formatted())" : words
    }

    private func makeSummary(from text: String) -> String {
        // Первые 2 «предложения» (до конца первой строки/второй строки).
        let lines = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.prefix(2).joined(separator: " ")
    }

    private static let defaultTopics = [
        "Математика", "Физика", "Химия", "Биология", "История",
        "Программирование", "Экономика", "Психология", "Литература", "Лингвистика",
    ]
}

private struct CounterView: View {
    let label: String
    let value: Int
    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.callout.monospacedDigit().bold())
        }
    }
}

private struct LectureSummaryView: View {
    let stats: TextStats
    let note: Note?
    let errorMessage: String?
    let onClose: () -> Void
    let onOpen: (Note) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Сводка лекции", systemImage: "checkmark.seal.fill")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                SummaryRow(label: "Символы", value: "\(stats.characters)")
                SummaryRow(label: "Слова", value: "\(stats.words)")
                SummaryRow(label: "Предложения", value: "\(stats.sentences)")
                SummaryRow(label: "Слов в предложении", value: String(format: "%.1f", stats.wordsPerSentence))
                SummaryRow(
                    label: "Длительность",
                    value: Duration.seconds(stats.duration).formatted(.units(allowed: [.minutes, .seconds]))
                )
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if let note {
                if note.questions.isEmpty {
                    Text("Конспект создан. ML-модель была недоступна, вопросы не сгенерированы.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Создан конспект «\(note.title)» с \(note.questions.split(separator: "\n").count) вопросами.")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Закрыть") { onClose() }
                if let note {
                    Button("Открыть в редакторе") {
                        onOpen(note)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
    }
}

private struct SummaryRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }
}