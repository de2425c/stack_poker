import SwiftUI

// New NoteCardView for displaying notes with better UI
struct NoteCardView: View {
    let noteText: String
    var onShareTapped: (() -> Void)? = nil
    
    // Attempt to get the current time for display, though this won't persist or update
    // For real timestamping, the note model itself would need a Date property.
    private var currentTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image("stack_logo") // Assuming you have a 'stack_logo' image in your assets
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .colorInvert() // Makes the logo white if it's black, or vice-versa
                .padding(8)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(noteText)
                    .font(.plusJakarta(.body, weight: .regular))
                    .foregroundColor(.white)
                    .lineLimit(3) // Limit lines for preview, full text in editor
                
                Text("Added around \(currentTime)") // Display a pseudo-timestamp
                    .font(.plusJakarta(.caption2, weight: .medium))
                    .foregroundColor(.gray)
            }
            
            Spacer() // Pushes content to the left
            
            // Share button on the right side
            if let onShareTapped = onShareTapped {
                Button(action: onShareTapped) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Material.ultraThinMaterial)
                    .opacity(0.2)
                
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.01))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}