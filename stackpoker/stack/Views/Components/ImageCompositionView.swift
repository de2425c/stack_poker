import SwiftUI
import PhotosUI
import FirebaseFirestore // Import for Timestamp

// Helper struct to wrap UIActivityViewController for SwiftUI
struct ActivityViewControllerRepresentable: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    @Environment(\.dismiss) var dismiss // To dismiss the sheet

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        controller.completionWithItemsHandler = { (_, _, _, _) in
            // Automatically dismiss the sheet when the share activity is completed or dismissed
            self.dismiss()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

@available(iOS 16.0, *)
struct ImageCompositionView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.displayScale) var displayScale // For ImageRenderer

    let session: Session
    let backgroundImage: UIImage

    // State for card manipulation
    @State private var cardScale: CGFloat = 0.7 // Initial scale for the card
    @State private var cardOffset: CGSize = .zero

    // Gesture states
    @State private var currentMagnification: CGFloat = 0
    @State private var currentDragOffset: CGSize = .zero
    
    // Card Customization States
    struct ColorOption: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let color: Color
        let isLight: Bool // Hint for text color adjustments
    }

    let cardColorOptions: [ColorOption] = [
        ColorOption(name: "Dark", color: Color(UIColor(red: 28/255, green: 28/255, blue: 32/255, alpha: 1.0)), isLight: false),
        ColorOption(name: "Light", color: Color(UIColor.systemGray6), isLight: true),
        ColorOption(name: "Theme", color: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)).opacity(0.7), isLight: false) // Example theme, adjust opacity
    ]
    @State private var selectedCardColor: Color
    @State private var cardOpacity: Double = 1.0
    
    // Sharing State
    @State private var isSharing: Bool = false
    @State private var imageToShare: UIImage?

    // Initializer to set default selected color
    init(session: Session, backgroundImage: UIImage) {
        self.session = session
        self.backgroundImage = backgroundImage
        _selectedCardColor = State(initialValue: cardColorOptions[0].color)
    }

    // To ensure date formatting is consistent
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func formatDuration(hours: Double) -> String {
        let totalMinutes = Int(hours * 60)
        let hrs = totalMinutes / 60
        let mins = totalMinutes % 60
        return hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
    }

    // The view that will be rendered for sharing (background + card)
    var shareableContentView: some View {
        ZStack {
            Image(uiImage: backgroundImage)
                .resizable()
                .scaledToFit() // Changed from .scaledToFill()

            FinishedSessionCardView(
                gameName: session.gameType.isEmpty ? session.gameName : "\(session.gameType) - \(session.gameName)",
                stakes: session.stakes,
                location: session.gameName,
                date: session.startDate,
                duration: formatDuration(hours: session.hoursPlayed),
                buyIn: session.buyIn,
                cashOut: session.cashout,
                cardBackgroundColor: selectedCardColor,
                cardOpacity: cardOpacity
            )
            .scaleEffect(cardScale + currentMagnification)
            .offset(x: cardOffset.width + currentDragOffset.width, y: cardOffset.height + currentDragOffset.height)
        }
    }

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all) // Base background to avoid white flash

            // Background image, scaled to fill the screen
            Image(uiImage: backgroundImage)
                .resizable()
                .scaledToFit() // Changed from .scaledToFill()
                .edgesIgnoringSafeArea(.all)
                // .overlay(Color.black.opacity(0.1)) // Opacity overlay might not be needed if image doesn't fill screen

            // The session card, movable and scalable
            FinishedSessionCardView(
                gameName: session.gameType.isEmpty ? session.gameName : "\(session.gameType) - \(session.gameName)",
                stakes: session.stakes,
                location: session.gameName,
                date: session.startDate,
                duration: formatDuration(hours: session.hoursPlayed),
                buyIn: session.buyIn,
                cashOut: session.cashout,
                cardBackgroundColor: selectedCardColor,
                cardOpacity: cardOpacity
            )
            .scaleEffect(cardScale + currentMagnification)
            .offset(x: cardOffset.width + currentDragOffset.width, y: cardOffset.height + currentDragOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        currentDragOffset = value.translation
                    }
                    .onEnded { value in
                        cardOffset.width += value.translation.width
                        cardOffset.height += value.translation.height
                        currentDragOffset = .zero
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        currentMagnification = value - 1
                    }
                    .onEnded { value in
                        cardScale += value - 1
                        currentMagnification = 0
                        cardScale = max(0.3, min(cardScale, 2.0))
                    }
            )

            // Controls Overlay
            VStack {
                // Top Controls (Dismiss and Share)
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .shadow(radius: 3)
                            .padding()
                    }
                    Spacer()
                    Button {
                        prepareAndShareImage()
                    } label: {
                        Image(systemName: "square.and.arrow.up.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .shadow(radius: 3)
                            .padding()
                    }
                }
                .padding(.top, safeAreaInsets.top)

                Spacer()

                // Bottom Controls (Card Customization)
                VStack(spacing: 15) {
                    // Opacity Slider
                    HStack {
                        Image(systemName: "slider.horizontal.3").foregroundColor(.white).padding(.leading)
                        Slider(value: $cardOpacity, in: 0.1...1.0)
                            .padding(.horizontal)
                         Text("\(Int(cardOpacity * 100))%")
                            .foregroundColor(.white)
                            .padding(.trailing)
                    }
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    
                    // Color Selection
                    HStack(spacing: 15) {
                        ForEach(cardColorOptions) { option in
                            Button {
                                selectedCardColor = option.color
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Circle()
                                                .stroke(selectedCardColor == option.color ? Color.yellow : Color.white, lineWidth: selectedCardColor == option.color ? 3 : 1)
                                        )
                                    if selectedCardColor == option.color {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.yellow)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                .padding(.bottom, safeAreaInsets.bottom + 10) // Ensure visibility above home bar
            }
        }
        .statusBarHidden(true)
        .sheet(isPresented: $isSharing, onDismiss: { imageToShare = nil }) { // Clear image when sheet dismissed
            if let image = imageToShare {
                ActivityViewControllerRepresentable(activityItems: [image])
            } else {
                // Fallback or error view if image isn't available, though `isSharing` should only be true if image is set.
                Text("Preparing image...")
            }
        }
    }
    
    // Helper to get safe area insets, more robustly
    private var safeAreaInsets: UIEdgeInsets {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.safeAreaInsets ?? .zero
    }

    private func prepareAndShareImage() {
        let viewToRender = shareableContentView
            .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height) // Render at screen size

        let renderer = ImageRenderer(content: viewToRender)
        renderer.scale = displayScale // Use screen scale for high quality

        if let image = renderer.uiImage {
            self.imageToShare = image
            self.isSharing = true // This will trigger the .sheet
        } else {
            // Handle error: image rendering failed
            print("Error: Could not render image for sharing.")
            // Optionally, present an alert to the user
        }
    }
}

