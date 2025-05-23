import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showingSignIn = false
    @State private var showingSignUp = false
    
    // Animation states
    @State private var logoScale = 0.8
    @State private var logoOpacity = 0.0
    @State private var textOpacity = 0.0
    @State private var buttonsOpacity = 0.0
    
    // Carousel state
    @State private var currentBlurbIndex = 0
    private let blurbs = [
        "Join thousands of poker players discovering and hosting private home games with just a tap.",
        "Join thousands of poker players tracking every session effortlessly.",
        "Join thousands of poker players sharing their best hands and epic moments with your community.",
        "Join thousands of poker players building vibrant game groups and chatting strategy in real time."
    ]
    
    // Timer for auto-rotating blurbs
    let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Just use the default AppBackgroundView
            AppBackgroundView()
            
            VStack {
                Spacer()
                
                // Logo section with animation
                VStack(spacing: 12) {
                    Image("stack_logo")
                        .renderingMode(.template) // Use template rendering mode
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 180)
                        .foregroundColor(.white) // This is the proper way to make the image white
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                    
                    // STACK text under logo - MUCH LARGER
                    Text("STACK")
                        .font(.custom("PlusJakartaSans-Bold", size: 48))
                        .foregroundColor(.white)
                        .opacity(textOpacity)
                }
                .padding(.bottom, 40)
                
                // Main welcome content - Improved carousel
                VStack(spacing: 24) {                    
                    // Enhanced carousel of blurbs - No background
                    // Carousel text
                    Text(blurbs[currentBlurbIndex])
                        .font(.custom("PlusJakartaSans-Medium", size: 17))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .frame(height: 70)
                        .opacity(textOpacity)
                        .id(currentBlurbIndex) // Force view refresh on index change
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    
                    // Improved carousel dots
                    HStack(spacing: 10) {
                        ForEach(0..<blurbs.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentBlurbIndex ? Color.white : Color.white.opacity(0.3))
                                .frame(width: index == currentBlurbIndex ? 10 : 8, height: index == currentBlurbIndex ? 10 : 8)
                                .animation(.spring(), value: currentBlurbIndex)
                        }
                    }
                    .opacity(textOpacity)
                    .padding(.bottom, 30)
                }
                
                Spacer(minLength: 40) // Further reduced to move buttons up
                
                // Simplified buttons
                VStack(spacing: 16) {
                    // Get Started Button - Simpler style
                    Button(action: { showingSignUp = true }) {
                        Text("Get Started")
                            .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                            .cornerRadius(12)
                    }
                    
                    // Sign In Button - Simpler style
                    Button(action: { showingSignIn = true }) {
                        Text("Sign In")
                            .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(buttonsOpacity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                textOpacity = 1.0
            }
            
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                buttonsOpacity = 1.0
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.6)) {
                currentBlurbIndex = (currentBlurbIndex + 1) % blurbs.count
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
    }
}

// Preview provider
struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView()
            .environmentObject(AuthViewModel())
    }
} 