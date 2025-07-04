import SwiftUI

struct AnalyticsView: View {
    @StateObject private var viewModel: AnalyticsViewModel
    @State private var showingBankrollSheet = false
    @State private var showingCashDashboard = false
    @State private var showingTournamentDashboard = false
    
    let userId: String
    let sessionStore: SessionStore
    let bankrollStore: BankrollStore
    let showFilterButton: Bool
    
    init(userId: String, sessionStore: SessionStore, bankrollStore: BankrollStore, showFilterButton: Bool = false) {
        self.userId = userId
        self.sessionStore = sessionStore
        self.bankrollStore = bankrollStore
        self.showFilterButton = showFilterButton
        _viewModel = StateObject(wrappedValue: AnalyticsViewModel(
            sessionStore: sessionStore,
            bankrollStore: bankrollStore,
            userId: userId
        ))
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Analytics Header Section
                AnalyticsHeaderSection(
                    viewModel: viewModel,
                    onAdjustBankroll: { showingBankrollSheet = true }
                )
                
                // Chart display with time selectors at bottom
                if !viewModel.isMainGraphsCollapsed {
                    VStack(spacing: 16) {
                        if viewModel.filteredSessions.isEmpty {
                            VStack(spacing: 12) {
                                Text("😢")
                                    .font(.system(size: 40))
                                Text("You haven't recorded a session in the past \(viewModel.getTimeRangeLabel(for: viewModel.selectedTimeRange).lowercased())")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                            .frame(height: 220)
                            .frame(maxWidth: .infinity)
                        } else {
                            // Swipeable Graph Carousel
                            SwipeableGraphCarousel(
                                sessions: viewModel.filteredSessions,
                                bankrollTransactions: bankrollStore.transactions,
                                selectedTimeRange: $viewModel.selectedTimeRange,
                                timeRanges: ["24H", "1W", "1M", "6M", "1Y", "All"],
                                selectedGraphIndex: $viewModel.selectedGraphTab,
                                adjustedProfitCalculator: viewModel.adjustedProfit
                            )
                            .frame(height: 300)
                            .padding(.horizontal, 4)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                }
                
                // Premium Highlights Carousel Section
                HighlightsSection(viewModel: viewModel)
                    .padding(.top, 24)
                
                // Dashboard Buttons
                VStack(spacing: 12) {
                    CashDashboardButton {
                        showingCashDashboard = true
                    }
                    
                    TournamentDashboardButton {
                        showingTournamentDashboard = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                // Performance Stats Section
                StatsSection(viewModel: viewModel)
                    .padding(.top, 16)
            }
            .padding(.bottom, 40)
        }
        .background(AppBackgroundView().ignoresSafeArea())
        .sheet(isPresented: $showingBankrollSheet) {
            BankrollAdjustmentSheet(
                bankrollStore: bankrollStore,
                currentTotalBankroll: viewModel.totalBankroll
            )
        }
        .sheet(isPresented: $showingCashDashboard) {
            CashDashboardView()
        }
        .sheet(isPresented: $showingTournamentDashboard) {
            TournamentDashboardView()
        }
        .sheet(isPresented: $viewModel.showFilterSheet) {
            let topGames = viewModel.getTop5MostCommonGames()
            AnalyticsFilterSheet(filter: $viewModel.analyticsFilter, topGames: topGames)
        }
        .toolbar {
            if showFilterButton {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { viewModel.showFilterSheet = true }) {
                        Image(systemName: viewModel.analyticsFilter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .onAppear {
            viewModel.ensureAdjustedProfitsCalculated()
        }
    }
}

 