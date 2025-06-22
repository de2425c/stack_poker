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
        ("promo_feed", "Share your biggest wins and hands"),
        ("promo_logging", "Intuitive session logging"),
        ("promo_events", "Create and join events"),
        ("promo_analytics", "Advanced analytics")
    ]
    
    // Timer for auto-rotating features - 6 seconds
    let timer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppBackgroundView()
                
                // Bottom section background overlay - always covers bottom area completely
                VStack {
                    Spacer()
                    
                    // Rich dark blue background - extends to very bottom with no gaps
                    Rectangle()
                        .fill(Color(red: 20/255, green: 30/255, blue: 50/255))
                        .frame(height: geometry.size.height * 0.45) // Cover bottom 45% of screen
                        .edgesIgnoringSafeArea(.bottom) // Ensure it goes to absolute bottom
                        .opacity(buttonsOpacity)
                }
                .edgesIgnoringSafeArea(.bottom) // Make sure VStack extends to bottom
                
                VStack(spacing: 10) {
                    // Top content area - constrained to never overlap buttons
                    VStack(spacing: 5) {
                        // Stack logo at very top
                        Image("promo_logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: min(geometry.size.width * 0.8, 280), height: min(geometry.size.width * 0.6, 210))
                            .scaleEffect(logoScale)
                            .opacity(logoOpacity)
                            .padding(.top, max(10, geometry.safeAreaInsets.top + 5)) // Much higher
                        
                        // Feature carousel - bigger image, moved UP away from buttons
                        VStack(spacing: 5) {
                            // Feature image - bigger and moved up
                            Image(features[currentFeatureIndex].image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(
                                    width: geometry.size.width - 15, // Even wider
                                    height: min(geometry.size.height * 0.48, 420) // Even bigger - 48% of screen height
                                )
                                .opacity(carouselOpacity)
                                .id(currentFeatureIndex)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                            
                            // Feature description
                            Text(features[currentFeatureIndex].description)
                                .font(.custom("PlusJakartaSans-Medium", size: 18))
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .opacity(carouselOpacity)
                                .padding(.horizontal, 30)
                                .lineLimit(2)
                            
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
                        }
                        .padding(.bottom, 40) // Add padding between carousel and buttons
                    }
                    .frame(maxHeight: geometry.size.height * 0.65) // Content area
                    
                    Spacer(minLength: 180) // Much more spacing to push image UP away from buttons
                }
                
                // Fixed buttons at bottom
                VStack {
                    Spacer()
                    
                    VStack(spacing: 16) {
                        // Email Sign Up Button
                        Button(action: { showingSignUp = true }) {
                            HStack {
                                Image(systemName: "envelope")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.black)
                                Text("Sign Up with Email")
                                    .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                    .foregroundColor(.black)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                            .cornerRadius(12)
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
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(12)
                        }
                        
                        // Sign In Button
                        Button(action: { showingSignIn = true }) {
                            Text("Already have an account? Sign In")
                                .font(.custom("PlusJakartaSans-Medium", size: 16))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, max(5, geometry.safeAreaInsets.bottom - 55)) // Much closer to bottom
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
    }
}

// Preview provider
struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView()
            .environmentObject(AuthViewModel())
    }
} 
