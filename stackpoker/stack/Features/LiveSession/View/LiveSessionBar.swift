import SwiftUI

struct LiveSessionBar: View {
    @ObservedObject var sessionStore: SessionStore
    @Binding var isExpanded: Bool // Keep for compatibility but won't use
    var onTap: () -> Void
    let isFirstBar: Bool
    
    // Show the bar if there's an active session
    private var shouldShowBar: Bool {
        return sessionStore.liveSession.buyIn > 0
    }
    
    // Computed properties for formatted time
    private var formattedElapsedTime: String {
        let totalSeconds = Int(sessionStore.liveSession.elapsedTime)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    // Design system colors
    private let primaryTextColor = Color(red: 0.98, green: 0.96, blue: 0.94)
    private let secondaryTextColor = Color(red: 0.9, green: 0.87, blue: 0.84)
    private let glassOpacity = 0.05
    private let materialOpacity = 0.3
    
    private var statusColor: Color {
        sessionStore.liveSession.isActive ? Color.green : Color.orange
    }
    
    private var pulseAnimation: Animation {
        sessionStore.liveSession.isActive ?
            Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true) :
            .default
    }
    
    var body: some View {
        if shouldShowBar {
            HStack(spacing: 12) {
                // Left side - Status and game info
                HStack(spacing: 10) {
                    // Animated status indicator with glow
                    ZStack {
                        // Glow effect
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                            .blur(radius: 4)
                            .opacity(0.6)
                        
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        
                        if sessionStore.liveSession.isActive {
                            Circle()
                                .stroke(statusColor, lineWidth: 1.5)
                                .frame(width: 14, height: 14)
                                .scaleEffect(sessionStore.liveSession.isActive ? 1.4 : 1)
                                .opacity(sessionStore.liveSession.isActive ? 0 : 0.8)
                                .animation(pulseAnimation, value: sessionStore.liveSession.isActive)
                        }
                    }
                    .frame(width: 14, height: 14) // Fixed size for status indicator
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(sessionStore.liveSession.gameName)
                                .font(.plusJakarta(.subheadline, weight: .semibold))
                                .foregroundColor(primaryTextColor)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(1)
                            
                            Text("•")
                                .foregroundColor(secondaryTextColor.opacity(0.5))
                            
                            Text(sessionStore.liveSession.stakes)
                                .font(.plusJakarta(.caption, weight: .medium))
                                .foregroundColor(secondaryTextColor)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        
                        HStack(spacing: 4) {
                            Text(sessionStore.liveSession.isActive ? "Live" : "Paused")
                                .font(.plusJakarta(.caption, weight: .medium))
                                .foregroundColor(statusColor)
                            
                            if sessionStore.liveSession.currentDay > 1 {
                                Text("• Day \(sessionStore.liveSession.currentDay)")
                                    .font(.plusJakarta(.caption, weight: .medium))
                                    .foregroundColor(secondaryTextColor.opacity(0.8))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Right side - Timer and buy-in with fixed sizing
                HStack(spacing: 12) {
                    // Timer with glass background
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(secondaryTextColor.opacity(0.8))
                            .fixedSize()
                        
                        Text(formattedElapsedTime)
                            .font(.plusJakarta(.footnote, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                            .monospacedDigit()
                            .fixedSize(horizontal: true, vertical: false)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                            )
                    )
                    .fixedSize()
                    
                    // Buy-in with glass background
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(secondaryTextColor.opacity(0.8))
                            .fixedSize()
                        
                        Text("$\(Int(sessionStore.liveSession.buyIn))")
                            .font(.plusJakarta(.footnote, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                            .fixedSize(horizontal: true, vertical: false)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                            )
                    )
                    .fixedSize()
                    
                    // Chevron to indicate tap action
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(secondaryTextColor.opacity(0.6))
                        .fixedSize()
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .padding(.top, isFirstBar ? (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.safeAreaInsets.top ?? 0 : 0)
            .background(
                ZStack {
                    // Base dark layer
                    Rectangle()
                        .fill(Color.black.opacity(0.85))
                    
                    // Glass morphism layer
                    Rectangle()
                        .fill(Material.ultraThinMaterial)
                        .opacity(materialOpacity)
                    
                    // Gradient overlay for depth
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.03),
                                    Color.white.opacity(0.01),
                                    Color.clear
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Top edge highlight
                    VStack {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        primaryTextColor.opacity(0.08),
                                        Color.clear
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 0.5)
                        
                        Spacer()
                    }
                    
                    // Bottom edge shadow
                    VStack {
                        Spacer()
                        
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.clear,
                                        Color.black.opacity(0.3)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 1)
                    }
                }
                .ignoresSafeArea(edges: isFirstBar ? .top : [])
            )
            .overlay(
                // Subtle inner border for glass effect
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.02)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
        }
    }
}


#Preview {
    VStack(spacing: 0) {
        // Active session example
        LiveSessionBar(
            sessionStore: {
                let store = SessionStore(userId: "preview")
                store.liveSession = LiveSessionData(
                    isActive: true,
                    startTime: Date(),
                    elapsedTime: 3723,
                    gameName: "MGM Grand",
                    stakes: "$2/$5",
                    buyIn: 500,
                    lastActiveAt: Date(),
                    currentDay: 1
                )
                return store
            }(),
            isExpanded: .constant(false),
            onTap: { print("Tapped active session") },
            isFirstBar: true
        )
        
        // Paused multi-day session example
        LiveSessionBar(
            sessionStore: {
                let store = SessionStore(userId: "preview")
                store.liveSession = LiveSessionData(
                    isActive: false,
                    startTime: Date(),
                    elapsedTime: 18400,
                    gameName: "Aria Poker Room",
                    stakes: "$5/$10",
                    buyIn: 2000,
                    lastPausedAt: Date(),
                    currentDay: 2
                )
                return store
            }(),
            isExpanded: .constant(false),
            onTap: { print("Tapped paused session") },
            isFirstBar: false
        )
        
        Spacer()
    }
    .background(AppBackgroundView())
} 

