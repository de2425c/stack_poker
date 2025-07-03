import SwiftUI  

// MARK: - Swipeable Graph Carousel
struct SwipeableGraphCarousel: View {
    let sessions: [Session]
    let bankrollTransactions: [BankrollTransaction]
    @Binding var selectedTimeRange: Int
    let timeRanges: [String]
    @Binding var selectedGraphIndex: Int
    let adjustedProfitCalculator: ((Session) -> Double)?
    
    @State private var dragOffset: CGFloat = 0
    
    private let graphTypes = ["Bankroll", "Profit", "Monthly"]
    
    init(sessions: [Session], bankrollTransactions: [BankrollTransaction], selectedTimeRange: Binding<Int>, timeRanges: [String], selectedGraphIndex: Binding<Int>, adjustedProfitCalculator: ((Session) -> Double)? = nil) {
        self.sessions = sessions
        self.bankrollTransactions = bankrollTransactions
        self._selectedTimeRange = selectedTimeRange
        self.timeRanges = timeRanges
        self._selectedGraphIndex = selectedGraphIndex
        self.adjustedProfitCalculator = adjustedProfitCalculator
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Swipeable graph container
            TabView(selection: $selectedGraphIndex) {
                // Bankroll Graph (sessions + bankroll adjustments)
                BankrollGraphView(
                    sessions: sessions,
                    bankrollTransactions: bankrollTransactions,
                    selectedTimeRange: selectedTimeRange,
                    timeRanges: timeRanges,
                    adjustedProfitCalculator: adjustedProfitCalculator
                )
                .tag(0)
                
                // Profit Graph (sessions only)
                ProfitGraphView(
                    sessions: sessions,
                    selectedTimeRange: selectedTimeRange,
                    timeRanges: timeRanges,
                    adjustedProfitCalculator: adjustedProfitCalculator
                )
                .tag(1)
                
                // Monthly Profit Bar Chart
                MonthlyProfitBarChart(
                    sessions: sessions,
                    bankrollTransactions: bankrollTransactions,
                    adjustedProfitCalculator: adjustedProfitCalculator,
                    onBarTouch: { monthData in
                        // Handle bar touch to show monthly profit
                        // Could potentially update selectedDataPoint here if needed
                    }
                )
                .tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .frame(height: 280)
            
            // Time period selector (only for bankroll and profit graphs)
            if selectedGraphIndex < 2 {
                HStack {
                    ForEach(Array(timeRanges.enumerated()), id: \.element) { index, rangeString in
                            Button(action: {
                            selectedTimeRange = index
                        }) {
                            Text(rangeString)
                                .font(.system(size: 13, weight: selectedTimeRange == index ? .medium : .regular))
                                .foregroundColor(selectedTimeRange == index ? .white : .gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(selectedTimeRange == index ? Color.gray.opacity(0.3) : Color.clear)
                                .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.top, 16)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            
            // Graph type indicators (moved to bottom, after time selectors)
                                HStack(spacing: 16) {
                ForEach(Array(graphTypes.enumerated()), id: \.offset) { index, type in
                    Button(action: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            selectedGraphIndex = index
                        }
                    }) {
                        Text(type)
                            .font(.system(size: 13, weight: selectedGraphIndex == index ? .semibold : .regular))
                            .foregroundColor(selectedGraphIndex == index ? .white : .gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selectedGraphIndex == index ? Color.gray.opacity(0.3) : Color.clear)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.top, selectedGraphIndex < 2 ? 12 : 16)
        }
        .animation(.easeInOut(duration: 0.3), value: selectedGraphIndex)
    }
}