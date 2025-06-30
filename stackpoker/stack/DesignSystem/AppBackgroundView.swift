import SwiftUI

struct AppBackgroundView: View {

    // ───── Your original enum preserved ─────
    enum Edges {
        case all, top, bottom,
             horizontal, vertical,
             leading, trailing, none
    }
    let edges: Edges
    init(edges: Edges = .all) { self.edges = edges }

    // Helper to convert the old enum → Edge.Set
    private var edgeSet: Edge.Set {
        switch edges {
        case .all:         return .all
        case .top:         return .top
        case .bottom:      return .bottom
        case .horizontal:  return [.leading, .trailing]
        case .vertical:    return [.top, .bottom]
        case .leading:     return .leading
        case .trailing:    return .trailing
        case .none:        return []
        }
    }

    // ───── Body ─────
    var body: some View {
        GeometryReader { geo in
            if geo.size.width > 430 {
                // ---------- iPad compatibility window (wider than any iPhone) ----------
                // Stretch to fill the full window so there are NO inner black bars.
                Image("background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width,
                           height: geo.size.height)
                    .clipped()                          // trim overflow
                    .ignoresSafeArea(edges: edgeSet)    // run under notch / home bar
            } else {
                // ---------- Real iPhone (≤ 430 pt) ----------
                // IDENTICAL to your original implementation.
                Image("background")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea(edges: edgeSet)
            }
        }
        // No extra ZStack needed; GeometryReader is already a full-screen container.
    }
}
