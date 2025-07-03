import SwiftUI

struct ParkedSessionsView: View {
    @ObservedObject var sessionStore: SessionStore
    @Environment(\.dismiss) var dismiss
    @State private var showingResumeConfirmation = false
    @State private var showingDiscardConfirmation = false
    @State private var selectedSessionKey: String? = nil
    @State private var selectedSessionInfo: (key: String, displayName: String, nextDayDate: Date)? = nil
    
    private var parkedSessionsInfo: [(key: String, displayName: String, nextDayDate: Date)] {
        sessionStore.getParkedSessionsInfo()
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                
                if parkedSessionsInfo.isEmpty {
                    emptyStateView
                } else {
                    parkedSessionsList
                }
            }
            .navigationTitle("Parked Sessions")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .alert("Resume Session?", isPresented: $showingResumeConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Resume") {
                if let key = selectedSessionKey {
                    sessionStore.restoreParkedSession(key: key)
                    dismiss()
                }
            }
        } message: {
            if let info = selectedSessionInfo {
                Text("Resume \(info.displayName)? This will make it your active session.")
            }
        }
        .alert("Discard Session?", isPresented: $showingDiscardConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                if let key = selectedSessionKey {
                    sessionStore.discardParkedSession(key: key)
                }
            }
        } message: {
            if let info = selectedSessionInfo {
                Text("Permanently discard \(info.displayName)? This action cannot be undone.")
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "bed.double.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.6))
            
            Text("No Parked Sessions")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("Multi-day tournament sessions that are paused for the next day will appear here.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    private var parkedSessionsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(parkedSessionsInfo, id: \.key) { sessionInfo in
                    ParkedSessionCard(
                        sessionInfo: sessionInfo,
                        onResume: {
                            selectedSessionKey = sessionInfo.key
                            selectedSessionInfo = sessionInfo
                            showingResumeConfirmation = true
                        },
                        onDiscard: {
                            selectedSessionKey = sessionInfo.key
                            selectedSessionInfo = sessionInfo
                            showingDiscardConfirmation = true
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
}

struct ParkedSessionCard: View {
    let sessionInfo: (key: String, displayName: String, nextDayDate: Date)
    let onResume: () -> Void
    let onDiscard: () -> Void
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: sessionInfo.nextDayDate)
    }
    
    private var isScheduledForToday: Bool {
        Calendar.current.isDateInToday(sessionInfo.nextDayDate)
    }
    
    private var isOverdue: Bool {
        sessionInfo.nextDayDate < Date()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Session Info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(sessionInfo.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Status Badge
                    HStack(spacing: 4) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 12))
                        Text(statusText)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .clipShape(Capsule())
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    Text("Scheduled for: \(formattedDate)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            // Action Buttons
            HStack(spacing: 12) {
                Button(action: onResume) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 16))
                        Text("Resume")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.black)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                Button(action: onDiscard) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                        Text("Discard")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.white)
                    .background(Color.red.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isOverdue ? Color.red.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private var statusIcon: String {
        if isOverdue {
            return "exclamationmark.triangle.fill"
        } else if isScheduledForToday {
            return "clock.fill"
        } else {
            return "calendar.badge.clock"
        }
    }
    
    private var statusText: String {
        if isOverdue {
            return "Overdue"
        } else if isScheduledForToday {
            return "Today"
        } else {
            return "Scheduled"
        }
    }
    
    private var statusColor: Color {
        if isOverdue {
            return .red
        } else if isScheduledForToday {
            return .orange
        } else {
            return .blue
        }
    }
}

#Preview {
    ParkedSessionsView(sessionStore: {
        let store = SessionStore(userId: "preview")
        // Add some mock parked sessions for preview
        store.parkedSessions = [
            "session1_day2": LiveSessionData(
                id: "session1",
                isActive: false,
                startTime: Date().addingTimeInterval(-86400), // Yesterday
                elapsedTime: 14400, // 4 hours
                gameName: "WSOP Main Event",
                stakes: "$10,000 Tournament",
                buyIn: 10000,
                isTournament: true,
                tournamentName: "WSOP Main Event",
                currentDay: 1,
                pausedForNextDay: true,
                pausedForNextDayDate: Date()
            ),
            "session2_day2": LiveSessionData(
                id: "session2",
                isActive: false,
                startTime: Date().addingTimeInterval(-172800), // 2 days ago
                elapsedTime: 7200, // 2 hours
                gameName: "Daily Deepstack",
                stakes: "$250 Tournament",
                buyIn: 250,
                isTournament: true,
                tournamentName: "Daily Deepstack",
                currentDay: 1,
                pausedForNextDay: true,
                pausedForNextDayDate: Date().addingTimeInterval(86400) // Tomorrow
            )
        ]
        return store
    }())
} 