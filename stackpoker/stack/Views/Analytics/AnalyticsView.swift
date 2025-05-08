import SwiftUI
import FirebaseAuth

struct AnalyticsCard: View {
    let title: String
    let savedHand: SavedHand
    let amount: Double
    let highlightColor: Color
    var showHand: Bool = false
    
    @State private var showingReplay = false
    @EnvironmentObject var postService: PostService
    @EnvironmentObject var userService: UserService
    
    private var userId: String {
        Auth.auth().currentUser?.uid ?? ""
    }
    
    private var hand: ParsedHandHistory {
        savedHand.hand
    }
    
    private var heroCards: [Card]? {
        if let hero = hand.raw.players.first(where: { $0.isHero }),
           let cards = hero.cards {
            return cards.map { Card(from: $0) }
        }
        return nil
    }
    
    private var handStrength: String? {
        hand.raw.players.first(where: { $0.isHero })?.finalHand
    }
    
    private func formatMoney(_ amount: Double) -> String {
        if amount >= 0 {
            return "+$\(Int(amount))"
        } else {
            return "-$\(abs(Int(amount)))"
        }
    }
    
    var body: some View {
        Button(action: {
            showingReplay = true
        }) {
            VStack(alignment: .leading, spacing: 12) {
                // Title and amount
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                    
                    Text(formatMoney(amount))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(amount >= 0 ? Color(red: 123/255, green: 255/255, blue: 99/255) : .red)
                }
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                // Cards and hand information
                HStack {
                    if let cards = heroCards {
                        HStack(spacing: 4) {
                            ForEach(cards, id: \.id) { card in
                                CardView(card: card)
                                    .aspectRatio(0.69, contentMode: .fit)
                                    .frame(width: 32, height: 46)
                                    .shadow(color: .black.opacity(0.2), radius: 2)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    if let strength = handStrength, showHand {
                        Text(strength)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(red: 45/255, green: 45/255, blue: 55/255))
                            )
                    }
                    
                    // Replay indicator
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 14))
                        Text("Replay")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 60/255, green: 60/255, blue: 70/255))
                    )
                }
                
                // Game info
                HStack {
                    Text("\(hand.raw.gameInfo.smallBlind)/\(hand.raw.gameInfo.bigBlind)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(red: 35/255, green: 35/255, blue: 40/255))
                        )
                    
                    Spacer()
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 28/255, green: 28/255, blue: 32/255))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(highlightColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingReplay) {
            HandReplayView(hand: hand, userId: userId)
                .environmentObject(postService)
                .environmentObject(userService)
        }
    }
}

struct AnalyticsView: View {
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var handStore: HandStore
    @EnvironmentObject var postService: PostService
    @EnvironmentObject var userService: UserService
    
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
                                .environmentObject(postService)
                                .environmentObject(userService)
                        }
                        if let loss = biggestLoss {
                            AnalyticsCard(title: "Biggest Loss", savedHand: loss, amount: loss.hand.raw.pot.heroPnl ?? 0, highlightColor: Color(red: 1, green: 0.3, blue: 0.3))
                                .environmentObject(postService)
                                .environmentObject(userService)
                        }
                        if let best = bestHand {
                            AnalyticsCard(title: "Best Hand", savedHand: best, amount: best.hand.raw.pot.heroPnl ?? 0, highlightColor: .blue, showHand: true)
                                .environmentObject(postService)
                                .environmentObject(userService)
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
