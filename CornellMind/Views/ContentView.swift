import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedNote: Note?
    @State private var searchText: String = ""
    @State private var isLectureMode = false

    private var filteredNotes: [Note] {
        guard !searchText.isEmpty else { return notes }
        let q = searchText.lowercased()
        return notes.filter { note in
            note.title.lowercased().contains(q)
                || note.questions.lowercased().contains(q)
                || note.tags.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        NavigationSplitView {
            NotesListView(
                notes: filteredNotes,
                selection: $selectedNote,
                searchText: $searchText,
                onNew: { newNote() },
                onDelete: { delete($0) },
                onLecture: { isLectureMode = true }
            )
        } detail: {
            if isLectureMode {
                LectureView(
                    isPresented: $isLectureMode,
                    onNoteCreated: { note in
                        isLectureMode = false
                        selectedNote = note
                    }
                )
            } else if let note = selectedNote {
                NoteEditorView(note: note)
                    .id(note.id)
            } else {
                ContentUnavailableView(
                    "Выберите или создайте конспект",
                    systemImage: "note.text",
                    description: Text("Создайте конспект по методу Корнелла — с вопросами, заметками и резюме.")
                )
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func newNote() {
        let note = Note()
        modelContext.insert(note)
        selectedNote = note
    }

    private func delete(_ indexSet: IndexSet) {
        for index in indexSet {
            if filteredNotes.indices.contains(index) {
                let note = filteredNotes[index]
                if selectedNote?.id == note.id { selectedNote = nil }
                modelContext.delete(note)
            }
        }
        try? modelContext.save()
    }
}