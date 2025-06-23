import SwiftUI

/// Circular win-rate gauge reused across multiple analytics screens.
public struct WinRateCard: View {
    let winRate: Double

    public init(winRate: Double) {
        self.winRate = winRate
    }

    public var body: some View {
        // Compute responsive sizing the same way ProfileView did
        let squareSize: CGFloat = (UIScreen.main.bounds.width - 50) / 3
        let dynamicRadius: CGFloat = squareSize * 0.15

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.cyan)
                    .frame(width: 14)
                Text("Win Rate")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
            }

            GeometryReader { proxy in
                let availableSize = min(proxy.size.width, proxy.size.height)
                let wheelSize = availableSize * 0.95
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 8)
                        .frame(width: wheelSize, height: wheelSize)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0,min(winRate,100))) / 100)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.cyan, Color.cyan.opacity(0.6)]),
                                startPoint: .top,
                                endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: wheelSize, height: wheelSize)
                    Text("\(Int(winRate))%")
                        .font(.system(size: min(wheelSize * 0.25, 28), weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(10)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: dynamicRadius)
                    .fill(Material.ultraThinMaterial)
                    .opacity(0.1)
                RoundedRectangle(cornerRadius: dynamicRadius)
                    .fill(Color.white.opacity(0.02))
                RoundedRectangle(cornerRadius: dynamicRadius)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.cyan.opacity(0.3), Color.white.opacity(0.04), Color.clear]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing),
                        lineWidth: 0.75)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: dynamicRadius))
    }
} 