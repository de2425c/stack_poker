import SwiftUI

struct SimpleNoteEditorView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var sessionStore: SessionStore
    let sessionId: String
    var onNoteAdded: ((String) -> Void)? = nil // Callback for when note is added
    
    @State private var noteText: String = ""

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    AppBackgroundView()
                        .ignoresSafeArea()
                        .onTapGesture {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }

                    VStack(spacing: 20) {
                        GlassyInputField(
                            icon: "note.text",
                            title: "Note",
                            glassOpacity: 0.01,
                            labelColor: .gray,
                            materialOpacity: 0.2
                        ) {
                            TextEditor(text: $noteText)
                                .frame(height: geometry.size.height * 0.3)
                                .scrollContentBackground(.hidden)
                                .foregroundColor(.white)
                                .font(.plusJakarta(.body, weight: .regular))
                        }

                        Spacer()

                        Button(action: saveAndDismiss) {
                            Text("Save Note")
                                .font(.plusJakarta(.body, weight: .bold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.5) : Color.white)
                                )
                        }
                        .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: geometry.size.height, alignment: .top)
                }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    private func saveAndDismiss() {
        let trimmedText = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedText.isEmpty else { return }
        
        // Save the note using the existing method
        sessionStore.addNote(note: trimmedText)
        
        // Call the callback if provided (for public session updates)
        onNoteAdded?(trimmedText)
        
        // Clear the text and dismiss
        noteText = ""
        dismiss()
    }
}

struct SimpleNoteEditorView_Previews: PreviewProvider {
    static var previews: some View {
        SimpleNoteEditorView(
            sessionStore: SessionStore(userId: "previewUser"),
            sessionId: "previewSession",
            onNoteAdded: nil
        )
    }
} 