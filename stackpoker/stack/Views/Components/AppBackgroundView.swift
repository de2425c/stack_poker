//import SwiftUI
//
//struct AppBackgroundView: View {
//    
//    enum Edges {
//        case all
//        case top
//        case bottom
//        case horizontal
//        case vertical
//        case leading
//        case trailing
//        case none
//    }
//    
//    let edges: Edges
//    
//    init(edges: Edges = .all) {
//        self.edges = edges
//    }
//    
//    var body: some View {
//        // Simple dark grayish background for a clean dark mode look
//        Color(hex: "#121418") // Dark gray with slight blue tint
//            .edgesIgnoringSafeArea(getEdges())
//    }
//    
//    private func getEdges() -> Edge.Set {
//        switch edges {
//        case .all:
//            return .all
//        case .top:
//            return .top
//        case .bottom:
//            return .bottom
//        case .horizontal:
//            return [.leading, .trailing]
//        case .vertical:
//            return [.top, .bottom]
//        case .leading:
//            return .leading
//        case .trailing:
//            return .trailing
//        case .none:
//            return []
//        }
//    }
//}
//
//struct AppBackgroundView_Previews: PreviewProvider {
//    static var previews: some View {
//        AppBackgroundView()
//    }
//}

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
            // Always use the "background" image
            Image("background")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .edgesIgnoringSafeArea(getEdges())
        }
        .edgesIgnoringSafeArea(getEdges())
    }
    
    private func getEdges() -> Edge.Set {
        switch edges {
        case .all:
            return .all
        case .top:
            return .top
        case .bottom:
            return .bottom
        case .horizontal:
            return [.leading, .trailing]
        case .vertical:
            return [.top, .bottom]
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        case .none:
            return []
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
