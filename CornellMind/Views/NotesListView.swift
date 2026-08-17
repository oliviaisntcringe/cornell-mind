import SwiftUI
import SwiftData

struct NotesListView: View {
    let notes: [Note]
    @Binding var selection: Note?
    @Binding var searchText: String
    let onNew: () -> Void
    let onDelete: (IndexSet) -> Void
    let onLecture: () -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title.isEmpty ? "Без названия" : note.title)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(note.updatedAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !note.tags.isEmpty {
                            Text(note.tags.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 2)
                .tag(note)
            }
            .onDelete(perform: onDelete)
        }
        .searchable(text: $searchText, prompt: "Поиск по заголовку, тегам…")
        .navigationTitle("Конспекты")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onLecture) {
                    Label("Режим лекции", systemImage: "mic")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: onNew) {
                    Label("Новый конспект", systemImage: "plus")
                }
            }
        }
    }
}