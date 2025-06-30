import SwiftUI

struct GlassyInputField<Content: View>: View {
    let icon: String
    let title: String
    var glassOpacity: Double
    var labelColor: Color
    var materialOpacity: Double
    @ViewBuilder let content: () -> Content
    
    init(icon: String, title: String, glassOpacity: Double = 0.01, labelColor: Color = Color(white: 0.4), materialOpacity: Double = 0.2, @ViewBuilder content: @escaping () -> Content) {
        self.icon = icon
        self.title = title
        self.glassOpacity = glassOpacity
        self.labelColor = labelColor
        self.materialOpacity = materialOpacity
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14)) // System font for icon
                    .foregroundColor(labelColor)
                Text(title)
                    .font(.plusJakarta(.caption, weight: .medium))
                    .foregroundColor(labelColor)
            }
            
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                // Ultra-transparent glass effect
                RoundedRectangle(cornerRadius: 16)
                    .fill(Material.ultraThinMaterial)
                    .opacity(materialOpacity)
                
                // Almost invisible white overlay
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(glassOpacity))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}