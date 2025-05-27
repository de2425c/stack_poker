import SwiftUI

struct HandsTab: View {
    @ObservedObject var handStore: HandStore
    @State private var selectedHandForReplay: SavedHand? = nil
    @State private var handToDelete: SavedHand? = nil
    @State private var showDeleteAlert: Bool = false
    
    // Group hands by time periods
    private var groupedHands: (today: [SavedHand], lastWeek: [SavedHand], older: [SavedHand]) {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        
        var today: [SavedHand] = []
        var lastWeek: [SavedHand] = []
        var older: [SavedHand] = []
        
                for hand in handStore.savedHands {
            if calendar.isDate(hand.timestamp, inSameDayAs: now) {
                today.append(hand)
            } else if hand.timestamp >= oneWeekAgo && hand.timestamp < startOfToday {
                lastWeek.append(hand)
            } else {
                older.append(hand)
            }
        }
        
        return (today, lastWeek, older)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                // Remove existing Spacer for top padding
                // Spacer()
                //     .frame(height: 16)
                
                LazyVStack(spacing: 16) {
                    // Today's hands
                    if !groupedHands.today.isEmpty {
                        HandListSection(title: "Today", hands: groupedHands.today, onHandTap: { hand in
                            self.selectedHandForReplay = hand
                        }, onHandLongPress: { hand in
                            self.handToDelete = hand
                            self.showDeleteAlert = true
                        })
                    }
                    
                    // Last week's hands
                    if !groupedHands.lastWeek.isEmpty {
                        HandListSection(title: "Last Week", hands: groupedHands.lastWeek, onHandTap: { hand in
                            self.selectedHandForReplay = hand
                        }, onHandLongPress: { hand in
                            self.handToDelete = hand
                            self.showDeleteAlert = true
                        })
                    }
                    
                    // Older hands
                    if !groupedHands.older.isEmpty {
                        HandListSection(title: "All Time", hands: groupedHands.older, onHandTap: { hand in
                            self.selectedHandForReplay = hand
                        }, onHandLongPress: { hand in
                            self.handToDelete = hand
                            self.showDeleteAlert = true
                        })
                    }
                    
                    // Empty state
                    if handStore.savedHands.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                                .padding(.top, 50)
                            
                            Text("No Hands Recorded")
                                .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                            
                            Text("Your hand histories will appear here")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(32)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .padding(.top, 50) // Added 40 points of top padding to the ScrollView
        }
        .sheet(item: $selectedHandForReplay) { handToReplay in
            // Corrected initializer for HandReplayView
            HandReplayView(hand: handToReplay.hand, userId: handStore.userId) 
        }
        .alert("Delete this hand?", isPresented: $showDeleteAlert, presenting: handToDelete) { hand in
            Button("Delete", role: .destructive) {
                Task {
                    try? await handStore.deleteHand(id: hand.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { hand in
            Text("This action cannot be undone.")
        }
    }
}

struct HandListSection: View {
    let title: String
    let hands: [SavedHand]
    var onHandTap: (SavedHand) -> Void // Closure to handle tap, passed from HandsTab
    var onHandLongPress: (SavedHand) -> Void // Closure for long-press
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack(alignment: .center) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Color.gray.opacity(0.85)) // Changed to greyish color
                
                Spacer()
                
                Text("\(hands.count) hands")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color.gray.opacity(0.7))
            }
            .padding(.horizontal, 4)
            
            // Hands in this section - keep original cards
            VStack(spacing: 12) {
                ForEach(hands) { savedHand in
                    HandDisplayCardView(hand: savedHand.hand, 
                                        onReplayTap: {

                                            onHandTap(savedHand) // Call the closure passed from HandsTab
                                        },
                                        location: savedHand.hand.raw.gameInfo.tableSize > 2 ? "Live Game" : "Online Game", // Example: derive from table size or pass nil
                                        createdAt: savedHand.timestamp)
                    .cornerRadius(12) // Keep corner radius if desired for the card's shape
                    .shadow(color: Color.black.opacity(0.1), radius: 3, y: 1) // Adjusted shadow for subtlety
                    .onLongPressGesture {
                        onHandLongPress(savedHand)
                    }
                }
            }
        }
        .padding(.vertical, 12)
    }
}