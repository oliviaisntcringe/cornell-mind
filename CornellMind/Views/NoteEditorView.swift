import SwiftUI
import SwiftData

struct NoteEditorView: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var modelContext
    @State private var showMindMap = false
    @State private var newTag = ""

    private let columnWidth: CGFloat = 1.0 / 3.0

    var body: some View {
        VStack(spacing: 12) {
            if note.title.isEmpty {
                Text("Конспект без названия")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
            } else {
                Text(note.title)
                    .font(.title2.bold())
            }

            HStack(spacing: 10) {
                CornellField(
                    title: "Ключевые вопросы",
                    systemImage: "questionmark.circle",
                    text: $note.questions,
                    placeholder: "Что я запомню из этого конспекта?\n• Вопрос 1\n• Вопрос 2",
                    heightScale: columnWidth
                )
                CornellField(
                    title: "Заметки",
                    systemImage: "note.text",
                    text: $note.notes,
                    placeholder: "Основной конспект…",
                    heightScale: 1.0
                )
            }

            CornellField(
                title: "Резюме",
                systemImage: "text.alignleft",
                text: $note.summary,
                placeholder: "2–3 предложения, резюмирующие суть…",
                heightScale: 1.0
            )
            .frame(minHeight: 100)

            HStack {
                Text("Теги:")
                    .foregroundStyle(.secondary)
                ForEach(Array(note.tags.enumerated()), id: \.offset) { _, tag in
                    TagChip(tag: tag) {
                        note.tags.removeAll { $0 == tag }
                    }
                }
                if !note.tags.isEmpty { Divider().frame(height: 16) }
                TextField("Добавить тег", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .onSubmit(addTag)
                Button { addTag() } label: { Image(systemName: "plus.circle.fill") }
                    .buttonStyle(.borderless)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .navigationTitle(note.title.isEmpty ? "Новый конспект" : note.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showMindMap.toggle()
                } label: {
                    Label("Mind Map", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .popover(isPresented: $showMindMap) {
                    MindMapView(note: note)
                        .frame(minWidth: 640, minHeight: 480)
                }
            }
        }
        .onChange(of: note.questions) { note.updatedAt = .now }
        .onChange(of: note.notes) { note.updatedAt = .now }
        .onChange(of: note.summary) { note.updatedAt = .now }
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !note.tags.contains(trimmed) else { return }
        note.tags.append(trimmed)
        newTag = ""
        note.updatedAt = .now
    }
}

struct CornellField: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    let placeholder: String
    var heightScale: CGFloat = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.callout.bold())
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    TextEditor(text: .constant(placeholder))
                        .font(.body)
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .disabled(true)
                }
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(maxHeight: .infinity)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.3))
            )
        }
        .frame(maxWidth: .infinity)
    }
}

struct TagChip: View {
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.accentColor.opacity(0.15))
        )
    }
}