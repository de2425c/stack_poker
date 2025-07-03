import SwiftUI

struct AnalyticsHeaderSection: View {
    @ObservedObject var viewModel: AnalyticsViewModel
    let onAdjustBankroll: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Dynamic header title based on selected graph tab and profit calculation mode
            let profitMode = viewModel.analyticsFilter.showRawProfits ? "Raw" : "Staking Adjusted"
            Text(viewModel.selectedGraphTab == 0 ? "Bankroll (\(profitMode))" : (viewModel.selectedGraphTab == 1 ? "Profit (\(profitMode))" : "Monthly Profit (\(profitMode))"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray)
            
            // Show aggregated value with edit button for bankroll
            HStack(alignment: .bottom, spacing: 12) {
                Text(viewModel.selectedGraphTab == 0 ? "$\(Int(viewModel.totalBankroll).formattedWithCommas)" :
                        (viewModel.selectedGraphTab == 1 ? "$\(Int(viewModel.filteredSessions.reduce(0){$0+viewModel.adjustedProfit(for: $1)}).formattedWithCommas)" :
                            "$\(Int(viewModel.monthlyProfitCurrent()).formattedWithCommas)"))
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)
                
                // Edit button only for bankroll view
                if viewModel.selectedGraphTab == 0 {
                    Button(action: onAdjustBankroll) {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .medium))
                            Text("Edit")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Material.ultraThinMaterial)
                                    .opacity(0.2)
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.02))
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                            }
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .transition(.scale.combined(with: .opacity))
                }
                
                Spacer()
                
                // Collapse/Expand button for main graphs
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        viewModel.isMainGraphsCollapsed.toggle()
                    }
                }) {
                    Image(systemName: viewModel.isMainGraphsCollapsed ? "chevron.down.circle" : "chevron.up.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .scaleEffect(viewModel.isMainGraphsCollapsed ? 0.9 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isMainGraphsCollapsed)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 4) {
                // Show time range indicator
                let filteredSessions = viewModel.filteredSessionsForTimeRange(viewModel.selectedTimeRange)
                let timeRangeProfit = filteredSessions.reduce(0) { $0 + viewModel.adjustedProfit(for: $1) }
                
                Image(systemName: timeRangeProfit >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 10))
                    .foregroundColor(timeRangeProfit >= 0 ?
                                     Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0)) :
                                        Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0)))
                
                Text("$\(abs(Int(timeRangeProfit)).formattedWithCommas)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(timeRangeProfit >= 0 ?
                                     Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0)) :
                                        Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0)))
                
                Text(viewModel.getTimeRangeLabel(for: viewModel.selectedTimeRange))
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
    }
} 