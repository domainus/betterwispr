import BetterWisprCore
import SwiftUI

struct SnippetsView: View {
    @Bindable var model: AppModel
    @State private var cue = ""
    @State private var text = ""
    @State private var editing: Snippet?
    @State private var snippetToDelete: Snippet?

    private var canSave: Bool {
        !cue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Say", text: $cue, prompt: Text("my calendar link"))
                    .onSubmit { if canSave { save() } }
                LabeledContent("Insert") {
                    TextEditor(text: $text)
                        .font(.body)
                        .frame(minHeight: 54, maxHeight: 160)
                        .accessibilityLabel("Insert")
                }
            } header: {
                Text(editing == nil ? "Add a Snippet" : "Edit Snippet")
            } footer: {
                HStack(alignment: .top) {
                    Text("Say these words while dictating and BetterWispr types the text instead, exactly as written here.")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 20)
                    if editing != nil {
                        Button("Cancel", action: reset)
                    }
                    Button(editing == nil ? "Add Snippet" : "Save Changes", action: save)
                        .disabled(!canSave)
                }
            }

            Section {
                if model.snippets.isEmpty {
                    Text("Save text you type often. For example, say “my calendar link” to insert your booking page.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.snippets) { snippet in
                    LabeledContent {
                        HStack(spacing: 10) {
                            Button { edit(snippet) } label: {
                                Image(systemName: "pencil")
                            }
                            .help("Edit \(snippet.cue)")
                            .accessibilityLabel("Edit \(snippet.cue)")
                            Button { snippetToDelete = snippet } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .help("Remove \(snippet.cue)")
                            .accessibilityLabel("Remove \(snippet.cue)")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    } label: {
                        Text(snippet.cue)
                        Text(snippet.text)
                            .lineLimit(2)
                    }
                }
            } header: {
                if model.snippets.isEmpty {
                    Text("Your Snippets")
                } else {
                    Text("^[\(model.snippets.count) snippet](inflect: true)")
                }
            }
        }
        .formStyle(.grouped)
        .alert("Delete this snippet?", isPresented: Binding(
            get: { snippetToDelete != nil },
            set: { if !$0 { snippetToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { snippetToDelete = nil }
            Button("Delete", role: .destructive) {
                if let snippetToDelete {
                    if editing?.id == snippetToDelete.id { reset() }
                    model.deleteSnippet(snippetToDelete)
                }
                snippetToDelete = nil
            }
        } message: {
            Text("Saying “\(snippetToDelete?.cue ?? "")” will no longer insert its text.")
        }
    }

    private func edit(_ snippet: Snippet) {
        editing = snippet
        cue = snippet.cue
        text = snippet.text
    }

    private func save() {
        guard canSave, model.saveSnippet(editing, cue: cue, text: text) else { return }
        reset()
    }

    private func reset() {
        editing = nil
        cue = ""
        text = ""
    }
}
