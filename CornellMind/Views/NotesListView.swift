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
                .tag(note)
            }
            .onDelete(perform: onDelete)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, prompt: "ПОИСК")
        .navigationTitle("INTR.")
        .navigationSubtitle("КОНСПЕКТЫ")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onLecture) {
                    Label("ЛЕКЦИЯ", systemImage: "mic")
                }
                .buttonStyle(.bordered)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: onNew) {
                    Label("НОВЫЙ", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(INTR.lime)
            }
        }
    }
}