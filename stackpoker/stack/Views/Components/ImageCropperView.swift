import SwiftUI
import UIKit

struct ImageCropperView: View {
    let image: UIImage
    let onCropComplete: (UIImage) -> Void
    let onCancel: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var normalizedImage: UIImage?
    
    private let cropSize: CGFloat = 300
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    // Background
                    Color.black.ignoresSafeArea()
                    
                    // Dimmed overlay
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .ignoresSafeArea()
                    
                    // Image with gestures
                    Image(uiImage: normalizedImage ?? image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                // Pan gesture
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    },
                                
                                // Zoom gesture
                                MagnificationGesture()
                                    .onChanged { value in
                                        let newScale = lastScale * value
                                        scale = max(0.5, min(newScale, 5.0)) // Limit scale between 0.5x and 5x
                                    }
                                    .onEnded { value in
                                        lastScale = scale
                                        // Ensure the scale doesn't go below a reasonable minimum
                                        if scale < 0.8 {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                scale = 1.0
                                                lastScale = 1.0
                                            }
                                        }
                                    }
                            )
                        )
                    
                    // Crop frame overlay
                    VStack {
                        Spacer()
                        
                        ZStack {
                            // Crop frame
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: cropSize, height: cropSize)
                                .background(Color.clear)
                            
                            // Corner guides
                            VStack {
                                HStack {
                                    cornerGuide
                                    Spacer()
                                    cornerGuide
                                }
                                Spacer()
                                HStack {
                                    cornerGuide
                                    Spacer()
                                    cornerGuide
                                }
                            }
                            .frame(width: cropSize, height: cropSize)
                        }
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Crop Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        cropImage()
                    }
                    .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                    .fontWeight(.semibold)
                }
            }
            .preferredColorScheme(.dark)
        }
        .onAppear {
            normalizedImage = normalizeImageOrientation(image)
            setupInitialImagePosition()
        }
    }
    
    private var cornerGuide: some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: 20, height: 2)
            .overlay(
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: 20)
            )
    }
    
    private func setupInitialImagePosition() {
        // Use normalized image size for calculations
        let imageToUse = normalizedImage ?? image
        let imageSize = imageToUse.size
        let imageAspectRatio = imageSize.width / imageSize.height
        
        // Calculate what the displayed size would be when scaledToFit
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height - 200 // Account for navigation and toolbar
        let screenAspectRatio = screenWidth / screenHeight
        
        let displayWidth: CGFloat
        let displayHeight: CGFloat
        
        if imageAspectRatio > screenAspectRatio {
            // Image is wider relative to screen - fit to width
            displayWidth = screenWidth
            displayHeight = screenWidth / imageAspectRatio
        } else {
            // Image is taller relative to screen - fit to height
            displayHeight = screenHeight
            displayWidth = screenHeight * imageAspectRatio
        }
        
        // Calculate scale to make the crop area fit nicely
        let scaleForWidth = cropSize / displayWidth
        let scaleForHeight = cropSize / displayHeight
        scale = max(scaleForWidth, scaleForHeight) * 1.1 // 1.1 gives a bit more room for adjustment
        
        lastScale = scale
        
        // Center the image
        offset = .zero
        lastOffset = .zero
    }
    
    private func cropImage() {
        // Create a normalized image with correct orientation first
        let normalizedImage = normalizeImageOrientation(image)
        
        // Create a graphics context to render the cropped image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: cropSize, height: cropSize))
        
        let croppedImage = renderer.image { context in
            // Use a simpler approach that matches what's displayed
            let imageSize = normalizedImage.size
            let imageAspectRatio = imageSize.width / imageSize.height
            
            // Calculate the displayed size on screen
            let screenWidth = UIScreen.main.bounds.width
            let screenHeight = UIScreen.main.bounds.height - 200 // Account for navigation and toolbar
            
            let displayWidth: CGFloat
            let displayHeight: CGFloat
            
            if imageAspectRatio > screenWidth / screenHeight {
                // Image is wider relative to screen
                displayWidth = screenWidth
                displayHeight = screenWidth / imageAspectRatio
            } else {
                // Image is taller relative to screen
                displayHeight = screenHeight
                displayWidth = screenHeight * imageAspectRatio
            }
            
            // Apply the current scale
            let scaledWidth = displayWidth * scale
            let scaledHeight = displayHeight * scale
            
            // Calculate the crop area in image coordinates
            let imageScale = imageSize.width / scaledWidth
            
            // Center point of the crop area in screen coordinates
            let cropCenterX = screenWidth / 2 - offset.width
            let cropCenterY = screenHeight / 2 - offset.height
            
            // Convert to image coordinates
            let imageCenterX = (cropCenterX - (screenWidth - scaledWidth) / 2) * imageScale
            let imageCenterY = (cropCenterY - (screenHeight - scaledHeight) / 2) * imageScale
            
            // Crop rectangle in image coordinates
            let cropRectSize = cropSize * imageScale
            let cropRect = CGRect(
                x: imageCenterX - cropRectSize / 2,
                y: imageCenterY - cropRectSize / 2,
                width: cropRectSize,
                height: cropRectSize
            )
            
            // Ensure crop rect is within image bounds
            let clampedCropRect = CGRect(
                x: max(0, min(cropRect.minX, imageSize.width - cropRect.width)),
                y: max(0, min(cropRect.minY, imageSize.height - cropRect.height)),
                width: min(cropRect.width, imageSize.width),
                height: min(cropRect.height, imageSize.height)
            )
            
            // Crop and draw
            if let cgImage = normalizedImage.cgImage?.cropping(to: clampedCropRect) {
                let croppedUIImage = UIImage(cgImage: cgImage)
                croppedUIImage.draw(in: CGRect(x: 0, y: 0, width: cropSize, height: cropSize))
            } else {
                // Fallback
                normalizedImage.draw(in: CGRect(x: 0, y: 0, width: cropSize, height: cropSize))
            }
        }
        
        onCropComplete(croppedImage)
    }
    
    private func normalizeImageOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            return image
        }
        
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return normalizedImage ?? image
    }
}

// MARK: - Preview
struct ImageCropperView_Previews: PreviewProvider {
    static var previews: some View {
        ImageCropperView(
            image: UIImage(systemName: "photo") ?? UIImage(),
            onCropComplete: { _ in },
            onCancel: { }
        )
    }
} 