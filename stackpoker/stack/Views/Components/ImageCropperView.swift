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
                    Image(uiImage: image)
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
                                    .onEnded { _ in
                                        lastScale = scale
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
        // Calculate initial scale to fit the image within the crop area
        let imageSize = image.size
        let imageAspectRatio = imageSize.width / imageSize.height
        
        if imageAspectRatio > 1 {
            // Landscape image - scale based on height
            scale = cropSize / imageSize.height
        } else {
            // Portrait or square image - scale based on width
            scale = cropSize / imageSize.width
        }
        
        lastScale = scale
        
        // Center the image
        offset = .zero
        lastOffset = .zero
    }
    
    private func cropImage() {
        // Create a graphics context to render the cropped image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: cropSize, height: cropSize))
        
        let croppedImage = renderer.image { context in
            // Calculate the image's actual displayed size and position
            let imageSize = image.size
            let displaySize = CGSize(
                width: imageSize.width * scale,
                height: imageSize.height * scale
            )
            
            // Calculate the crop rectangle in the image's coordinate system
            let cropRect = CGRect(
                x: (displaySize.width - cropSize) / 2 - offset.width,
                y: (displaySize.height - cropSize) / 2 - offset.height,
                width: cropSize,
                height: cropSize
            )
            
            // Draw the image scaled and positioned
            let drawRect = CGRect(
                x: -cropRect.minX,
                y: -cropRect.minY,
                width: displaySize.width,
                height: displaySize.height
            )
            
            image.draw(in: drawRect)
        }
        
        onCropComplete(croppedImage)
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