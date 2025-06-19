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
    
    // REMOVED: HandStore for fetching hands related to this session
    // @StateObject private var handStore: HandStore
    
    // StakeService for fetching stakes related to this session
    @StateObject private var stakeService = StakeService()
    @EnvironmentObject var userService: UserService // Add UserService for stake user lookups
    
    // State for fetched hands, notes, and stakes
    // REMOVED: @State private var sessionHands: [SavedHand] = []
    @State private var sessionStakes: [Stake] = []
    // REMOVED: @State private var isLoadingHands: Bool = false
    @State private var isLoadingStakes: Bool = false

    // State for presenting image picker and composition view
    @State private var showingImagePicker = false
    @State private var selectedImageForComposer: UIImage?
    @State private var showImageComposer = false
    
    // State for navigating to HandReplayView
    // REMOVED: @State private var selectedHandForReplay: ParsedHandHistory? = nil
    // REMOVED: @State private var showingHandReplaySheet: Bool = false // Use a sheet for replay for now
    
    // State for presenting EditSessionView with NavigationView instead of sheet
    @State private var showingEditView = false // Changed from showingEditSheet
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
            return session.gameName // Always use the tournament name, not the series
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
    
    @State private var selectedStakeForEdit: Stake? = nil
    
    init(session: Session) {
        self.session = session
        // REMOVED: Initialize HandStore with the current user's ID.
        // Ensure proper fallback or error handling if UID is nil in a real app.
        // _handStore = StateObject(wrappedValue: HandStore(userId: Auth.auth().currentUser?.uid ?? ""))
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
                    VStack(alignment: .leading, spacing: 25) {
                        // Beautiful Session Details Display
                        sessionDetailsView()
                        
                        // Share and Edit Actions
                        actionButtonsView()
                        
                        // Staking Details Section
                        stakingSectionView()
                        
                        // REMOVED: handsSectionView()
                        notesSectionView()
                        
                        Spacer(minLength: 30)
                    }
                    .padding(.top, 20)
                    .padding(.horizontal)
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
            // REMOVED: Hand replay sheet
            /*
            .sheet(isPresented: $showingHandReplaySheet) { 
                if let handToReplay = selectedHandForReplay {
                    HandReplayView(hand: handToReplay, userId: session.userId) 
                } else {
                    Text("No hand selected for replay.") 
                }
            }
            */
            .fullScreenCover(isPresented: $showingEditView) {
                NavigationView {
                    EditSessionSheetView(
                        session: session, 
                        sessionStore: sessionStore, 
                        sessionStakes: sessionStakes, 
                        stakeService: stakeService,
                        onStakeUpdated: {
                            fetchSessionDetails()
                        }
                    )
                    .environmentObject(sessionStore)
                        .environmentObject(userService)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button(action: { 
                                    showingEditView = false 
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Beautiful Session Details Display
    @ViewBuilder
    private func sessionDetailsView() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text(cardGameName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                Text(cardStakes)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.gray)
                
                Text(cardLocation)
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
            }
            
            // Clean Analytics Layout
            VStack(spacing: 24) {
                // Session Metrics - Clean Row Layout
                VStack(spacing: 16) {
                    HStack {
                        MetricItem(label: "Duration", value: formatDuration(hours: session.hoursPlayed))
                        Spacer()
                        MetricItem(label: "Date", value: formatShortDate(session.startDate))
                    }
                    
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1)
                    
                    HStack {
                        MetricItem(label: "Buy-in", value: "$\(session.buyIn.isFinite ? Int(session.buyIn) : 0)")
                        Spacer()
                        MetricItem(label: "Cashout", value: "$\(session.cashout.isFinite ? Int(session.cashout) : 0)")
                    }
                }
                
                // Profit Summary - Clean Layout
                let profit = session.cashout - session.buyIn
                CleanProfitSummary(profit: profit, hoursPlayed: session.hoursPlayed)
            }
        }
    }
    
    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    // MARK: - Action Buttons
    @ViewBuilder
    private func actionButtonsView() -> some View {
        HStack(spacing: 12) {
            Button(action: {
                if #available(iOS 16.0, *) {
                    showingImagePicker = true
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
            }
            .modifier(GlassyButtonStyling())
            
            Button(action: {
                showingEditView = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "pencil.line")
                    Text("Edit Details")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
            }
            .modifier(GlassyButtonStyling())
        }
    }

    // NEW: Extracted Staking Section
    @ViewBuilder
    private func stakingSectionView() -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Staking Details")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            if isLoadingStakes {
                HStack {
                    ProgressView()
                    Text("Loading stakes...")
                        .foregroundColor(.gray)
                }
            } else if !sessionStakes.isEmpty {
                VStack(spacing: 12) {
                    ForEach(sessionStakes) { stake in
                        GlassyStakeCard(stake: stake, userService: userService)
                    }
                }
            } else {
                Text("No stakes found for this session")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.bottom, 25)
    }

    // REMOVED: Hands Section functionality
    /*
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
                }
            }
            .padding(.bottom, 25)
        } else {
            Text("No hands recorded for this session.")
                .font(.caption)
                .foregroundColor(.gray)
                .padding()
        }
    }
    */

    // Extracted Notes Section
    @ViewBuilder
    private func notesSectionView() -> some View {
        if let notes = session.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Session Notes")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                ForEach(notes, id: \.self) { noteText in
                    NoteCardView(noteText: noteText)
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
        // REMOVED: Hands fetching functionality
        /*
        // -----------------------------
        // 1. HANDS
        // -----------------------------
        if let idForHandsQuery = session.liveSessionUUID, !idForHandsQuery.isEmpty {
        isLoadingHands = true
        handStore.fetchHands(forSessionId: idForHandsQuery) { hands in
            self.sessionHands = hands
                self.isLoadingHands = false
            }
        } else {
            // No liveSessionUUID – skip hand fetch gracefully.
            self.isLoadingHands = false
            self.sessionHands = []
        }
        */

        // -----------------------------
        // 2. STAKES
        // -----------------------------
        isLoadingStakes = true

        // Fetch stakes - try both session.id and liveSessionUUID
        Task {
            do {
                print("🔍 [SessionDetailView] Attempting to fetch stakes for session...")
                print("🔍 [SessionDetailView] session.id: '\(session.id)'")
                
                // The user who created the session log is the one who was staked.
                let playerUserId = session.userId
                print("🔍 [SessionDetailView] Fetching for user: '\(playerUserId)'")

                let stakes = try await stakeService.fetchStakesForSession(session.id)
                
                // If that fails, we can try the liveSessionUUID as a fallback, still using the same user.
                if stakes.isEmpty, let liveUUID = session.liveSessionUUID, !liveUUID.isEmpty {
                     print("🔍 [SessionDetailView] No stakes found with session.id, trying liveSessionUUID...")
                     let fallbackStakes = try await stakeService.fetchStakesForSession(liveUUID)
                     await MainActor.run {
                         self.sessionStakes = fallbackStakes
                     }
                } else {
                    await MainActor.run {
                        self.sessionStakes = stakes
                    }
                }
                
                // Fetch user profiles for staker / staked if not already loaded
                for stake in self.sessionStakes {
                    if userService.loadedUsers[stake.stakerUserId] == nil {
                        Task { await userService.fetchUser(id: stake.stakerUserId) }
                    }
                    if userService.loadedUsers[stake.stakedPlayerUserId] == nil {
                        Task { await userService.fetchUser(id: stake.stakedPlayerUserId) }
                    }
                }
                
                await MainActor.run {
                    self.isLoadingStakes = false
                    print("🔍 [SessionDetailView] Final result: \(self.sessionStakes.count) stakes loaded")
                }

            } catch {
                await MainActor.run {
                    self.sessionStakes = []
                    self.isLoadingStakes = false
                    print("❌ [SessionDetailView] Error fetching stakes: \(error)")
                }
            }
        }
    }
}

