import SwiftUI

struct StatsSection: View {
    @ObservedObject var viewModel: AnalyticsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PERFORMANCE STATS")
                        .font(.plusJakarta(.subheadline, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Text(viewModel.analyticsFilter.showRawProfits ? "Raw Profits" : "Staking-Adjusted Profits")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(.gray.opacity(0.7))
                }
                
                if !viewModel.isCustomizingStats {
                    Text("\(viewModel.selectedStats.count)/\(PerformanceStat.allCases.count)")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(.gray.opacity(0.6))
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        viewModel.isCustomizingStats.toggle()
                    }
                }) {
                    Text(viewModel.isCustomizingStats ? "Done" : "Customize Stats")
                        .font(.plusJakarta(.callout, weight: .semibold))
                        .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            
            if viewModel.isCustomizingStats {
                // Customization Interface
                CustomizeStatsView(selectedStats: $viewModel.selectedStats, isDraggingAny: $viewModel.isDraggingAny)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                // Regular Stats Display as Beautiful Boxes
                if viewModel.selectedStats.isEmpty {
                    Text("No stats selected. Tap 'Customize Stats' to add some.")
                        .font(.plusJakarta(.body))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 20)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(viewModel.selectedStats, id: \.id) { stat in
                            StatDisplayCard(
                                stat: stat,
                                value: viewModel.getStatValue(for: stat)
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
        }
        .onChange(of: viewModel.selectedStats) { _ in
            viewModel.saveSelectedStats()
        }
    }
} 