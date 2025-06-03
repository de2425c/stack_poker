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
        return min(max(challenge.currentValue / challenge.targetValue * 100, 0), 100)
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
                
                // Confetti overlay
                if showConfetti {
                    ConfettiView()
                        .allowsHitTesting(false)
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
    }
    
    @ViewBuilder
    private var challengeCompletionCard: some View {
        VStack(spacing: 24) {
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
            
            // Achievement Stats
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TARGET ACHIEVED")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                        Text(formattedValue(challenge.targetValue, type: challenge.type))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(colorForType(challenge.type))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("COMPLETED IN")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                        Text(completionDuration)
                            .font(.system(size: 20, weight: .bold))
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
            
            // Stack Poker branding
            HStack {
                Spacer()
                Text("stackpoker.gg")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray.opacity(0.6))
                Spacer()
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.4))
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
        Target: \(formattedValue(challenge.targetValue, type: challenge.type))
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
            .frame(width: 400, height: 300)
            .background(Color.black)
        
        // Convert to UIImage (simplified version - in production you'd use ImageRenderer or similar)
        celebrationCard = UIImage(systemName: "trophy.fill") // Placeholder for now
    }
    
    private func shareToSocialMedia() {
        showShareSheet = true
    }
    
    private func postToFeed() {
        // Post completion to the app's feed
        let completionText = """
        🎉 Challenge Completed!
        
        \(challenge.title)
        
        Target: \(formattedValue(challenge.targetValue, type: challenge.type))
        Final: \(formattedValue(challenge.currentValue, type: challenge.type))
        Completed in: \(completionDuration)
        
        #ChallengeCompleted #\(challenge.type.rawValue.capitalized)Goal
        """
        
        Task {
            do {
                try await postService.createPost(
                    content: completionText,
                    userId: challenge.userId,
                    username: userService.currentUserProfile?.username ?? "",
                    displayName: userService.currentUserProfile?.displayName,
                    profileImage: userService.currentUserProfile?.avatarURL,
                    imageURLs: nil,
                    postType: .text,
                    handHistory: nil,
                    sessionId: nil,
                    location: nil,
                    isNote: false
                )
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
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
            return "$\(Int(value).formattedWithCommas)"
        case .hands:
            return "\(Int(value))"
        case .session:
            return "\(Int(value))"
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

// Scale button style for better interaction
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Extension for number formatting
extension Int {
    var formattedWithCommas: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        return numberFormatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
} 