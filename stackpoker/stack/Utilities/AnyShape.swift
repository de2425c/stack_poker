import SwiftUI

struct AnyShape: Shape {
    private let makePath: (CGRect) -> Path
    
    init<S: Shape>(_ shape: S) {
        makePath = { rect in
            shape.path(in: rect)
        }
    }
    
    func path(in rect: CGRect) -> Path {
        makePath(rect)
    }
}