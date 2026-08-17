import SwiftUI
import SwiftData

struct NoteEditorView: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var modelContext
    @State private var showMindMap = false
    @State private var newTag = ""

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(INTR.lime)
                    .frame(width: 10, height: 38)
                Text(note.title.isEmpty ? "БЕЗ НАЗВАНИЯ" : note.title.uppercased())
                    .font(INTR.fontHeader)
                    .foregroundColor(INTR.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
            }

            HStack(alignment: .top, spacing: 10) {
                CornellField(
                    title: "ВОПРОСЫ",
                    systemImage: "questionmark",
                    text: $note.questions,
                    placeholder: "Что запомню?",
                    ratio: 1
                )
                CornellField(
                    title: "ЗАМЕТКИ",
                    systemImage: "doc.plaintext",
                    text: $note.notes,
                    placeholder: "Основной конспект…",
                    ratio: 3
                )
            }

            CornellField(
                title: "РЕЗЮМЕ",
                systemImage: "text.alignleft",
                text: $note.summary,
                placeholder: "Суть в 2–3 предложениях…",
                ratio: 1
            )
            .frame(minHeight: 100)

            HStack(spacing: 8) {
                Text("ТЕГИ:")
                    .font(.caption2.bold())
                    .foregroundColor(INTR.concrete)
                ForEach(Array(note.tags.enumerated()), id: \.offset) { _, tag in
                    TagChip(tag: tag) { note.tags.removeAll { $0 == tag } }
                }
                Spacer()
                TextField("ДОБАВИТЬ ТЕГ", text: $newTag)
                    .textFieldStyle(.plain)
                    .font(.caption.bold())
                    .frame(width: 150)
                    .onSubmit(addTag)
                Button(action: addTag) {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                        .frame(width: 24, height: 24)
                        .background(INTR.graphite)
                        .foregroundColor(INTR.lime)
                }
                .buttonStyle(.plain)
                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(INTR.background)
        .navigationTitle(note.title.isEmpty ? "Новый конспект" : note.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showMindMap.toggle()
                } label: {
                    Label("MIND MAP", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.bordered)
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

/// Поле Cornell в бруталистском стиле. `ratio` задаёт долю ширины (вопросы : заметки).
struct CornellField: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    let placeholder: String
    var ratio: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.bold())
                Text(title)
                    .font(.caption.bold())
                Spacer()
            }
            .foregroundColor(INTR.graphite)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    TextEditor(text: .constant(placeholder))
                        .font(INTR.fontBody)
                        .foregroundColor(INTR.concrete.opacity(0.6))
                        .disabled(true)
                }
                TextEditor(text: $text)
                    .font(INTR.fontBody)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(INTR.text)
                    .frame(maxHeight: .infinity)
            }
            .padding(8)
            .background(Color(hex: 0xF2EFE6))
            .overlay(Rectangle().stroke(INTR.border, lineWidth: 2))
        }
        .frame(maxWidth: .infinity)
        .layoutPriority(ratio > 1 ? 1 : 0)
        .frame(minWidth: ratio > 1 ? 360 : 120)
    }
}

struct TagChip: View {
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tag.uppercased())
                .font(.caption.bold())
                .foregroundColor(INTR.text)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
                    .foregroundColor(INTR.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(INTR.lime)
        .overlay(Rectangle().stroke(INTR.border, lineWidth: 2))
    }
}