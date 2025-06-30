import SwiftUI

struct ChallengeCompletedView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var challengeService: ChallengeService
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var postService: PostService
    
    let challenge: Challenge
    @State private var showConfetti = false
    @State private var showShareSheet = false
    @State private var celebrationCard: UIImage?
    @State private var shareText = ""
    @State private var userComment = ""
    @State private var isPosting = false
    @State private var showPostSuccess = false
    @FocusState private var isCommentFocused: Bool
    
    private var completionDuration: String {
        guard let completedAt = challenge.completedAt else { return "Unknown" }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: challenge.startDate, to: completedAt)
        let days = components.day ?? 0
        
        if days == 0 {
            return "Same day"
        } else if days == 1 {
            return "1 day"
        } else {
            return "\(days) days"
        }
    }
    
    private var progressPercentage: Double {
        if challenge.isCompleted {
            return 100
        }
        return min(max(challenge.currentValue / challenge.targetValue * 100, 0), 100)
    }
    
    // MARK: - Challenge Type Determination for Session Challenges
    private var isSessionCountChallenge: Bool {
        return challenge.type == .session && challenge.targetSessionCount != nil
    }
    private var isHoursBasedSessionChallenge: Bool {
        return challenge.type == .session && challenge.targetSessionCount == nil && challenge.targetHours != nil
    }
    
    private var displayFinalValue: Double {
        if challenge.isCompleted {
            return displayTargetValue
        }
        if challenge.type == .session {
            if isSessionCountChallenge {
                return Double(min(challenge.validSessionsCount, challenge.targetSessionCount ?? 0))
            } else if isHoursBasedSessionChallenge {
                return min(challenge.totalHoursPlayed, challenge.targetHours ?? challenge.targetValue)
            }
        }
        if challenge.type == .bankroll {
            return max(challenge.currentValue, challenge.targetValue)
        }
        return challenge.currentValue
    }
    
    private var displayTargetValue: Double {
        if challenge.type == .session {
            if isSessionCountChallenge {
                return Double(challenge.targetSessionCount ?? 0)
            } else if isHoursBasedSessionChallenge {
                return challenge.targetHours ?? challenge.targetValue
            }
        }
        return challenge.targetValue
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black,
                        Color(red: 0.1, green: 0.2, blue: 0.1),
                        Color.black
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        // Celebration Header
                        VStack(spacing: 16) {
                            Text("🎉")
                                .font(.system(size: 80))
                                .scaleEffect(showConfetti ? 1.2 : 1.0)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showConfetti)
                            
                            Text("Challenge Completed!")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            
                            Text("Congratulations on reaching your goal!")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)
                        
                        // Challenge Card - Shareable
                        challengeCompletionCard
                            .scaleEffect(showConfetti ? 1.05 : 1.0)
                            .animation(.spring(response: 0.8, dampingFraction: 0.7), value: showConfetti)
                        
                        // Comment box
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add a comment for your post (optional)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            TextEditor(text: $userComment)
                                .foregroundColor(.white)
                                .frame(height: 100)
                                .scrollContentBackground(.hidden)
                                .background(Color.black.opacity(0.1))
                                .cornerRadius(10)
                                .focused($isCommentFocused)
                        }
                        .padding(.horizontal, 32)
                        
                        // Action Buttons
                        VStack(spacing: 16) {
                            // Share to Social Media
                            Button(action: shareToSocialMedia) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Share Achievement")
                                        .font(.system(size: 18, weight: .semibold))
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)),
                                            Color(UIColor(red: 100/255, green: 230/255, blue: 85/255, alpha: 1.0))
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .shadow(color: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.4)), radius: 8, y: 3)
                                )
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            // Post to Feed
                            Button(action: postToFeed) {
                                HStack {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Post to Feed")
                                        .font(.system(size: 18, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                        .padding(.horizontal, 32)
                        
                        Spacer(minLength: 50)
                    }
                    .padding(.horizontal, 20)
                }
                .onTapGesture {
                    // Dismiss keyboard when tapping anywhere on the ScrollView
                    isCommentFocused = false
                }
                
                // Confetti overlay
                if showConfetti {
                    ConfettiView()
                        .allowsHitTesting(false)
                }
                
                // Posting overlay
                if isPosting {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("Posting…")
                            .foregroundColor(.white)
                    }
                    .padding(30)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(16)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .onAppear {
            startCelebration()
            generateShareContent()
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = celebrationCard {
                ActivityViewController(activityItems: [image, shareText])
            }
        }
        .alert("Post shared!", isPresented: $showPostSuccess) {
            Button("OK", role: .cancel) { dismiss() }
        }
    }
    
    @ViewBuilder
    private var challengeCompletionCard: some View {
        VStack(spacing: 28) {
            // Header with icon and type
            HStack {
                Image(systemName: challenge.type.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(colorForType(challenge.type))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    
                    Text(challenge.type.displayName + " Challenge")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Completion badge
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                    Text("COMPLETED")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.15))
                        .overlay(
                            Capsule()
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            
            // Achievement Stats (final + target)
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FINAL")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                        Text(formattedValue(challenge.isCompleted ? displayTargetValue : displayFinalValue, type: challenge.type))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(colorForType(challenge.type))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("TARGET")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                        Text(formattedValue(displayTargetValue, type: challenge.type))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                // Progress bar (full)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 12)
                        
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        colorForType(challenge.type),
                                        colorForType(challenge.type).opacity(0.8)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width, height: 12)
                            .animation(.spring(response: 1.0, dampingFraction: 0.8), value: showConfetti)
                    }
                }
                .frame(height: 12)
                
                // Completion details
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Started")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                        Text(formatDate(challenge.startDate))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Completed")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                        Text(formatDate(challenge.completedAt ?? Date()))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
            
            // Duration & branding
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image("stack_logo")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(height: 60)
                    Text("STACK")
                        .font(.plusJakarta(.largeTitle, weight: .black))
                        .foregroundColor(colorForType(challenge.type))
                }
                // Starting bankroll
                if let startRoll = challenge.startingBankroll {
                    Text("Started at " + formattedValue(startRoll, type: .bankroll))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black.opacity(0.5), colorForType(challenge.type).opacity(0.3)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    colorForType(challenge.type).opacity(0.5),
                                    Color.white.opacity(0.1)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: colorForType(challenge.type).opacity(0.3), radius: 20, y: 10)
        )
        .padding(.horizontal, 20)
    }
    
    private func startCelebration() {
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.3)) {
            showConfetti = true
        }
        
        // Hide confetti after a few seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                showConfetti = false
            }
        }
    }
    
    private func generateShareContent() {
        shareText = """
        🎉 Just completed my poker challenge!
        
        \(challenge.title)
        Target: \(formattedValue(displayTargetValue, type: challenge.type))
        Completed in: \(completionDuration)
        
        #PokerChallenge #\(challenge.type.rawValue.capitalized)Goal #StackPoker
        """
        
        // Generate card image for sharing
        Task {
            await generateCelebrationCardImage()
        }
    }
    
    @MainActor
    private func generateCelebrationCardImage() async {
        // Create a view that represents the card for image generation
        let cardView = challengeCompletionCard
            .frame(width: 400, height: 500)
            .background(Color.black)
        
        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: cardView)
            if let uiImg = renderer.uiImage {
                celebrationCard = uiImg
            }
        } else {
            celebrationCard = nil
        }
    }
    
    private func shareToSocialMedia() {
        showShareSheet = true
    }
    
    private func postToFeed() {
        // Post completion to the app's feed
        var completionText = """
🎉 Challenge Completed!

\(challenge.title)

Target: \(formattedValue(displayTargetValue, type: challenge.type))
Final: \(formattedValue(challenge.isCompleted ? displayTargetValue : displayFinalValue, type: challenge.type))

#ChallengeCompleted #\(challenge.type.rawValue.capitalized)Goal
"""
        if !userComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completionText += "\n\n" + userComment
        }
        
        Task {
            await MainActor.run { isPosting = true }
            do {
                try await postService.createPost(
                    content: completionText,
                    userId: challenge.userId,
                    username: userService.currentUserProfile?.username ?? "",
                    displayName: userService.currentUserProfile?.displayName,
                    profileImage: userService.currentUserProfile?.avatarURL,
                    imageURLs: nil,
                    postType: .text,
                    sessionId: nil,
                    location: nil,
                    isNote: false
                )
                
                await MainActor.run {
                    isPosting = false
                    showPostSuccess = true
                }
            } catch {
                await MainActor.run { isPosting = false }
                print("Error posting challenge completion: \(error)")
            }
        }
    }
    
    private func colorForType(_ type: ChallengeType) -> Color {
        switch type {
        case .bankroll: return .green
        case .hands: return .purple
        case .session: return .orange
        }
    }
    
    private func formattedValue(_ value: Double, type: ChallengeType) -> String {
        switch type {
        case .bankroll:
            return "$" + Int(value).formattedWithCommas
        case .hands:
            return "\(Int(value))"
        case .session:
            // Determine if this is hours-based or session-count based
            if isHoursBasedSessionChallenge {
                // Hours-based session challenge
                return String(format: "%.1f hours", value)
            } else if isSessionCountChallenge {
                // Session-count based challenge
                return "\(Int(value)) sessions"
            } else {
                return "Unknown"
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// Confetti animation view
struct ConfettiView: View {
    @State private var confettiItems: [ConfettiItem] = []
    
    var body: some View {
        ZStack {
            ForEach(confettiItems) { item in
                Text(item.emoji)
                    .font(.system(size: item.size))
                    .position(item.position)
                    .opacity(item.opacity)
                    .animation(.linear(duration: item.duration), value: item.position)
            }
        }
        .onAppear {
            generateConfetti()
        }
    }
    
    private func generateConfetti() {
        let emojis = ["🎉", "🎊", "✨", "🏆", "💫", "⭐️", "🌟"]
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        for i in 0..<50 {
            let item = ConfettiItem(
                id: i,
                emoji: emojis.randomElement() ?? "🎉",
                position: CGPoint(
                    x: CGFloat.random(in: 0...screenWidth),
                    y: -50
                ),
                size: CGFloat.random(in: 20...40),
                duration: Double.random(in: 2...4),
                opacity: Double.random(in: 0.6...1.0)
            )
            confettiItems.append(item)
            
            // Animate to bottom
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                withAnimation(.linear(duration: item.duration)) {
                    if let index = confettiItems.firstIndex(where: { $0.id == item.id }) {
                        confettiItems[index].position.y = screenHeight + 100
                        confettiItems[index].opacity = 0
                    }
                }
            }
        }
    }
}

struct ConfettiItem: Identifiable {
    let id: Int
    let emoji: String
    var position: CGPoint
    let size: CGFloat
    let duration: Double
    var opacity: Double
}

// Activity view controller for sharing
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


