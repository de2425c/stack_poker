import SwiftUI
import FirebaseFirestore

struct DashboardView: View {
    @StateObject private var handStore: HandStore
    @StateObject private var sessionStore: SessionStore
    @State private var selectedTab = 0
    private let tabs = ["Analytics", "Hands", "Sessions"]
    @StateObject private var postService = PostService()
    @State private var showingReplay = false
    @State private var selectedHand: ParsedHandHistory?
    
    init(userId: String) {
        _handStore = StateObject(wrappedValue: HandStore(userId: userId))
        _sessionStore = StateObject(wrappedValue: SessionStore(userId: userId))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(UIColor(red: 22/255, green: 23/255, blue: 26/255, alpha: 1.0))
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Top Tab Bar
                    HStack(spacing: 24) {
                        ForEach(0..<tabs.count, id: \.self) { index in
                            TabButton(
                                title: tabs[index],
                                isSelected: selectedTab == index
                            ) {
                                withAnimation {
                                    selectedTab = index
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Content
                    TabView(selection: $selectedTab) {
                        AnalyticsView(sessionStore: sessionStore, handStore: handStore)
                            .tag(0)
                        
                        HandsTab(handStore: handStore)
                            .tag(1)
                        
                        SessionsTab(userId: handStore.userId)
                            .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Image(systemName: "chart.line.uptrend.xyaxis") // or your app icon
                        .foregroundColor(.white)
                        .font(.system(size: 24))
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Image(systemName: "bell")
                        .foregroundColor(.white)
                        .font(.system(size: 20))
                }
            }
        }
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? .white : .gray)
                
                // Underline
                Rectangle()
                    .fill(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                    .frame(height: 2)
                    .opacity(isSelected ? 1 : 0)
            }
        }
    }
}

struct AnalyticsTab: View {
    @ObservedObject var handStore: HandStore

    private var biggestWin: SavedHand? {
        let win = handStore.savedHands.max(by: { 
            ($0.hand.raw.pot.heroPnl ?? 0) < ($1.hand.raw.pot.heroPnl ?? 0) 
        })
        print("Biggest Win: \(win?.hand.raw.pot.heroPnl ?? 0)")
        return win
    }

    private var biggestLoss: SavedHand? {
        let loss = handStore.savedHands.min(by: { 
            ($0.hand.raw.pot.heroPnl ?? 0) < ($1.hand.raw.pot.heroPnl ?? 0) 
        })
        print("Biggest Loss: \(loss?.hand.raw.pot.heroPnl ?? 0)")
        return loss
    }

    private var bestHand: SavedHand? {
        let best = handStore.savedHands.max(by: { handRank(for: $0) < handRank(for: $1) })
        if let best = best {
            print("Best Hand: \(best.hand.raw.players.first(where: { $0.isHero })?.finalHand ?? "none")")
        }
        return best
    }

    private func handRank(for savedHand: SavedHand) -> Int {
        let handString = savedHand.hand.raw.players.first(where: { $0.isHero })?.finalHand ?? ""
        let rank = pokerHandRank(handString)
        print("Hand: \(handString), Rank: \(rank)")
        return rank
    }

    private func pokerHandRank(_ hand: String) -> Int {
        // Higher is better
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
                if let win = biggestWin {
                    AnalyticsCard(title: "Biggest Win", savedHand: win, amount: win.hand.raw.pot.heroPnl ?? 0, highlightColor: .green)
                }
                
                if let loss = biggestLoss {
                    AnalyticsCard(title: "Biggest Loss", savedHand: loss, amount: loss.hand.raw.pot.heroPnl ?? 0, highlightColor: Color(red: 1, green: 0.3, blue: 0.3))
                }
                
                if let best = bestHand {
                    let handString = best.hand.raw.players.first(where: { $0.isHero })?.finalHand ?? "-"
                    if !handString.isEmpty && handString != "-" {
                        AnalyticsCard(title: "Best Hand", savedHand: best, amount: best.hand.raw.pot.heroPnl ?? 0, highlightColor: .blue, showHand: true)
                    }
                }
            }
            .padding()
            .onAppear {
                print("Total hands: \(handStore.savedHands.count)")
                for hand in handStore.savedHands {
                    print("Hand PNL: \(hand.hand.raw.pot.heroPnl ?? 0)")
                    if let hero = hand.hand.raw.players.first(where: { $0.isHero }) {
                        print("Hand type: \(hero.finalHand ?? "none")")
                    }
                }
            }
        }
    }
}

struct AnalyticsCard: View {
    let title: String
    let savedHand: SavedHand
    let amount: Double
    let highlightColor: Color
    var showHand: Bool = false
    @State private var showingReplay = false

    private var hero: Player? {
        savedHand.hand.raw.players.first(where: { $0.isHero })
    }
    private var heroCards: [String] {
        hero?.finalCards ?? hero?.cards ?? []
    }
    private var handType: String {
        hero?.finalHand ?? "-"
    }
    
    private var formattedAmount: String {
        if amount >= 0 {
            return "$\(abs(Int(amount)))"
        } else {
            return "$\(abs(Int(amount)))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(highlightColor)
                Spacer()
                Text(formattedAmount)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(amount >= 0 ? .green : .red)
            }
            Divider().background(Color.white.opacity(0.1))
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    if showHand {
                        Text(handType)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    HStack(spacing: 8) {
                        ForEach(heroCards, id: \.self) { card in
                            CardView(card: Card(from: card))
                                .aspectRatio(0.69, contentMode: .fit)
                                .frame(width: 32, height: 46)
                                .shadow(color: .black.opacity(0.7), radius: 1, x: 0, y: 1)
                        }
                    }
                }
                Spacer()
                Button(action: { showingReplay = true }) {
                    Text("Replay")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 22)
                        .background(highlightColor.opacity(0.8))
                        .cornerRadius(14)
                }
            }
        }
        .padding()
        .background(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
        .cornerRadius(16)
        .shadow(color: highlightColor.opacity(0.15), radius: 8, y: 2)
        .fullScreenCover(isPresented: $showingReplay) {
            HandReplayView(hand: savedHand.hand)
        }
    }
}

struct HandsTab: View {
    @ObservedObject var handStore: HandStore
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(handStore.savedHands) { savedHand in
                    HandSummaryRow(hand: savedHand.hand)
                        .background(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                        .cornerRadius(12)
                        .environmentObject(handStore)
                }
            }
            .padding()
        }
    }
}

struct SessionsTab: View {
    @StateObject private var sessionStore: SessionStore
    
    init(userId: String) {
        _sessionStore = StateObject(wrappedValue: SessionStore(userId: userId))
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(sessionStore.sessions) { session in
                    SessionSummaryRow(session: session)
                        .background(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                        .cornerRadius(12)
                }
            }
            .padding()
        }
    }
}

