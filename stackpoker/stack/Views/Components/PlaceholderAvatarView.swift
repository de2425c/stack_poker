import SwiftUI

struct PlaceholderAvatarView: View {
    let size: CGFloat
    var iconSize: CGFloat? = nil
    var backgroundColor: Color? = nil
    var iconColor: Color? = nil
    var strokeColor: Color? = nil
    var strokeWidth: CGFloat = 1
    
    private var computedIconSize: CGFloat {
        iconSize ?? (size * 0.4)
    }
    
    private var computedBackgroundColor: Color {
        backgroundColor ?? Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0))
    }
    
    private var computedIconColor: Color {
        iconColor ?? Color.gray.opacity(0.7)
    }
    
    private var computedStrokeColor: Color {
        strokeColor ?? Color.white.opacity(0.1)
    }
    
    var body: some View {
        Circle()
            .fill(computedBackgroundColor)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: computedIconSize))
                    .foregroundColor(computedIconColor)
            )
            .overlay(
                Circle()
                    .stroke(computedStrokeColor, lineWidth: strokeWidth)
            )
    }
}

#Preview {
    VStack(spacing: 20) {
        PlaceholderAvatarView(size: 80)
        PlaceholderAvatarView(size: 50)
        PlaceholderAvatarView(size: 36)
        PlaceholderAvatarView(size: 32)
    }
    .padding()
    .background(Color.black)
} 