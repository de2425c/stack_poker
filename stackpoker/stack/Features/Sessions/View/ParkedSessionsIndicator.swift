import SwiftUI

struct ParkedSessionsIndicator: View {
    @ObservedObject var sessionStore: SessionStore
    @State private var showingParkedSessions = false
    
    private var parkedSessionsCount: Int {
        sessionStore.parkedSessions.count
    }
    
    private var hasParkedSessions: Bool {
        parkedSessionsCount > 0
    }
    
    var body: some View {
        if hasParkedSessions {
            Button(action: {
                showingParkedSessions = true
            }) {
                HStack(spacing: 12) {
                    // Icon with badge
                    ZStack {
                        Image(systemName: "bed.double.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.orange)
                        
                        // Badge with count
                        if parkedSessionsCount > 1 {
                            Text("\(parkedSessionsCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.red)
                                .clipShape(Circle())
                                .offset(x: 12, y: -8)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Parked Sessions")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("\(parkedSessionsCount) session\(parkedSessionsCount == 1 ? "" : "s") waiting")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .sheet(isPresented: $showingParkedSessions) {
                ParkedSessionsView(sessionStore: sessionStore)
            }
        }
    }
}

// Compact version for navigation bars or smaller spaces
struct CompactParkedSessionsIndicator: View {
    @ObservedObject var sessionStore: SessionStore
    @State private var showingParkedSessions = false
    
    private var parkedSessionsCount: Int {
        sessionStore.parkedSessions.count
    }
    
    private var hasParkedSessions: Bool {
        parkedSessionsCount > 0
    }
    
    var body: some View {
        if hasParkedSessions {
            Button(action: {
                showingParkedSessions = true
            }) {
                ZStack {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.orange)
                    
                    // Badge with count
                    if parkedSessionsCount > 1 {
                        Text("\(parkedSessionsCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(Color.red)
                            .clipShape(Circle())
                            .offset(x: 10, y: -6)
                    }
                }
            }
            .sheet(isPresented: $showingParkedSessions) {
                ParkedSessionsView(sessionStore: sessionStore)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ParkedSessionsIndicator(sessionStore: {
            let store = SessionStore(userId: "preview")
            store.parkedSessions = [
                "session1_day2": LiveSessionData(
                    id: "session1",
                    isActive: false,
                    startTime: Date(),
                    elapsedTime: 7200,
                    gameName: "WSOP Main Event",
                    stakes: "$10,000 Tournament",
                    buyIn: 10000,
                    isTournament: true,
                    tournamentName: "WSOP Main Event",
                    pausedForNextDay: true,
                    pausedForNextDayDate: Date()
                )
            ]
            return store
        }())
        
        CompactParkedSessionsIndicator(sessionStore: {
            let store = SessionStore(userId: "preview")
            store.parkedSessions = [
                "session1_day2": LiveSessionData(),
                "session2_day2": LiveSessionData()
            ]
            return store
        }())
    }
    .padding()
    .background(Color.black)
} 