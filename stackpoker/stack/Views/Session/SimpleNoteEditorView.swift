import SwiftUI
import PhotosUI // Import PhotosUI for image picker

struct SimpleNoteEditorView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var sessionStore: SessionStore
    let sessionId: String
    var existingNoteIndex: Int? = nil
    var existingNoteText: String? = nil

    @State private var noteText: String = ""
    @State private var selectedImage: PhotosPickerItem? = nil
    @State private var imageData: Data? = nil // To store image data for saving
    @State private var showingImagePicker = false
    @State private var isSaving = false

    init(sessionStore: SessionStore, sessionId: String, existingNoteIndex: Int? = nil, existingNoteText: String? = nil) {
        self.sessionStore = sessionStore
        self.sessionId = sessionId
        self.existingNoteIndex = existingNoteIndex
        self.existingNoteText = existingNoteText
        // Initialize noteText with existing text if editing
        _noteText = State(initialValue: existingNoteText ?? "")
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()

                VStack(spacing: 20) { // Added spacing for better visual separation
                    Spacer() // Pushes content down from the top
                    
                    // Text Editor for the note
                    TextEditor(text: $noteText)
                        .scrollContentBackground(.hidden) 
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                        .frame(height: 150) // Fixed height for the text editor
                        .padding(15)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.15))
                        )
                        .padding(.horizontal, 20) // Horizontal padding for the editor container

                    // Image display area
                    if let imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 150) // Constrained image height
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                            .contextMenu {
                                Button(role: .destructive) {
                                    self.selectedImage = nil
                                    self.imageData = nil
                                } label: {
                                    Label("Remove Image", systemImage: "trash")
                                }
                            }
                    } else {
                        // Placeholder if no image, to maintain some space
                        Spacer().frame(height: 150)
                    }

                    Spacer() // Pushes content up from the bottom (before the Add Image button)
                }
                // Removed top padding from here, Spacer handles it
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Button("Save") {
                            saveNote()
                        }
                        .foregroundColor(.white)
                        .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageData == nil)
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(
                Color.black.opacity(0.2), // Semi-transparent black
                for: .navigationBar
            )
            .sheet(isPresented: $showingImagePicker) {
                PhotosPicker(selection: $selectedImage, matching: .images, photoLibrary: .shared()) {
                    Text("Select an image") // This text might not be visible depending on picker style
                }
                .onChange(of: selectedImage) { newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            self.imageData = data
                        }
                    }
                }
            }
            // Add a button to trigger the image picker, placed in the bottom toolbar for clarity
            .safeAreaInset(edge: .bottom) {
                 Button {
                    showingImagePicker = true
                } label: {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("Add Image")
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.3).background(.ultraThinMaterial))
                    .cornerRadius(12)
                }
                .padding()
            }
        }
    }

    private func saveNote() {
        guard !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageData != nil else { return }
        isSaving = true
        
        var noteToSave = noteText
        if imageData != nil {
            if !noteToSave.isEmpty {
                noteToSave += "\n\n[Image Attached]"
            } else {
                noteToSave = "[Image Attached]"
            }
        }
        
        if let editIndex = existingNoteIndex {
            // Update existing note
            sessionStore.updateNote(at: editIndex, with: noteToSave)
        } else {
            // Add new note
            sessionStore.addNote(note: noteToSave)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSaving = false
            dismiss()
        }
    }
}

struct SimpleNoteEditorView_Previews: PreviewProvider {
    static var previews: some View {
        SimpleNoteEditorView(
            sessionStore: SessionStore(userId: "previewUser"),
            sessionId: "previewSession"
        )
    }
} 