// MARK: - MetricItem Component
struct MetricItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - CleanProfitSummary Component
struct CleanProfitSummary: View {
    let profit: Double
    let hoursPlayed: Double
    
    private var profitString: String {
        guard profit.isFinite else { return "$0" }
        return "$\(Int(abs(profit)))"
    }
    
    private var hourlyString: String {
        guard hoursPlayed > 0 && profit.isFinite else { return "$0/hr" }
        let hourly = profit / hoursPlayed
        return "$\(Int(abs(hourly)))/hr"
    }
    
    private var profitColor: Color {
        profit >= 0 ? .green : .red
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Net Result")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    Text(profitString)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(profitColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hourly Rate")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    Text(hourlyString)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(profitColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - GlassyStakeCard Component  
struct GlassyStakeCard: View {
    let stake: Stake
    @ObservedObject var userService: UserService
    
    private let glassOpacity = 0.01
    private let materialOpacity = 0.25
    
    private func formatCurrency(_ amount: Double) -> String {
        guard amount.isFinite && !amount.isNaN else {
            return "$0"
        }
        
        if amount >= 0 {
            return "+$\(Int(amount))"
        } else {
            return "-$\(abs(Int(amount)))"
        }
    }
    
    private var stakerName: String {
        if stake.isOffAppStake == true {
            return stake.manualStakerDisplayName ?? "Manual Staker"
        } else if let stakerProfile = userService.loadedUsers[stake.stakerUserId] {
            return stakerProfile.displayName ?? stakerProfile.username
        } else {
            return "Loading..."
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with staker info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Staker: \(stakerName)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("\(stake.stakePercentage.isFinite ? Int(stake.stakePercentage * 100) : 0)% at \(stake.markup, specifier: "%.2f")x markup")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Status")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    
                    Text(stake.status.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(stake.status == .settled ? .green : .orange)
                }
            }
            
            // Financial Grid - Glassy Style
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                StakeInfoItem(
                    title: "Player Buy-in",
                    value: "$\(stake.totalPlayerBuyInForSession.isFinite ? Int(stake.totalPlayerBuyInForSession) : 0)",
                    icon: "arrow.down.circle",
                    color: .orange
                )
                
                StakeInfoItem(
                    title: "Player Cashout", 
                    value: "$\(stake.playerCashoutForSession.isFinite ? Int(stake.playerCashoutForSession) : 0)",
                    icon: "arrow.up.circle",
                    color: .purple
                )
                
                StakeInfoItem(
                    title: "Staker Cost",
                    value: "$\(stake.stakerCost.isFinite ? Int(stake.stakerCost) : 0)",
                    icon: "dollarsign.circle",
                    color: .blue
                )
                
                StakeInfoItem(
                    title: "Settlement",
                    value: formatCurrency(stake.amountTransferredAtSettlement),
                    icon: stake.amountTransferredAtSettlement >= 0 ? "plus.circle.fill" : "minus.circle.fill",
                    color: stake.amountTransferredAtSettlement >= 0 ? .green : .red
                )
            }
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Material.ultraThinMaterial)
                    .opacity(materialOpacity)
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(glassOpacity))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - StakeInfoItem Component
struct StakeInfoItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 50)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
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

