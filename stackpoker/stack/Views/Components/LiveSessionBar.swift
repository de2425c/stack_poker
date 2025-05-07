import SwiftUI

struct LiveSessionBar: View {
    @ObservedObject var sessionStore: SessionStore
    @Binding var isExpanded: Bool
    var onTap: () -> Void
    
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Expand/collapse handle
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 40, height: 5)
                .padding(.vertical, 6)
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                }
            
            if isExpanded {
                // Expanded session details
                VStack(spacing: 16) {
                    HStack(alignment: .center) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(sessionStore.liveSession.isActive ? accentColor : Color.orange)
                                    .frame(width: 14, height: 14)
                                    .shadow(color: (sessionStore.liveSession.isActive ? accentColor : Color.orange).opacity(0.5), radius: 6, y: 0)
                                Circle()
                                    .stroke(Color.white.opacity(0.18), lineWidth: 2)
                                    .frame(width: 20, height: 20)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Live Session")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Text("\(sessionStore.liveSession.gameName) (\(sessionStore.liveSession.stakes))")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }
                        }
                        Spacer()
                        Button(action: onTap) {
                            Text("Open")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(accentColor)
                                .foregroundColor(.black)
                                .cornerRadius(16)
                        }
                    }
                    .padding(.top, 2)
                    
                    HStack(spacing: 18) {
                        // Timer
                        VStack(alignment: .center, spacing: 4) {
                            Text(formattedElapsedTime)
                                .font(.system(size: 26, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Text("Duration")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                        // Start time
                        VStack(alignment: .center, spacing: 4) {
                            Text(formattedSessionStart)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                            Text("Start Time")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                        // Buy-in
                        VStack(alignment: .center, spacing: 4) {
                            Text("$\(Int(sessionStore.liveSession.buyIn))")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(accentColor)
                            Text("Buy-in")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 2)
                    
                    // Pause/Resume button
                    HStack {
                        Spacer()
                        Button(action: {
                            if sessionStore.liveSession.isActive {
                                sessionStore.pauseLiveSession()
                            } else {
                                sessionStore.resumeLiveSession()
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: sessionStore.liveSession.isActive ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 22, weight: .bold))
                                Text(sessionStore.liveSession.isActive ? "Pause" : "Resume")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [accentColor.opacity(0.7), Color.white.opacity(0.12)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(18)
                            .shadow(color: accentColor.opacity(0.18), radius: 6, y: 2)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            } else {
                // Collapsed mini bar
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(sessionStore.liveSession.isActive ? accentColor : Color.orange)
                            .frame(width: 10, height: 10)
                            .shadow(color: (sessionStore.liveSession.isActive ? accentColor : Color.orange).opacity(0.5), radius: 4, y: 0)
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            .frame(width: 16, height: 16)
                    }
                    Text(sessionStore.liveSession.isActive ? "Live Session" : "Session Paused")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Text(formattedElapsedTime)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
        }
        .background(
            BlurView(style: .systemUltraThinMaterialDark)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color(red: 0.08, green: 0.09, blue: 0.12), Color(red: 0.13, green: 0.15, blue: 0.18)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 24 : 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isExpanded ? 24 : 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 2)
        .padding(.horizontal, 8)
        .onTapGesture {
            if !isExpanded {
                onTap()
            }
        }
    }
}

// Helper for glassy blur background
struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
} 