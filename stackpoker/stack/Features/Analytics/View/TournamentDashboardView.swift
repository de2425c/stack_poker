import SwiftUI

struct TournamentDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: SessionStore
    
    // Filter for tournaments only
    private var tournamentSessions: [Session] {
        sessionStore.sessions.filter { session in
            session.gameType.lowercased().contains("tournament")
        }
    }
    
    var body: some View {
        ZStack {
            // Full background
            AppBackgroundView()
                .ignoresSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 40) {
                    // Header with proper spacing from top
                    VStack(spacing: 8) {
                        HStack {
                            Button(action: { dismiss() }) {
                                Image(systemName: "chevron.backward")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            Text("Tournament Dashboard")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            // Invisible button for balance
                            Button(action: {}) {
                                Image(systemName: "chevron.backward")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.clear)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                    }
                    
                    // Main Analytics Section with bigger numbers
                    TournamentAnalyticsHeader(sessions: tournamentSessions)
                    
                    // Poker Card Stats (Horizontal Scroll)
                    TournamentStatsSection(sessions: tournamentSessions)
                    
                    // Tournament Graphs (Horizontal Scroll)
                    TournamentGraphsSection(sessions: tournamentSessions)
                    
                    // Latest Session (Collapsible) with more space
                    if let latestTournamentSession = tournamentSessions.first {
                        CollapsibleLatestSession(session: latestTournamentSession)
                    } else {
                        EmptyTournamentCard()
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 120) // Much more bottom padding
            }
        }
        .onAppear {
            sessionStore.loadSessionsForUI()
        }
    }
}

#Preview {
    TournamentDashboardView()
        .environmentObject(SessionStore(userId: "preview"))
} 