import SwiftUI

struct AppBackgroundView: View {
    
    enum Edges { case all, top, bottom, horizontal, vertical, leading, trailing, none }
    let edges: Edges
    
    init(edges: Edges = .all) { self.edges = edges }

    var body: some View {
        GeometryReader { geo in
                    let isPadCompatibility = geo.size.width > 430   // 390-pt window is fine,
                                                                    // Stage-Manager widths still ≤ 430
                    if isPadCompatibility {
                        StretchyBackground()
                    } else {
                        LegacyBackground()
                    }
                }
        // If you need edge selection, apply it to both versions:
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

//  New stretchy version – works nicely on iPad
struct StretchyBackground: View {
    var body: some View {
        GeometryReader { geo in
            Image("background")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width,
                       height: geo.size.height)
                .clipped()
                .ignoresSafeArea()
        }
    }
}

//  Original version you liked on iPhone
struct LegacyBackground: View {
    var body: some View {
        Image("background")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .ignoresSafeArea()
    }
}

