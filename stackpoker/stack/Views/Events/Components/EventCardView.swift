import SwiftUI

struct EventCardView: View {
    let event: Event
    var onSelect: (() -> Void)?

    // Define app's accent color for reuse
    private let accentColor = Color(red: 64/255, green: 156/255, blue: 255/255)

    var body: some View {
        Button(action: { onSelect?() }) {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Header Section (Event Name & Series)
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.event_name)
                        .font(.system(size: 18, weight: .bold, design: .default))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    
                    if let seriesName = event.series_name, !seriesName.isEmpty {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                            Text(seriesName)
                                .font(.system(size: 12, weight: .medium, design: .default))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // MARK: - Info Section (Date, Time, Description) - Condensed
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 16)
                        Text(event.simpleDate.displayMedium)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        
                        if let time = event.time, !time.isEmpty {
                            Text("•")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.white)
                            Image(systemName: "clock.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            Text(time)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 14)

                // MARK: - Footer Section (Buy-in & Action Chevron) - Compressed
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BUY-IN")
                            .font(.system(size: 9, weight: .bold, design: .default))
                            .foregroundColor(.white)
                        Text(event.buyin_string)
                            .font(.system(size: 20, weight: .bold, design: .default))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
                .padding(.top, 6)
            }
            .frame(minHeight: 130) // Significantly reduced from 190
            .background(
                ZStack {
                    // Base card with rich black and subtle deep blue hint
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color(red: 8/255, green: 12/255, blue: 20/255).opacity(0.9), location: 0.0),
                                    .init(color: Color(red: 12/255, green: 16/255, blue: 28/255).opacity(0.7), location: 0.3),
                                    .init(color: Color(red: 16/255, green: 20/255, blue: 32/255).opacity(0.5), location: 0.6),
                                    .init(color: Color(red: 20/255, green: 24/255, blue: 36/255).opacity(0.4), location: 1.0)
                                ]),
                                startPoint: .center,
                                endPoint: .bottomTrailing
                            )
                        )
                        
                    // Large flowing gradient overlay
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            RadialGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.12), location: 0.0),
                                    .init(color: Color.white.opacity(0.06), location: 0.4),
                                    .init(color: Color.white.opacity(0.02), location: 0.7),
                                    .init(color: Color.clear, location: 1.0)
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                        
                    // Secondary gradient for depth
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.05), location: 0.0),
                                    .init(color: Color.clear, location: 0.4),
                                    .init(color: Color(red: 100/255, green: 180/255, blue: 255/255).opacity(0.02), location: 1.0)
                                ]),
                                startPoint: .center,
                                endPoint: .bottomTrailing
                            )
                        )
                        
                    // Enhanced border gradient
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.25), location: 0.0),
                                    .init(color: Color.white.opacity(0.12), location: 0.3),
                                    .init(color: Color.white.opacity(0.06), location: 0.6),
                                    .init(color: Color.white.opacity(0.02), location: 1.0)
                                ]),
                                startPoint: .center,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
            
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Helper for UIBlurEffect
struct VisualEffectView: UIViewRepresentable {
    var effect: UIVisualEffect?
    func makeUIView(context: UIViewRepresentableContext<Self>) -> UIVisualEffectView { UIVisualEffectView() }
    func updateUIView(_ uiView: UIVisualEffectView, context: UIViewRepresentableContext<Self>) { uiView.effect = effect }
} 