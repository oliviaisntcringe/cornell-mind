import SwiftUI
import SwiftData

struct NotesListView: View {
    let notes: [Note]
    @Binding var selection: Note?
    @Binding var searchText: String
    let onNew: () -> Void
    let onLecture: () -> Void
    let onDelete: (Note) -> Void
    let onRename: (Note, String) -> Void

    @State private var renamingNote: Note?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            headerActions
            notesList
        }
        .searchable(text: $searchText, prompt: "ПОИСК")
        .navigationTitle("INTR.")
        .navigationSubtitle("КОНСПЕКТЫ")
        .sheet(item: $renamingNote) { note in
            RenameNoteSheet(note: note, text: renameText) { newTitle in
                onRename(note, newTitle)
            }
            .frame(width: 360, height: 180)
        }
    }

    private var notesList: some View {
        List(selection: $selection) {
            ForEach(notes) { note in
                NoteRow(note: note)
                    .tag(note)
                    .contextMenu {
                        Button("Переименовать", systemImage: "pencil") {
                            renameText = note.title
                            renamingNote = note
                        }
                        Divider()
                        Button("Удалить", systemImage: "trash", role: .destructive) {
                            if selection?.id == note.id { selection = nil }
                            onDelete(note)
                        }
                    }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    if notes.indices.contains(index) {
                        let note = notes[index]
                        if selection?.id == note.id { selection = nil }
                        onDelete(note)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            Button(action: onNew) {
                Label("НОВЫЙ", systemImage: "plus")
                    .font(.system(.headline, design: .default).weight(.black))
                    .foregroundColor(INTR.text)
                    .frame(height: 34)
                    .padding(.horizontal, 16)
                    .background(INTR.lime)
                    .overlay(Rectangle().stroke(INTR.border, lineWidth: 2))
            }
            .buttonStyle(.plain)

            Button(action: onLecture) {
                Label("ЛЕКЦИЯ", systemImage: "mic")
                    .font(.system(.headline, design: .default).weight(.black))
                    .foregroundColor(INTR.text)
                    .frame(height: 34)
                    .padding(.horizontal, 16)
                    .background(INTR.red)
                    .overlay(Rectangle().stroke(INTR.border, lineWidth: 2))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(INTR.background)
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title.isEmpty ? "БЕЗ НАЗВАНИЯ" : note.title.uppercased())
                .font(.system(.headline, design: .default).weight(.black))
                .foregroundColor(INTR.text)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(note.updatedAt, style: .date)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(INTR.concrete)
                if !note.tags.isEmpty {
                    Text(note.tags.joined(separator: " · ").uppercased())
                        .font(.caption2)
                        .foregroundColor(INTR.red)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct RenameNoteSheet: View {
    let note: Note
    let text: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: String

    init(note: Note, text: String, onSave: @escaping (String) -> Void) {
        self.note = note
        self.text = text
        self.onSave = onSave
        _value = State(initialValue: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ПЕРЕИМЕНОВАТЬ")
                .font(INTR.fontHeader)
                .foregroundColor(INTR.text)
            TextField("Название", text: $value)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(8)
                .background(Color(hex: 0xF2EFE6))
                .overlay(Rectangle().stroke(INTR.border, lineWidth: 2))
                .onSubmit(save)
            Spacer()
            HStack {
                Button("ОТМЕНА") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.caption.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay(Rectangle().stroke(INTR.border, lineWidth: 2))
                Spacer()
                Button("СОХРАНИТЬ") {
                    save()
                }
                .buttonStyle(.plain)
                .font(.caption.bold())
                .foregroundColor(INTR.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(INTR.lime)
                .overlay(Rectangle().stroke(INTR.border, lineWidth: 2))
            }
        }
        .padding(20)
        .background(INTR.background)
    }

    private func save() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(trimmed)
        dismiss()
    }
}