import SwiftUI

// A completely re-architected luxury share card.
// This version uses a robust, asymmetrical layout to prevent text clipping.
struct FinishedSessionCardView: View {
    // MARK: - Data
    let gameName: String
    let stakes: String
    let date: Date // Retained for potential future use
    let duration: String
    let buyIn: Double
    let cashOut: Double
    let isBackgroundTransparent: Bool

    // MARK: - Derived Properties
    private var profit: Double { cashOut - buyIn }
    private var profitColor: Color { profit < 0 ? .red : .green }
    // This now correctly formats negative profit, e.g., "-$250"
    private var formattedProfit: String {
        let sign = profit < 0 ? "-" : ""
        return "\(sign)$\(Int(abs(profit)))"
    }
    private var formattedBuyIn: String { "$\(Int(buyIn))" }
    private var formattedCashOut: String { "$\(Int(cashOut))" }

    // MARK: - Body
    var body: some View {
        ZStack {
            // Background with a subtle, premium border
            AppBackgroundView()
                .opacity(isBackgroundTransparent ? 0.0 : 1.0)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(isBackgroundTransparent ? 0.0 : 0.12), lineWidth: 1.5)
                )

            GeometryReader { geo in
                // Main content layout, without the logo
                VStack(alignment: .leading, spacing: 0) {
                    
                    // Top Section: Game Title & Net Profit
                    HStack(alignment: .top, spacing: 0) {
                        // Title block with wrapping text
                        VStack(alignment: .leading, spacing: 4) {
                            Text(gameName.uppercased())
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundColor(.white)
                                .lineLimit(3)
                                .minimumScaleFactor(0.8)
                            
                            Text(stakes)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white.opacity(0.75))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer(minLength: 16)

                        // Profit display with a dedicated width to prevent clipping
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("NET")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                                .tracking(1)
                            Text(formattedProfit)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(profitColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(width: geo.size.width * 0.25) // Reduced to push PNL further right
                    }

                    Spacer()

                    // Bottom Metrics Row - logo is now separate
                    HStack(spacing: 24) {
                        MetricView(label: "BUY-IN", value: formattedBuyIn)
                        MetricView(label: "CASHOUT", value: formattedCashOut)
                        MetricView(label: "TIME", value: duration.uppercased())
                        Spacer() // Pushes metrics to the left
                    }
                }
                .padding(24)
            }
            
            // Logo overlay, positioned with hardcoded padding for reliability
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image("promo_logo")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(.white.opacity(0.9))
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 70, height: 70)
                }
            }
            .padding(.bottom, 1) // Nudge up from the bottom
            .padding(.trailing, 30) // Nudge in from the right
        }
        .frame(width: 350, height: 220) // A beautiful, balanced rectangle
    }
}

// MARK: - Reusable Metric View
private struct MetricView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.55))
                .tracking(0.8)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        FinishedSessionCardView(
            gameName: "Wynn",
            stakes: "$2/$5 No-Limit Hold'em",
            date: Date(),
            duration: "4H 15M",
            buyIn: 500,
            cashOut: 1280,
            isBackgroundTransparent: false
        )
        FinishedSessionCardView(
            gameName: "No-Limit Hold'em Tournament",
            stakes: "$3000 Guaranteed",
            date: Date(),
            duration: "2H 30M",
            buyIn: 250,
            cashOut: 0, // This will now show "-$250"
            isBackgroundTransparent: false
        )
        FinishedSessionCardView(
            gameName: "NLH Tournament",
            stakes: "$250 Buy-in NLH",
            date: Date(),
            duration: "4H 15M",
            buyIn: 500,
            cashOut: 250, // Example of a loss
            isBackgroundTransparent: true
        )
    }
    .padding()
    .background(Color.black)
}
