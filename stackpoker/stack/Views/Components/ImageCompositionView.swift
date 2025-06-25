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
    let onDismiss: () -> Void // Add closure for parent to handle dismissal
    let overrideGameName: String? // Optional override for edited game name

    // State for card manipulation (drag and scale)
    @State private var interactiveCardOffset: CGSize = .zero
    @State private var currentDragOffset: CGSize = .zero
    @State private var cardScale: CGFloat = 0.8 // Initial scale for the card
    @State private var currentMagnification: CGFloat = 0 // For live pinch gesture
    
    // Card Customization States
    @State private var selectedCardType: ShareCardType = .detailed
    @State private var showingCardPicker: Bool = false
    
    // Sharing State
    @State private var isSharing: Bool = false
    @State private var imageToShare: UIImage?

    // Initializer - now accepts the selected card type and optional override game name
    init(session: Session, backgroundImage: UIImage, selectedCardType: ShareCardType = .detailed, overrideGameName: String? = nil, onDismiss: @escaping () -> Void) {
        self.session = session
        self.backgroundImage = backgroundImage
        self.onDismiss = onDismiss
        self.overrideGameName = overrideGameName
        self._selectedCardType = State(initialValue: selectedCardType)
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
                .scaledToFit() // Match on-screen aspect ratio to avoid stretching
                .clipped()

            ShareCardView(
                cardType: selectedCardType,
                gameName: overrideGameName ?? session.gameName,
                stakes: session.stakes,
                duration: formatDuration(hours: session.hoursPlayed),
                buyIn: session.buyIn,
                cashOut: session.cashout,
                profit: session.profit,
                onTitleChanged: nil
            )
            .scaleEffect(cardScale + currentMagnification) // Include live magnification state
            .offset(x: interactiveCardOffset.width + currentDragOffset.width, // Include live drag state
                    y: interactiveCardOffset.height + currentDragOffset.height)
        }
    }

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            Image(uiImage: backgroundImage)
                .resizable()
                .scaledToFit() // Match on-screen aspect ratio to avoid stretching
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                .edgesIgnoringSafeArea(.all)
                .clipped()

            ShareCardView(
                cardType: selectedCardType,
                gameName: overrideGameName ?? session.gameName,
                stakes: session.stakes,
                duration: formatDuration(hours: session.hoursPlayed),
                buyIn: session.buyIn,
                cashOut: session.cashout,
                profit: session.profit,
                onTitleChanged: nil
            )
            .scaleEffect(cardScale + currentMagnification) // Interactive scaling
            .offset(x: interactiveCardOffset.width + currentDragOffset.width,
                    y: interactiveCardOffset.height + currentDragOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        currentDragOffset = value.translation
                    }
                    .onEnded { value in
                        interactiveCardOffset.width += value.translation.width
                        interactiveCardOffset.height += value.translation.height
                        currentDragOffset = .zero
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        self.currentMagnification = value - 1
                    }
                    .onEnded { value in
                        self.cardScale += (value - 1)
                        self.currentMagnification = 0
                        self.cardScale = max(0.2, min(self.cardScale, 2.5)) // Clamp scale
                    }
            )

            // Controls Overlay – wrapped in GeometryReader to respect dynamic safe-area insets
            GeometryReader { proxy in
                VStack {
                    // Top Controls (Dismiss and Share)
                    HStack {
                        Button {
                            onDismiss()
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
                    .padding(.top, proxy.safeAreaInsets.top)

                    Spacer()

                    // Bottom Controls (Card Type Picker)
                    VStack(spacing: 15) {
                        // Card Type Toggle
                        Button {
                            selectedCardType = selectedCardType == .detailed ? .minimal : .detailed
                        } label: {
                            HStack {
                                Image(systemName: selectedCardType == .minimal ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedCardType == .minimal ? .green : .white)
                                    .padding(.leading)
                                Text("Simple Card Design")
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "rectangle.stack")
                                    .foregroundColor(.white)
                                    .padding(.trailing)
                            }
                            .padding(.vertical, 12)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, proxy.safeAreaInsets.bottom + 10)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
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
    private func prepareAndShareImage() {
        // Capture exactly what the user sees on screen by using the current screen size
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height

        // Calculate the actual size of the background image after .scaledToFit
        let imageAspectRatio = backgroundImage.size.width / backgroundImage.size.height
        let screenAspectRatio = screenWidth / screenHeight

        var finalRenderWidth: CGFloat
        var finalRenderHeight: CGFloat

        if imageAspectRatio > screenAspectRatio { // Image is wider than screen (letterboxed)
            finalRenderWidth = screenWidth
            finalRenderHeight = screenWidth / imageAspectRatio
        } else { // Image is taller than screen (pillarboxed)
            finalRenderHeight = screenHeight
            finalRenderWidth = screenHeight * imageAspectRatio
        }

        let viewToRender = shareableContentView
            .frame(width: finalRenderWidth, height: finalRenderHeight) // Render at the size of the fitted image

        let renderer = ImageRenderer(content: viewToRender)
        // Use device scale for crisp output
        renderer.scale = UIScreen.main.scale

        if let image = renderer.uiImage {
            self.imageToShare = image
            self.isSharing = true // This will trigger the .sheet
        } else {
            // Handle error: image rendering failed

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
                backgroundImage: UIImage(systemName: "photo.fill") ?? UIImage(), // Placeholder image
                onDismiss: {}
            )
        } else {
            Text("ImageCompositionView requires iOS 16.0+")
        }
    }
} 
