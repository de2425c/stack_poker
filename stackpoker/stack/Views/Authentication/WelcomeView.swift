import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showingSignIn = false
    @State private var showingSignUp = false
    @State private var showingPhoneSignUp = false
    
    // Animation states
    @State private var logoScale = 0.8
    @State private var logoOpacity = 0.0
    @State private var buttonsOpacity = 0.0
    @State private var carouselOpacity = 0.0
    
    // Carousel state
    @State private var currentFeatureIndex = 0
    private let features: [(image: String, description: String)] = [
        ("promo_events", "Create and join events"),
        ("promo_feed", "Share your biggest wins and hands"),
        ("promo_logging", "Intuitive session logging")
    ]
    
    // Timer for auto-rotating features - 6 seconds
    let timer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea(.all) // Ensure background covers everything
                
                VStack(spacing: 0) {
                    // Top section with heading text
                    VStack(spacing: 20) {
                        Spacer()
                            .frame(height: geometry.safeAreaInsets.top + 20)
                        
                        // Stack logo
                        Image("promo_logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: min(geometry.size.width * 0.7, 300))
                            .frame(height: 60)
                            .scaleEffect(logoScale)
                            .opacity(logoOpacity)
                    }
                    
                    Spacer()
                        .frame(maxHeight: 40)
                    
                    // Middle section with carousel
                    VStack(spacing: 8) {
                        // Feature image with border and gradient background
                        ZStack {
                            // More pronounced gradient background behind image
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.6), // Stronger blue center
                                    Color(red: 100/255, green: 180/255, blue: 255/255).opacity(0.4), // More visible blue
                                    Color(red: 30/255, green: 80/255, blue: 150/255).opacity(0.2), // Darker blue ring
                                    Color.clear // Transparent edges
                                ]),
                                center: .center,
                                startRadius: 30,
                                endRadius: 250
                            )
                            .frame(width: geometry.size.width * 0.95, height: min(geometry.size.height * 0.6, 450))
                            .opacity(carouselOpacity)
                            
                            // Phone with squircle shape and metallic border
                            ZStack {
                                // Main phone body with squircle shape
                                Image(features[currentFeatureIndex].image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: max(geometry.size.height * 0.5, 380))
                                    .clipShape(RoundedRectangle(cornerRadius: 30)) // Sharper squircle corners
                                    .overlay(
                                        // Metallic border with multiple layers for realism
                                        RoundedRectangle(cornerRadius: 30)
                                            .strokeBorder(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        Color(red: 0.05, green: 0.05, blue: 0.05), // Very dark
                                                        Color(red: 0.15, green: 0.15, blue: 0.15), // Dark metallic
                                                        Color(red: 0.35, green: 0.35, blue: 0.35), // Metallic highlight
                                                        Color(red: 0.08, green: 0.08, blue: 0.08), // Dark shadow
                                                        Color.black // Pure black edge
                                                    ]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 6
                                            )
                                    )
                                    .overlay(
                                        // Inner metallic shine
                                        RoundedRectangle(cornerRadius: 30)
                                            .strokeBorder(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        Color.white.opacity(0.1),
                                                        Color.clear,
                                                        Color.clear,
                                                        Color.white.opacity(0.05)
                                                    ]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                                    .opacity(carouselOpacity)
                                    .id(currentFeatureIndex)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)
                                    ))
                                    .shadow(color: Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.3), radius: 25, x: 0, y: 15)
                                
                                // Side button (power button)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 0.1, green: 0.1, blue: 0.1),
                                                Color(red: 0.25, green: 0.25, blue: 0.25),
                                                Color(red: 0.05, green: 0.05, blue: 0.05)
                                            ]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: 4, height: 30)
                                    .offset(x: max(geometry.size.width * 0.25, 190), y: -40) // Position on right side
                                    .opacity(carouselOpacity)
                            }
                        }
                        
                        // Carousel dots
                        HStack(spacing: 8) {
                            ForEach(0..<features.count, id: \.self) { index in
                                Circle()
                                    .fill(index == currentFeatureIndex ? Color.white : Color.white.opacity(0.3))
                                    .frame(width: index == currentFeatureIndex ? 10 : 8, 
                                           height: index == currentFeatureIndex ? 10 : 8)
                                    .animation(.spring(response: 0.3), value: currentFeatureIndex)
                            }
                        }
                        .opacity(carouselOpacity)
                        .padding(.top, 16)
                    }
                    
                    Spacer()
                        .frame(maxHeight: 30) // Reduced from 40
                    
                    // Bottom section with buttons - always at bottom
                    VStack() {
                        // Email Sign Up Button with blue gradient
                        Button(action: { showingSignUp = true }) {
                            HStack {
                                Image(systemName: "envelope")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Sign Up with Email")
                                    .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 64/255, green: 156/255, blue: 255/255), // #409CFF
                                        Color(red: 100/255, green: 180/255, blue: 255/255) // #64B4FF
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(28)
                        }
                        
                        // Phone Sign Up Button
                        Button(action: { showingPhoneSignUp = true }) {
                            HStack {
                                Image(systemName: "phone")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Sign Up with Phone")
                                    .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.15),
                                        Color.white.opacity(0.25)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(28)
                        }
                        
                        // Sign In Button
                        Button(action: { showingSignIn = true }) {
                            Text("Already have an account? Sign In")
                                .font(.custom("PlusJakartaSans-Medium", size: 16))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 38)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom + 20, 20)) // Ensure minimum padding
                    .opacity(buttonsOpacity)
                }
            }
        }
        .onAppear {
            // Staggered animation entrance
            withAnimation(.easeOut(duration: 0.6)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                carouselOpacity = 1.0
            }
            
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                buttonsOpacity = 1.0
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentFeatureIndex = (currentFeatureIndex + 1) % features.count
            }
        }
        .sheet(isPresented: $showingSignIn) {
            SignInView()
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showingSignUp) {
            SignUpView()
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showingPhoneSignUp) {
            PhoneSignUpView()
                .environmentObject(authViewModel)
        }
        .ignoresSafeArea(.all) // Ensure the entire view ignores safe areas
    }
}

// Preview provider
struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView()
            .environmentObject(AuthViewModel())
    }
} 
