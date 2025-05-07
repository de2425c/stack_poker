import SwiftUI

struct AnalyticsView: View {
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var handStore: HandStore
    
    private var totalProfit: Double {
        sessionStore.sessions.reduce(0) { $0 + $1.profit }
    }
    
    private var heroName: String? {
        handStore.savedHands.first?.hand.raw.players.first(where: { $0.isHero })?.name
    }

    private var biggestWin: SavedHand? {
        handStore.savedHands.max(by: { 
            ($0.hand.raw.pot.heroPnl ?? 0) < ($1.hand.raw.pot.heroPnl ?? 0) 
        })
    }

    private var biggestLoss: SavedHand? {
        handStore.savedHands.min(by: { 
            ($0.hand.raw.pot.heroPnl ?? 0) < ($1.hand.raw.pot.heroPnl ?? 0) 
        })
    }

    private var bestHand: SavedHand? {
        handStore.savedHands.filter { handRank(for: $0) > 0 }.max(by: { handRank(for: $0) < handRank(for: $1) })
    }

    private func handRank(for savedHand: SavedHand) -> Int {
        let handString = savedHand.hand.raw.players.first(where: { $0.isHero })?.finalHand ?? ""
        return pokerHandRank(handString)
    }

    private func pokerHandRank(_ hand: String) -> Int {
        if hand.isEmpty || hand == "-" { return 0 }
        
        let ranks = [
            "Royal Flush": 10,
            "Straight Flush": 9,
            "Four of a Kind": 8,
            "Full House": 7,
            "Flush": 6,
            "Straight": 5,
            "Three of a Kind": 4,
            "Two Pair": 3,
            "Pair": 2,
            "High Card": 1
        ]
        
        for (key, value) in ranks {
            if hand.localizedCaseInsensitiveContains(key) { 
                return value 
            }
        }
        return 0
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Profit Graph Section
                VStack(spacing: 16) {
                    HStack {
                        Text("Total Profit")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.gray)
                        Spacer()
                        Text(totalProfit >= 0 ? "+$\(Int(totalProfit))" : "-$\(abs(Int(totalProfit)))")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(totalProfit >= 0 ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .red)
                    }
                    .padding(.horizontal)
                    
                    ProfitGraph(sessionStore: sessionStore)
                }
                .padding(.vertical, 16)
                .background(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // Selected Hands section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Notable Hands")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    
                    VStack(spacing: 16) {
                        if let win = biggestWin {
                            AnalyticsCard(title: "Biggest Win", savedHand: win, amount: win.hand.raw.pot.heroPnl ?? 0, highlightColor: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        }
                        if let loss = biggestLoss {
                            AnalyticsCard(title: "Biggest Loss", savedHand: loss, amount: loss.hand.raw.pot.heroPnl ?? 0, highlightColor: Color(red: 1, green: 0.3, blue: 0.3))
                        }
                        if let best = bestHand {
                            AnalyticsCard(title: "Best Hand", savedHand: best, amount: best.hand.raw.pot.heroPnl ?? 0, highlightColor: .blue, showHand: true)
                        }
                        
                        if biggestWin == nil && biggestLoss == nil && bestHand == nil {
                            HStack {
                                Spacer()
                                Text("No hands recorded yet")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 15, weight: .medium))
                                Spacer()
                            }
                            .padding()
                            .background(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Color(UIColor(red: 22/255, green: 23/255, blue: 26/255, alpha: 1.0)))
        .onAppear {
            sessionStore.fetchSessions()
        }
    }
} 