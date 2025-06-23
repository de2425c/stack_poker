import SwiftUI

// Displays every available analytics graph in one scrollable dashboard and offers a single
// entry-point to the existing home-page graph customisation flow.
struct GraphsDashboardView: View {
    // These are required so that the graphs render with real data.
    let userId: String
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var bankrollStore: BankrollStore

    // Pass in the same binding used elsewhere so the customisation sheet edits the same source of truth.
    @Binding var selectedGraphs: [GraphType]

    // Local state just for graphs that need it
    @State private var dayOfWeekStatsPeriod: DayOfWeekStatsPeriod = .month

    // Convenience helpers --------------------------------------------------
    private var allSessions: [Session] { sessionStore.sessions }
    private var allBankrollTxns: [BankrollTransaction] { bankrollStore.transactions }

    private var winRate: Double {
        guard !allSessions.isEmpty else { return 0 }
        let winning = allSessions.filter { $0.profit > 0 }.count
        return Double(winning) / Double(allSessions.count) * 100.0
    }

    // MARK: - View ---------------------------------------------------------
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: Customisation button
                NavigationLink(
                    destination: GraphCustomizationView(
                        userId: userId,
                        sessionStore: sessionStore,
                        selectedGraphs: $selectedGraphs
                    )
                ) {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .medium))
                        Text("Customize Home Page")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 20)
                .padding(.top, 10)

                // MARK: Bonus graphs only (not the static ones)
                ForEach([GraphType.dollarPerHour, GraphType.daily, GraphType.dayOfWeek], id: \.id) { graphType in
                    graphSection(for: graphType)
                }
            }
            .padding(.bottom, 40)
        }
        .background(AppBackgroundView().ignoresSafeArea())
        .navigationTitle("Graphs Dashboard")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Graph builder ---------------------------------------------------
    @ViewBuilder
    private func graphSection(for graphType: GraphType) -> some View {
        switch graphType {
        case .dollarPerHour:
            DollarPerHourGraph(sessions: allSessions)
                .padding(.horizontal, 20)
                
        case .daily:
            DailyTimeMoneyBarGraph(sessions: allSessions)
                .padding(.horizontal, 20)
                
        case .dayOfWeek:
            DayOfWeekStatsBarChart(sessions: allSessions, period: dayOfWeekStatsPeriod)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                
        default:
            EmptyView()
        }
    }
}