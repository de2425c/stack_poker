import SwiftUI
import PhotosUI

struct AddMenuOverlay: View {
    @Binding var showingMenu: Bool
    let userId: String
    @Binding var showSessionForm: Bool
    @Binding var showingLiveSession: Bool
    @Binding var showingOpenHomeGameFlow: Bool
    @ObservedObject var tutorialManager: TutorialManager

    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var showPostCreationView = false
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showingMenu = false }
                }

            // Menu items in a VStack
            VStack(spacing: 20) {
                menuButton(title: "New Session", systemImage: "play.circle.fill", action: {
                    if tutorialManager.shouldShow(tutorial: .startFirstSession) {
                        tutorialManager.currentTutorial = .startFirstSession
                        tutorialManager.highlightAddMenuButton = false // Turn off menu highlight
                    }
                    showSessionForm = true
                    showingMenu = false
                })
                .id("addMenu-newSessionButton")
                
                menuButton(title: "New Post", systemImage: "plus.square.fill", action: {
                    showingImagePicker = true
                })
                
                menuButton(title: "New Home Game", systemImage: "house.fill", action: {
                    showingOpenHomeGameFlow = true
                    showingMenu = false
                })
            }
            .padding(30)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .shadow(radius: 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .fullScreenCover(isPresented: $showingImagePicker) {
            // After the picker is dismissed, check if an image was selected
            if let selectedImage = selectedImage {
                // We have an image, now show the post creation view
                showPostCreationView = true
            }
        } content: {
            ImagePicker(selectedImage: $selectedImage)
        }
        .fullScreenCover(isPresented: $showPostCreationView) {
            // This is presented after an image is chosen from the picker
            if let imageToPost = selectedImage {
                PostCreationView(
                    isPresented: $showPostCreationView,
                    selectedImage: imageToPost,
                    userId: userId,
                    postService: PostService()
                )
            }
        }
    }

    private func menuButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation {
                action()
            }
        }) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title)
                Text(title)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()
            .foregroundColor(.white)
            .background(Color.white.opacity(0.1))
            .cornerRadius(15)
        }
    }
} 