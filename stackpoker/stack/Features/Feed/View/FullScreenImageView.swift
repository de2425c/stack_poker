import SwiftUI
import Kingfisher

// Full Screen Image View
struct FullScreenImageView: View {
    let imageURL: String
    let onDismiss: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    
    // State to defer loading of image content
    @State private var showImageContent = false

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            if showImageContent {
                if let url = URL(string: imageURL) {
                    KFImage(url)
                        .resizable()
                        .placeholder {
                            // This placeholder will be shown by KFImage while it loads
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                        }
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, 1), 5)
                                }
                                .onEnded { _ in lastScale = 1.0 }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    if scale > 1 {
                                        offset = CGSize(
                                            width: lastOffset.width + gesture.translation.width,
                                            height: lastOffset.height + gesture.translation.height
                                        )
                                    }
                                }
                                .onEnded { _ in if scale > 1 { lastOffset = offset } }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                if scale > 1 {
                                    scale = 1
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2
                                }
                            }
                        }
                        .onTapGesture(count: 1) {
                            if scale <= 1.05 { onDismiss() }
                        }
                } else {
                    Text("Invalid image URL")
                        .foregroundColor(.white)
                }
            } else {
                // Initial placeholder before attempting to load image content
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            }

            // Close button remains visible
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(12)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 16)
                    .padding(.top)
                }
                Spacer()
            }
        }
        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            // Using DispatchQueue.main.asyncAfter to ensure the modal presentation animation completes
            // before we switch in the potentially heavy image content.
            // A small delay like 0.1 seconds can often be enough.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !self.showImageContent { // Ensure we only set it if not already set (e.g. view reappears)
                    self.showImageContent = true
                }
            }
        }
    }
}

// Helper to get safe area insets, if needed by other views using this component.
extension UIApplication {
    var firstWindow: UIWindow? {
        return UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .first(where: { $0 is UIWindowScene })
            .flatMap({ $0 as? UIWindowScene })?.windows
            .first(where: \.isKeyWindow)
    }
} 