// Dummy Session for preview if needed, assuming Session struct exists
// Ensure Session is Codable or provide sample data as in SessionDetailView_Previews
struct ImageCompositionView_Previews: PreviewProvider {
    static func createSampleSession() -> Session {
        // Reuse the sample session logic from SessionDetailView if possible
        // For now, a placeholder if Session can't be directly initialized
        // This assumes Session has an init(id: String, data: [String:Any])
        // and Timestamp exists or is handled.
        // You might need to adjust this based on your actual Session model.
        // let sampleData: [String: Any] = [
        //     "userId": "previewUser",
        //     "gameType": "NL Hold'em",
        //     "gameName": "Preview Game",
        //     "stakes": "$1/$2",
        //     "startDate": Date(), // Firebase Timestamp might need specific handling for previews
        //     "hoursPlayed": 2.5,
        //     "buyIn": 100.0,
        //     "cashout": 150.0,
        //     "profit": 50.0
        //     // Add other necessary fields for Session model
        // ]
        // This is a guess. Replace with your actual Session initializer
        // or a mock that conforms to whatever FinishedSessionCardView expects.
        // If Session requires Firebase's Timestamp, previews can be tricky without a mock.
        // For simplicity, if you have a simple init for Session, use that.
        // Otherwise, you might need a MockSession struct for previews.
        return Session(id: "previewSession", data: sampleDataWithTimestamps())
    }

    static func sampleDataWithTimestamps() -> [String: Any] {
        // This is a helper to create data with Firebase Timestamps for preview
        // It's often easier to have a separate mock object or simplified init for previews.
        #if canImport(FirebaseFirestore)
        return [
            "userId": "previewUser",
            "gameType": "NL Hold'em",
            "gameName": "Preview Game",
            "stakes": "$1/$2",
            "startDate": Timestamp(date: Date()),
            "startTime": Timestamp(date: Date()),
            "endTime": Timestamp(date: Date().addingTimeInterval(2.5 * 3600)),
            "hoursPlayed": 2.5,
            "buyIn": 100.0,
            "cashout": 150.0,
            "profit": 50.0,
            "createdAt": Timestamp(date: Date())
        ]
        #else
        // Fallback if FirebaseFirestore is not available in this preview context
        // (e.g., some non-app targets)
        // This will cause an error if Timestamp is not found, but #if canImport should prevent that.
        // To fully fix, ensure Timestamp is available or provide a mock that doesn't use it.
        return [
            "userId": "previewUser",
            "gameType": "NL Hold'em",
            "gameName": "Preview Game",
            "stakes": "$1/$2",
            "startDate": Date(), // Using Date directly here for fallback.
            "hoursPlayed": 2.5,
            "buyIn": 100.0,
            "cashout": 150.0,
            "profit": 50.0,
             "createdAt": Date() // Using Date directly here for fallback.
        ]
        #endif
    }

    static var previews: some View {
        if #available(iOS 16.0, *) {
            ImageCompositionView(
                session: createSampleSession(),
                backgroundImage: UIImage(systemName: "photo.fill") ?? UIImage() // Placeholder image
            )
        } else {
            Text("ImageCompositionView requires iOS 16.0+")
        }
    }
} 