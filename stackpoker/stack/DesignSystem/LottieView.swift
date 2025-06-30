import SwiftUI
import Lottie // Ensure Lottie is imported

struct LottieView: UIViewRepresentable {
    var name: String
    var loopMode: LottieLoopMode = .playOnce
    var animationSpeed: CGFloat = 1.0
    var contentMode: UIView.ContentMode = .scaleAspectFit
    @Binding var play: Bool

    // No need to create it here, will be created in makeUIView
    // let animationView = LottieAnimationView()

    func makeUIView(context: UIViewRepresentableContext<LottieView>) -> UIView {
        let view = UIView(frame: .zero)
        
        let animationView = LottieAnimationView()
        animationView.animation = LottieAnimation.named(name)
        animationView.contentMode = contentMode
        animationView.loopMode = loopMode
        animationView.animationSpeed = animationSpeed
        
        // Set the LottieAnimationView's background to clear
        animationView.backgroundColor = .clear
        // Make the containing UIView also clear
        view.backgroundColor = .clear 
        // Ensure the LottieAnimationView itself is opaque = false for transparency if the animation supports it
        animationView.isOpaque = false
        
        view.addSubview(animationView)
        
        animationView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            animationView.heightAnchor.constraint(equalTo: view.heightAnchor),
            animationView.widthAnchor.constraint(equalTo: view.widthAnchor)
        ])
        
        context.coordinator.animationView = animationView
        // Play if the binding is true when the view is made
        if play {
             animationView.play()
        }
        
        return view
    }

    func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<LottieView>) {
        guard let animationView = context.coordinator.animationView else { return }
        
        if play {
            if !animationView.isAnimationPlaying {
                animationView.play { (finished) in
                    if loopMode == .playOnce && finished {
                        self.play = false 
                    }
                }
            }
        } else {
            animationView.stop()
        }
    }
    
    // Coordinator to hold the animationView instance
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: LottieView
        var animationView: LottieAnimationView? // Store the animation view

        init(_ parent: LottieView) {
            self.parent = parent
        }
    }
}

// Optional: Preview Provider for SwiftUI Canvas
#if DEBUG
struct LottieView_Previews: PreviewProvider {
    static var previews: some View {
        LottieView(name: "lottie_white", loopMode: .loop, play: .constant(true))
            .frame(width: 200, height: 200)
            .background(Color.blue) // Example background to test transparency
    }
}
#endif 