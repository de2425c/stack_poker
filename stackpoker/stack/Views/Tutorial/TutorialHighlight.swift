import SwiftUI

// MARK: - Tutorial Highlight Modifier
struct TutorialHighlight: ViewModifier {
    let isHighlighted: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 64/255, green: 156/255, blue: 255/255), // #409CFF
                                Color(red: 100/255, green: 180/255, blue: 255/255) // #64B4FF
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: isHighlighted ? 3 : 0
                    )
                    .shadow(
                        color: isHighlighted ? Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.5) : Color.clear,
                        radius: isHighlighted ? 8 : 0
                    )
                    .animation(.easeInOut(duration: 0.3), value: isHighlighted)
            )
            .scaleEffect(isHighlighted ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: isHighlighted)
    }
}

// MARK: - Tab Button Highlight Modifier
struct TutorialTabHighlight: ViewModifier {
    let isHighlighted: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.8),
                                Color.white.opacity(0.6)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isHighlighted ? 2 : 0
                    )
                    .shadow(
                        color: isHighlighted ? Color.white.opacity(0.6) : Color.clear,
                        radius: isHighlighted ? 12 : 0
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isHighlighted)
            )
            .scaleEffect(isHighlighted ? 1.05 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isHighlighted)
    }
}

// MARK: - Plus Button Highlight Modifier
struct TutorialPlusHighlight: ViewModifier {
    let isHighlighted: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.8),
                                Color.white.opacity(0.6)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isHighlighted ? 3 : 0
                    )
                    .shadow(
                        color: isHighlighted ? Color.white.opacity(0.6) : Color.clear,
                        radius: isHighlighted ? 15 : 0
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isHighlighted)
            )
            .scaleEffect(isHighlighted ? 1.08 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isHighlighted)
    }
}

// MARK: - Menu Item Highlight Modifier
struct TutorialMenuHighlight: ViewModifier {
    let isHighlighted: Bool
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isHighlighted ? 
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.2), // #409CFF
                                Color(red: 100/255, green: 180/255, blue: 255/255).opacity(0.2) // #64B4FF
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ) :
                        LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 64/255, green: 156/255, blue: 255/255), // #409CFF
                                        Color(red: 100/255, green: 180/255, blue: 255/255) // #64B4FF
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: isHighlighted ? 2 : 0
                            )
                    )
                    .animation(.easeInOut(duration: 0.3), value: isHighlighted)
            )
            .scaleEffect(isHighlighted ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: isHighlighted)
    }
}

// MARK: - View Extensions
extension View {
    func tutorialHighlight(isHighlighted: Bool) -> some View {
        self.modifier(TutorialHighlight(isHighlighted: isHighlighted))
    }
    
    func tutorialTabHighlight(isHighlighted: Bool) -> some View {
        self.modifier(TutorialTabHighlight(isHighlighted: isHighlighted))
    }
    
    func tutorialPlusHighlight(isHighlighted: Bool) -> some View {
        self.modifier(TutorialPlusHighlight(isHighlighted: isHighlighted))
    }
    
    func tutorialMenuHighlight(isHighlighted: Bool) -> some View {
        self.modifier(TutorialMenuHighlight(isHighlighted: isHighlighted))
    }
} 