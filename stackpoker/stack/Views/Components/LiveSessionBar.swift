import SwiftUI

struct LiveSessionBar: View {
    @ObservedObject var sessionStore: SessionStore
    @Binding var isExpanded: Bool
    var onTap: () -> Void
    let isFirstBar: Bool
    
    // Computed properties for formatted time
    private var formattedElapsedTime: String {
        let totalSeconds = Int(sessionStore.liveSession.elapsedTime)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    private var formattedSessionStart: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: sessionStore.liveSession.startTime)
    }
    
    private var accentColor: Color {
        Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))
    }
    
    private var statusColor: Color {
        sessionStore.liveSession.isActive ? accentColor : Color.orange
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Pull handle - always visible
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 4)
                .cornerRadius(2)
                .padding(.vertical, 6)
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }
            
            if isExpanded {
                // Expanded view with detailed session information
                VStack(spacing: 22) {
                    // Game Info Row
                    HStack(alignment: .center) {
                        // Status dot and game info
                        HStack(spacing: 10) {
                            // Animated pulsing dot
                            ZStack {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 10, height: 10)
                                
                                Circle()
                                    .fill(statusColor.opacity(0.5))
                                    .frame(width: 10, height: 10)
                                    .scaleEffect(sessionStore.liveSession.isActive ? 2 : 1)
                                    .opacity(sessionStore.liveSession.isActive ? 0 : 0.5)
                                    .animation(
                                        sessionStore.liveSession.isActive ? 
                                            Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true) : 
                                            .default,
                                        value: sessionStore.liveSession.isActive
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sessionStore.liveSession.gameName)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                Text(sessionStore.liveSession.stakes)
                                    .font(.system(size: 14))
                                    .foregroundColor(accentColor)
                            }
                        }
                        
                        Spacer()
                        
                        // Status badge
                        Text(sessionStore.liveSession.isActive ? "ACTIVE" : "PAUSED")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(statusColor.opacity(0.2))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(statusColor, lineWidth: 1)
                                    )
                            )
                            .foregroundColor(statusColor)
                    }
                    
                    // Session metrics row with elegant cards
                    HStack(spacing: 12) {
                        // Timer card
                        MetricCard(
                            value: formattedElapsedTime,
                            label: "TIME",
                            icon: "clock.fill",
                            color: .white
                        )
                        
                        // Buy-in card
                        MetricCard(
                            value: "$\(Int(sessionStore.liveSession.buyIn))",
                            label: "BUY-IN",
                            icon: "dollarsign.circle.fill",
                            color: accentColor
                        )
                    }
                    
                    // Action buttons row
                    HStack(spacing: 12) {
                        // Pause/Resume button
                        Button(action: {
                            if sessionStore.liveSession.isActive {
                                sessionStore.pauseLiveSession()
                            } else {
                                sessionStore.resumeLiveSession()
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: sessionStore.liveSession.isActive ? "pause.fill" : "play.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(sessionStore.liveSession.isActive ? "Pause" : "Resume")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .foregroundColor(sessionStore.liveSession.isActive ? .black : .white)
                            .background(
                                sessionStore.liveSession.isActive ?
                                    Color.white :
                                    Color.white.opacity(0.2)
                            )
                            .cornerRadius(12)
                        }
                        
                        // Open full view button
                        Button(action: onTap) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.forward.square.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Open")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .foregroundColor(.black)
                            .background(accentColor)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .padding(.top, 6)
            } else {
                // Collapsed bar with essential info
                HStack(alignment: .center, spacing: 12) {
                    // Animated status indicator
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .fill(statusColor.opacity(0.5))
                                .frame(width: 8, height: 8)
                                .scaleEffect(sessionStore.liveSession.isActive ? 2 : 1)
                                .opacity(sessionStore.liveSession.isActive ? 0 : 0.5)
                                .animation(
                                    sessionStore.liveSession.isActive ? 
                                        Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true) : 
                                        .default,
                                    value: sessionStore.liveSession.isActive
                                )
                        )
                    
                    // Game name and status
                    Text("\(sessionStore.liveSession.isActive ? "LIVE" : "PAUSED"): \(sessionStore.liveSession.gameName)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Timer with subtle pulsing animation
                    Text(formattedElapsedTime)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .opacity(sessionStore.liveSession.isActive ? 1.0 : 0.7)
                        .scaleEffect(sessionStore.liveSession.isActive ? 1.0 : 0.98)
                        .animation(
                            sessionStore.liveSession.isActive ? 
                                Animation.easeInOut(duration: 1).repeatForever(autoreverses: true) : 
                                .default,
                            value: sessionStore.liveSession.isActive
                        )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    onTap()
                }
            }
        }
        .padding(.top, isFirstBar ? (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.safeAreaInsets.top ?? 0 : 0)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 30/255, green: 32/255, blue: 40/255),
                    Color(red: 22/255, green: 24/255, blue: 30/255)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: isFirstBar ? .top : [])
        )
    }
}

// Elegant metric card for displaying session statistics
struct MetricCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color.opacity(0.7))
                
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(color.opacity(0.7))
                    .textCase(.uppercase)
            }
            
            Text(value)
                .font(.system(size: 24, weight: .bold, design: value.contains(":") ? .monospaced : .default))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.07))
        )
    }
}

// Subtle pattern overlay to add depth
struct DiamondPatternView: View {
    var body: some View {
        Canvas { context, size in
            let diamondSize: CGFloat = 12
            let spacing: CGFloat = 24
            
            for row in stride(from: 0, to: size.height + diamondSize, by: spacing) {
                for col in stride(from: 0, to: size.width + diamondSize, by: spacing) {
                    let offset = row.truncatingRemainder(dividingBy: 2*spacing) == 0 ? 0 : spacing/2
                    let x = col + offset
                    
                    let path = Path { p in
                        p.move(to: CGPoint(x: x, y: row))
                        p.addLine(to: CGPoint(x: x + diamondSize/2, y: row + diamondSize/2))
                        p.addLine(to: CGPoint(x: x, y: row + diamondSize))
                        p.addLine(to: CGPoint(x: x - diamondSize/2, y: row + diamondSize/2))
                        p.closeSubpath()
                    }
                    
                    context.stroke(
                        path,
                        with: .color(Color.white),
                        lineWidth: 0.5
                    )
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            
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
                        lastActiveAt: Date()
                    )
                    return store
                }(),
                isExpanded: .constant(true),
                onTap: {},
                isFirstBar: true
            )
            
            Spacer()
            
            LiveSessionBar(
                sessionStore: {
                    let store = SessionStore(userId: "preview")
                    store.liveSession = LiveSessionData(
                        isActive: false,
                        startTime: Date(),
                        elapsedTime: 1840,
                        gameName: "Lucky Star Casino",
                        stakes: "$1/$3",
                        buyIn: 300,
                        lastPausedAt: Date()
                    )
                    return store
                }(),
                isExpanded: .constant(false),
                onTap: {},
                isFirstBar: false
            )
            
            Spacer()
        }
    }
} 

