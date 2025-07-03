import SwiftUI

struct CashDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: SessionStore
    
    // Filter for cash games only
    private var cashGameSessions: [Session] {
        sessionStore.sessions.filter { session in
            session.gameType.lowercased().contains("cash")
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
                            
                            Text("Cash Game Dashboard")
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
                    CashGameAnalyticsHeader(sessions: cashGameSessions)
                    
                    // Poker Card Stats (Horizontal Scroll)
                    PokerCardStatsSection(sessions: cashGameSessions)
                    
                    // Cash Game Graphs (Horizontal Scroll)
                    CashGameGraphsSection(sessions: cashGameSessions)
                    
                    // Latest Session (Collapsible) with more space
                    if let latestCashSession = cashGameSessions.first {
                        CollapsibleLatestSession(session: latestCashSession)
                    } else {
                        EmptySessionCard()
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
    CashDashboardView()
        .environmentObject(SessionStore(userId: "preview"))
} 