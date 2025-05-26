import SwiftUI
import FirebaseFirestore
import PhotosUI
import UIKit
import FirebaseAuth

// Simple Glassy Button Style for Edit Session
private struct GlassyButtonStyling: ViewModifier {
    var glassOpacity: Double = 0.02
    var materialOpacity: Double = 0.25

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity) // Make it full width
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Material.ultraThinMaterial)
                        .opacity(materialOpacity)
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(glassOpacity))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(0.1), radius: 3, y: 2)
    }
}

struct SessionDetailView: View {
    // Session data
    let session: Session
    @Environment(\.dismiss) var dismiss
    @Environment(\.presentationMode) var presentationMode
    
    // HandStore for fetching hands related to this session
    @StateObject private var handStore: HandStore
    
    // State for fetched hands and notes
    @State private var sessionHands: [SavedHand] = []
    @State private var isLoadingHands: Bool = false
    // @State private var isLoadingNotes: Bool = false

    // State for presenting image picker and composition view
    @State private var showingImagePicker = false
    @State private var selectedImageForComposer: UIImage?
    @State private var showImageComposer = false
    
    // State for navigating to HandReplayView
    @State private var selectedHandForReplay: ParsedHandHistory? = nil
    @State private var showingHandReplaySheet: Bool = false // Use a sheet for replay for now
    
    // State for presenting EditSessionSheetView
    @State private var showingEditSheet = false // New state variable
    @EnvironmentObject var sessionStore: SessionStore // Add SessionStore to environment
    
    // Formatting helpers
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // Computed properties for card display
    private var cardGameName: String {
        if session.gameType == SessionLogType.tournament.rawValue {
            return session.series ?? session.gameName // Series or Tournament Name
        } else {
            return session.gameType.isEmpty ? session.gameName : "\(session.gameType) - \(session.gameName)"
        }
    }
    
    private var cardStakes: String {
        if session.gameType == SessionLogType.tournament.rawValue {
            return session.location ?? "Location TBD" // Location as the secondary line
        } else {
            return session.stakes
        }
    }
    
    private var cardLocation: String {
        if session.gameType == SessionLogType.tournament.rawValue {
            return session.tournamentType ?? "Tournament" // Tournament Type for the original 'location' prop
        } else {
            return session.location ?? session.gameName // Fallback for cash games
        }
    }
    
    init(session: Session) {
        self.session = session
        // Initialize HandStore with the current user's ID.
        // Ensure proper fallback or error handling if UID is nil in a real app.
        _handStore = StateObject(wrappedValue: HandStore(userId: Auth.auth().currentUser?.uid ?? ""))
    }
    
    private func formatDuration(hours: Double) -> String {
        let totalMinutes = Int(hours * 60)
        let hrs = totalMinutes / 60
        let mins = totalMinutes % 60
        return hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
    }
    
    private func dismissView() {
        // Use both dismissal methods to ensure compatibility
        dismiss()
        presentationMode.wrappedValue.dismiss()
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppBackgroundView().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .center, spacing: 15) { // Reduced spacing a bit
                        Text("Tap card to customize & share")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                            .padding(.top, 10)
                            .padding(.bottom, 5)

                        FinishedSessionCardView(
                            gameName: cardGameName,
                            stakes: cardStakes,
                            location: cardLocation, 
                            date: session.startDate,
                            duration: formatDuration(hours: session.hoursPlayed),
                            buyIn: session.buyIn,
                            cashOut: session.cashout
                        )
                        .padding(.horizontal)
                        .onTapGesture {
                            if #available(iOS 16.0, *) {
                                showingImagePicker = true
                            } else {

                            }
                        }
                        
                        // Edit Session Button - Placed here and styled
                        Button(action: {
                            showingEditSheet = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "pencil.line")
                                Text("Edit Session Details")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white) // Text color for the button
                        }
                        .modifier(GlassyButtonStyling())
                        .padding(.horizontal) // Padding for the button itself within the VStack
                        .padding(.top, 5) // Space above the button
                        
                        handsSectionView()
                        notesSectionView()
                        
                        Spacer(minLength: 30) // Keep some space at the bottom
                    }
                    .padding(.top, 20)
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                fetchSessionDetails()
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(selectedImage: $selectedImageForComposer)
            }
            .onChange(of: selectedImageForComposer) { newValue in
                if newValue != nil {
                    showImageComposer = true
                }
            }
            .fullScreenCover(isPresented: $showImageComposer) {
                if let selectedImage = selectedImageForComposer, #available(iOS 16.0, *) {
                    ImageCompositionView(session: session, backgroundImage: selectedImage)
                } else {
                    Text(selectedImageForComposer == nil ? "No image selected." : "Image composition requires iOS 16+")
                        .onAppear {
                            selectedImageForComposer = nil
                            showImageComposer = false
                        }
                }
            }
            .sheet(isPresented: $showingHandReplaySheet) { 
                if let handToReplay = selectedHandForReplay {
                    HandReplayView(hand: handToReplay, userId: session.userId) 
                } else {
                    Text("No hand selected for replay.") 
                }
            }
            .sheet(isPresented: $showingEditSheet) { 
                EditSessionSheetView(session: session, sessionStore: sessionStore)
                    .environmentObject(sessionStore)
            }
        }
    }

    // Extracted Hands Section
    @ViewBuilder
    private func handsSectionView() -> some View {
        if isLoadingHands {
            ProgressView()
                .padding()
        } else if !sessionHands.isEmpty {
            VStack(alignment: .leading, spacing: 15) {
                Text("Hands from this Session")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal)
                
                ForEach(sessionHands) { savedHand in
                    HandDisplayCardView(
                        hand: savedHand.hand, 
                        onReplayTap: {
                            self.selectedHandForReplay = savedHand.hand
                            self.showingHandReplaySheet = true
                        }, 
                        location: session.gameName,
                        createdAt: savedHand.timestamp,
                        showReplayInFeed: false
                    )
                    .padding(.horizontal)
                }
            }
        } else {
            Text("No hands recorded for this session.")
                .font(.caption)
                .foregroundColor(.gray)
                .padding()
        }
    }

    // Extracted Notes Section
    @ViewBuilder
    private func notesSectionView() -> some View {
        if let notes = session.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Session Notes")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal)

                ForEach(notes, id: \.self) { noteText in
                    NoteCardView(noteText: noteText)
                        .padding(.horizontal)
                }
            }
        } else {
            Text("No notes for this session.")
                .font(.caption)
                .foregroundColor(.gray)
                .padding()
        }
    }

    private func fetchSessionDetails() {
        // Fetch Hands using the liveSessionUUID if available, otherwise fall back (though ideally it should always be available for new sessions)
        guard let idForHandsQuery = session.liveSessionUUID, !idForHandsQuery.isEmpty else {

            // Optionally, you could try session.id as a last resort if some old data might use it,
            // but the primary mechanism should be liveSessionUUID.
            // For now, we just won't fetch if the intended ID is missing.
            self.isLoadingHands = false // Stop loading indicator
            self.sessionHands = [] // Ensure hands are empty
            return
        }

        isLoadingHands = true

        handStore.fetchHands(forSessionId: idForHandsQuery) { hands in
            self.sessionHands = hands
            self.isLoadingHands = false

        }
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let provider = results.first?.itemProvider else { return }

            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    self.parent.selectedImage = image as? UIImage
                }
            }
        }
    }
}

