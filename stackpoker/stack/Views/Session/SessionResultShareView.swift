import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers

struct SessionResultShareView: View {
    let sessionDetails: (buyIn: Double, cashout: Double, profit: Double, duration: String, gameName: String, stakes: String, sessionId: String)?
    let isTournament: Bool
    let onShareToFeed: () -> Void
    let onShareToSocials: (ShareCardType) -> Void
    let onDone: () -> Void
    let onTitleChanged: ((String) -> Void)?
    
    init(sessionDetails: (buyIn: Double, cashout: Double, profit: Double, duration: String, gameName: String, stakes: String, sessionId: String)?, 
         isTournament: Bool, 
         onShareToFeed: @escaping () -> Void, 
         onShareToSocials: @escaping (ShareCardType) -> Void, 
         onDone: @escaping () -> Void, 
         onTitleChanged: ((String) -> Void)? = nil) {
        self.sessionDetails = sessionDetails
        self.isTournament = isTournament
        self.onShareToFeed = onShareToFeed
        self.onShareToSocials = onShareToSocials
        self.onDone = onDone
        self.onTitleChanged = onTitleChanged
    }
    
    @State private var currentCardIndex = 0
    @State private var editableGameName: String = ""
    
    private let cardTypes: [ShareCardType] = [.detailed, .minimal]
    
    var body: some View {
        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with close button
                HStack {
                    Spacer()
                    Button(action: onDone) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.top, 60)
                .padding(.horizontal, 20)
                
                Spacer()
            }
            
            VStack(spacing: 40) {
                // Title based on profit/loss
                if let details = sessionDetails {
                    let isWin = details.profit >= 0
                    Text(isWin ? "Share your win! 🎉" : "Share your loss 😔")
                        .font(.plusJakarta(.title, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 60)
                }
                
                Spacer()
                
                // Swipeable Session Cards
                if let details = sessionDetails {
                    VStack(spacing: 20) {
                        // Card carousel
                        TabView(selection: $currentCardIndex) {
                            ForEach(Array(cardTypes.enumerated()), id: \.offset) { index, cardType in
                                Button(action: { onShareToSocials(cardType) }) {
                                    ShareCardView(
                                        cardType: cardType,
                                        gameName: editableGameName.isEmpty ? details.gameName : editableGameName,
                                        stakes: details.stakes,
                                        duration: details.duration,
                                        buyIn: details.buyIn,
                                        cashOut: details.cashout,
                                        profit: details.profit,
                                        onTitleChanged: { newTitle in
                                            editableGameName = newTitle
                                            onTitleChanged?(newTitle)
                                        }
                                    )
                                }
                                .tag(index)
                            }
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                        .frame(height: 280)
                        
                        // Custom page indicator
                        HStack(spacing: 8) {
                            ForEach(0..<cardTypes.count, id: \.self) { index in
                                Circle()
                                    .fill(currentCardIndex == index ? Color.white : Color.white.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                    .animation(.easeInOut(duration: 0.3), value: currentCardIndex)
                            }
                        }
                        
                        VStack(spacing: 4) {
                            Text("Swipe to see different designs")
                                .font(.plusJakarta(.body, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                            Text("Tap card to share to socials")
                                .font(.plusJakarta(.body, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.top, 8)
                    }
                }
                
                Spacer()
                
                // Bottom Buttons
                VStack(spacing: 16) {
                    Button(action: onShareToFeed) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Share to Feed")
                                .font(.plusJakarta(.body, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color.blue)
                        )
                    }
                    
                    Button(action: onDone) {
                        Text("Done")
                            .font(.plusJakarta(.body, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 25)
                                    .fill(Color.white.opacity(0.2))
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
        .onAppear {
            if let details = sessionDetails {
                editableGameName = details.gameName
            }
        }
    }
}

// MARK: - Share Card Types

enum ShareCardType {
    case detailed
    case minimal
}

// MARK: - Share Card View

struct ShareCardView: View {
    let cardType: ShareCardType
    let gameName: String
    let stakes: String
    let duration: String
    let buyIn: Double
    let cashOut: Double
    let profit: Double
    let onTitleChanged: ((String) -> Void)?
    var showSaveButton: Bool = true
    
    @State private var showingSavedAlert = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main card content (this is what gets saved)
            Group {
                switch cardType {
                case .detailed:
                    FinishedSessionCardView(
                        gameName: gameName,
                        stakes: stakes,
                        date: Date(),
                        duration: duration,
                        buyIn: buyIn,
                        cashOut: cashOut,
                        isBackgroundTransparent: false,
                        onTitleChanged: onTitleChanged
                    )
                case .minimal:
                    MinimalShareCardView(
                        gameName: gameName,
                        stakes: stakes,
                        duration: duration,
                        buyIn: buyIn,
                        cashOut: cashOut,
                        profit: profit,
                        onTitleChanged: onTitleChanged
                    )
                }
            }
            
            // Save to photos button - positioned on the left (overlay, not part of saved image)
            if showSaveButton {
                Button(action: {
                    saveCardToPhotos()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .medium))
                        Text("Save to Photos")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.6))
                    )
                }
                .padding(.top, 12)
                .padding(.leading, 12)
            }
        }
        .alert("Saved to Photos!", isPresented: $showingSavedAlert) {
            Button("OK") { }
        } message: {
            Text("Your poker session card has been saved to your photo library.")
        }
    }
    
    private func saveCardToPhotos() {
        let renderer: ImageRenderer<AnyView>
        
        switch cardType {
        case .detailed:
            let cardView = AnyView(
                FinishedSessionCardView(
                    gameName: gameName,
                    stakes: stakes,
                    date: Date(),
                    duration: duration,
                    buyIn: buyIn,
                    cashOut: cashOut,
                    isBackgroundTransparent: false,
                    onTitleChanged: nil
                )
            )
            renderer = ImageRenderer(content: cardView)
            
        case .minimal:
            // For minimal card, ensure transparent background - capture only the card content
            let cardView = AnyView(
                MinimalShareCardView(
                    gameName: gameName,
                    stakes: stakes,
                    duration: duration,
                    buyIn: buyIn,
                    cashOut: cashOut,
                    profit: profit,
                    onTitleChanged: nil
                )
                .frame(width: 350, height: 280)
                .background(Color.clear)
            )
            renderer = ImageRenderer(content: cardView)
            renderer.proposedSize = .init(width: 350, height: 280)
            renderer.isOpaque = false
        }
        
        renderer.scale = UIScreen.main.scale
        renderer.isOpaque = false // Preserve alpha channel for transparency
        
        if let uiImage = renderer.uiImage {
            if cardType == .minimal {
                // Save as transparent PNG for minimal card
                saveTransparentPNG(image: uiImage)
            } else {
                // Save normally for detailed card
                UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                showSuccessFeedback()
            }
        }
    }
    
    @MainActor
    private func saveTransparentPNG(image: UIImage) {
        guard let pngData = image.pngData() else { return }
        
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else { return }
            PHPhotoLibrary.shared().performChanges {
                let opts = PHAssetResourceCreationOptions()
                opts.uniformTypeIdentifier = UTType.png.identifier // Force PNG
                PHAssetCreationRequest.forAsset().addResource(
                    with: .photo,
                    data: pngData,
                    options: opts
                )
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        self.showSuccessFeedback()
                    }
                }
            }
        }
    }
    
