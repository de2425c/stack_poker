import SwiftUI
import FirebaseAuth

struct ToolsScreen: View {
    let userId: String
    @EnvironmentObject private var userService: UserService
    @State private var showProfile = false
    
    // Define fixed grid layout for consistent sizing
    private let columns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                
                VStack(spacing: 0) {
                    // STACK logo at the top
                    Text("STACK")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.top, 32)
                        .padding(.bottom, 24) // Increased spacing here
                    
                    // Tools grid with fixed-size buttons
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 24) {
                            ToolButton(
                                icon: "person.fill",
                                title: "Profile",
                                color: Color(red: 80/255, green: 80/255, blue: 90/255)
                            ) {
                                showProfile = true
                            }
                            
                            ToolButton(
                                icon: "calendar",
                                title: "Calendar",
                                color: Color(red: 70/255, green: 70/255, blue: 80/255)
                            ) {
                                // Will be implemented later
                            }
                            
                            ToolButton(
                                icon: "trophy.fill",
                                title: "Tournaments",
                                color: Color(red: 60/255, green: 60/255, blue: 70/255)
                            ) {
                                // Will be implemented later
                            }
                            
                            ToolButton(
                                icon: "gamecontroller.fill",
                                title: "Custom Games",
                                color: Color(red: 50/255, green: 50/255, blue: 60/255),
                                isPro: true
                            ) {
                                // Will be implemented later
                            }
                            
                            ToolButton(
                                icon: "arrow.down.doc.fill",
                                title: "CSV Import",
                                color: Color(red: 65/255, green: 65/255, blue: 75/255)
                            ) {
                                // Will be implemented later
                            }
                            
                            ToolButton(
                                icon: "gearshape.fill",
                                title: "Settings",
                                color: Color(red: 75/255, green: 75/255, blue: 85/255)
                            ) {
                                // Will be implemented later
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showProfile) {
                ProfileScreen(userId: userId)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct ToolButton: View {
    let icon: String
    let title: String
    let color: Color
    var isPro: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                // Improved icon style with inner shadow and highlight
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 70, height: 70)
                        .shadow(color: Color.black.opacity(0.2), radius: 8, y: 4)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                .blur(radius: 0.5)
                        )
                    
                    // Inner shadow effect
                    Circle()
                        .fill(color)
                        .frame(width: 70, height: 70)
                        .overlay(
                            Circle()
                                .fill(
                                    RadialGradient(
                                        gradient: Gradient(colors: [
                                            color.opacity(0.7),
                                            color
                                        ]),
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 35
                                    )
                                )
                        )
                    
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if isPro {
                        Text("Pro")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.3))
                            )
                    }
                }
            }
            .frame(height: 140) // Fixed height for consistency
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 35/255, green: 37/255, blue: 45/255),
                                Color(red: 28/255, green: 30/255, blue: 38/255)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 5, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.1),
                                        Color.clear
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
} 