import SwiftUI
import UniformTypeIdentifiers

struct CSVImportPrompt: View {
    let onImportSelected: () -> Void
    let onDismiss: () -> Void
    
    @State private var showingPulse = false
    @State private var offset: CGFloat = 0
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isLoading {
                        onDismiss()
                    }
                }
            
            // Compact popup
            VStack(spacing: 20) {
                // Header with icon
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 64/255, green: 156/255, blue: 255/255),
                                        Color(red: 100/255, green: 180/255, blue: 255/255)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: 6) {
                        Text("Import Your Poker History")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("Import from Pokerbase, Poker Bankroll Tracker, or other poker apps to jumpstart your Stack experience")
                            .font(.system(size: 14))
                            .foregroundColor(.gray.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                }
                
                // Action buttons
                VStack(spacing: 10) {
                    Button(action: {
                        isLoading = true
                        // Small delay to allow UI to update before navigation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onImportSelected()
                        }
                    }) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        } else {
                            HStack(spacing: 10) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 16, weight: .semibold))
                                
                                Text("Import CSV File")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                    }
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 64/255, green: 156/255, blue: 255/255),
                                Color(red: 100/255, green: 180/255, blue: 255/255)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(10)
                    .disabled(isLoading)
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: onDismiss) {
                        Text("Maybe Later")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .disabled(isLoading)
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor(red: 20/255, green: 20/255, blue: 24/255, alpha: 1.0)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 15, y: 8)
            )
            .frame(maxWidth: 340)
            .padding(.horizontal, 32)
            .offset(y: offset)
        }
        .onAppear {
            // Subtle entrance animation
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0)) {
                offset = 0
            }
        }
    }
}

// MARK: - Feature Row Component
private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon container
            ZStack {
                Circle()
                    .fill(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.15)))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
            }
            
            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }
            
            Spacer()
        }
    }
}



// MARK: - Preview
#Preview {
    CSVImportPrompt(
        onImportSelected: { print("Import selected") },
        onDismiss: { print("Dismissed") }
    )
} 
