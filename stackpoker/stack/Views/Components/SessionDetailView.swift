import SwiftUI
import FirebaseFirestore
import PhotosUI
import UIKit
import FirebaseAuth

struct SessionDetailView: View {
    // Session data
    let session: Session
    @Environment(\.dismiss) var dismiss
    
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
    
    // Formatting helpers
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
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
    
    
    var body: some View {
        ZStack {
            // Use the unified app background
            AppBackgroundView()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .center, spacing: 20) {
                    // Instruction text ABOVE card
                    Text("Tap card to customize & share")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        .padding(.top, 10)

                    FinishedSessionCardView(
                        gameName: session.gameType.isEmpty ? session.gameName : "\(session.gameType) - \(session.gameName)",
                        stakes: session.stakes,
                        location: session.gameName,
                        date: session.startDate,
                        duration: formatDuration(hours: session.hoursPlayed),
                        buyIn: session.buyIn,
                        cashOut: session.cashout
                        // Default card background and opacity will be used here
                    )
                    .padding(.horizontal)
                    .onTapGesture {
                        if #available(iOS 16.0, *) {
                            showingImagePicker = true
                        } else {
                            // Legacy share functionality was removed by the user.
                            // Consider an alert or disabling for older OS if ImageCompositionView is core.
                            print("Share functionality requires iOS 16+")
                        }
                    }
                    
                    // Hands Section
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
                                HandSummaryView(hand: savedHand.hand, 
                                                onReplayTap: {
                                                    print("Replay tapped for hand ID: \(savedHand.id). Attempting to show replay sheet.")
                                                    self.selectedHandForReplay = savedHand.hand
                                                    self.showingHandReplaySheet = true
                                                }, 
                                                showReplayButton: true)
                                .padding(.horizontal)
                            }
                        }
                    } else {
                        Text("No hands recorded for this session.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding()
                    }
                    
                    // Notes Section - Now uses session.notes directly
                    if let notes = session.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Session Notes")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal)

                            ForEach(notes, id: \.self) { noteText in
                                SharedNoteView(note: noteText)
                                    .padding(.horizontal)
                            }
                        }
                    } else {
                        Text("No notes for this session.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding()
                    }
                    // Add a flexible spacer at the bottom of the VStack inside ScrollView
                    // to ensure content can be scrolled fully if it's short but scrollable
                    Spacer(minLength: 30) // Adjust minLength as needed
                }
                .padding(.top, 60) // Extra top padding so content starts below close button
            }
        }
        // Close button overlay similar to HandReplayView
        .overlay(
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.leading, 16)
            , alignment: .topLeading
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure ZStack is flexible
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
                // Fallback if no image or not iOS 16+
                Text(selectedImageForComposer == nil ? "No image selected." : "Image composition requires iOS 16+")
                    .onAppear {
                        selectedImageForComposer = nil
                        showImageComposer = false
                    }
            }
        }
        .sheet(isPresented: $showingHandReplaySheet) { // Sheet for Hand Replay
            if let handToReplay = selectedHandForReplay {
                // Assuming HandReplayView exists and can be initialized like this.
                // You might need to pass other environment objects if HandReplayView needs them.
                HandReplayView(hand: handToReplay, userId: session.userId) 
            } else {
                Text("No hand selected for replay.") // Fallback
            }
        }
    }

    private func fetchSessionDetails() {
        // Fetch Hands using the liveSessionUUID if available, otherwise fall back (though ideally it should always be available for new sessions)
        guard let idForHandsQuery = session.liveSessionUUID, !idForHandsQuery.isEmpty else {
            print("SessionDetailView: liveSessionUUID is missing or empty on the session object. Cannot fetch hands.")
            // Optionally, you could try session.id as a last resort if some old data might use it,
            // but the primary mechanism should be liveSessionUUID.
            // For now, we just won't fetch if the intended ID is missing.
            self.isLoadingHands = false // Stop loading indicator
            self.sessionHands = [] // Ensure hands are empty
            return
        }

        isLoadingHands = true
        print("SessionDetailView: Attempting to fetch hands with liveSessionUUID: \(idForHandsQuery)")
        handStore.fetchHands(forSessionId: idForHandsQuery) { hands in
            self.sessionHands = hands
            self.isLoadingHands = false
            print("SessionDetailView: Received \(hands.count) hands from HandStore.")
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

