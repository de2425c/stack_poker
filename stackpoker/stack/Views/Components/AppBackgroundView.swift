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
            // Dark gradient background with blueish tint
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(UIColor(red: 18/255, green: 18/255, blue: 22/255, alpha: 1.0)),
                    Color(UIColor(red: 22/255, green: 26/255, blue: 35/255, alpha: 1.0))
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}
    

#Preview {
    AppBackgroundView()
} 
