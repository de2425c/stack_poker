import SwiftUI

struct AppBackgroundView: View {
    enum Edges {
        case all
        case top
        case bottom
        case horizontal
        case vertical
        case leading
        case trailing
        case none
    }
    
    let edges: Edges
    
    init(edges: Edges = .all) {
        self.edges = edges
    }
    
    var body: some View {
        ZStack {
            // Rich dark gradient base with deep blues and subtle accent
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 12/255, green: 12/255, blue: 20/255),
                    Color(red: 18/255, green: 20/255, blue: 28/255),
                    Color(red: 16/255, green: 22/255, blue: 32/255)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Noise-like texture effect using overlapping dots
            NoiseOverlayView()
                .blendMode(.overlay)
                .opacity(0.015)
                .allowsHitTesting(false)
                .ignoresSafeArea()
            
            // Soft highlight gradient at the top
            VStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.07),
                        Color.white.opacity(0.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                Spacer()
            }
            .ignoresSafeArea()
            
            // Optional accent glow in bottom corner
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Circle()
                        .fill(Color(red: 123/255, green: 255/255, blue: 99/255, opacity: 0.05))
                        .frame(width: 150, height: 150)
                        .blur(radius: 70)
                        .offset(x: 50, y: 50)
                }
            }
            .ignoresSafeArea()
        }
    }
}

// A view that creates a subtle noise-like texture pattern
struct NoiseOverlayView: View {
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // Draw many tiny dots with random opacity to simulate noise
                for _ in 0..<3000 {
                    let x = CGFloat.random(in: 0..<size.width)
                    let y = CGFloat.random(in: 0..<size.height)
                    let opacity = Double.random(in: 0.1...0.9)
                    
                    context.opacity = opacity
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: x,
                            y: y,
                            width: 1,
                            height: 1
                        )),
                        with: .color(.white)
                    )
                }
            }
        }
    }
}
    

#Preview {
    AppBackgroundView()
} 