    private func showSuccessFeedback() {
        showingSavedAlert = true
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
}

// MARK: - Minimal Share Card View

struct MinimalShareCardView: View {
    let gameName: String
    let stakes: String
    let duration: String
    let buyIn: Double
    let cashOut: Double
    let profit: Double
    let onTitleChanged: ((String) -> Void)?
    
    @State private var showingEditAlert = false
    @State private var editedTitle: String = ""
    
    private var formattedBuyIn: String { "$\(Int(buyIn))" }
    private var formattedCashOut: String { "$\(Int(cashOut))" }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Completely transparent background - no borders or background
                Color.clear
                
                VStack(spacing: geometry.size.height * 0.02) {
                    // Stack logo positioned above content - smaller to save space
                    Image("promo_logo")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(.white)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width * 0.25, height: geometry.size.height * 0.18)
                    
                    // Main content with labels - reduced spacing
                    VStack(spacing: geometry.size.height * 0.03) {
                        // Duration with label
                        VStack(spacing: 2) {
                            Text("DURATION")
                                .font(.plusJakarta(.caption, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                .tracking(1.0)
                            Text(duration.uppercased())
                                .font(.plusJakarta(.title, weight: .heavy))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        
                        // Buy-in with label
                        VStack(spacing: 2) {
                            Text("BUY-IN")
                                .font(.plusJakarta(.caption, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                .tracking(1.0)
                            Text(formattedBuyIn)
                                .font(.plusJakarta(.title, weight: .heavy))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        
                        // Cashout with label
                        VStack(spacing: 2) {
                            Text("CASHOUT")
                                .font(.plusJakarta(.caption, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                .tracking(1.0)
                            Text(formattedCashOut)
                                .font(.plusJakarta(.title, weight: .heavy))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    
                    Spacer()
                }
                .padding(geometry.size.width * 0.06)
            }
        }
        .frame(width: 350, height: 280)
        .onAppear {
            editedTitle = gameName
        }
        .alert("Edit Game Name", isPresented: $showingEditAlert) {
            TextField("Game name", text: $editedTitle)
            Button("Cancel", role: .cancel) {
                editedTitle = gameName // Reset to original
            }
            Button("Save") {
                saveTitle()
            }
        } message: {
            Text("Enter a new name for this game")
        }
    }
    
    // MARK: - Helper Functions
    private func showEditAlert() {
        editedTitle = gameName
        showingEditAlert = true
    }
    
    private func saveTitle() {
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            onTitleChanged?(trimmedTitle)
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    SessionResultShareView(
        sessionDetails: (
            buyIn: 100.0,
            cashout: 500.0,
            profit: 400.0,
            duration: "3h 45m",
            gameName: "Wynn",
            stakes: "$2/$5",
            sessionId: "preview"
        ),
        isTournament: false,
        onShareToFeed: {},
        onShareToSocials: { _ in },
        onDone: {}
    )
} 