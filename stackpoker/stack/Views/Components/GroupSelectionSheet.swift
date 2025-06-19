import SwiftUI
import FirebaseAuth

struct GroupSelectionSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var groupService = GroupService()
    let noteText: String
    let onGroupSelected: (UserGroup) -> Void
    
    @State private var isLoading = false
    @State private var error: String?
    @State private var showError = false
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if groupService.isLoading && groupService.userGroups.isEmpty {
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            
                            Text("Loading groups...")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if groupService.userGroups.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "person.2")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            
                            Text("No Groups Found")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Text("Create a group first to share notes")
                                .font(.system(size: 15))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(groupService.userGroups) { group in
                                    GroupSelectionRow(group: group) {
                                        shareToGroup(group)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }
                    }
                }
            }
            .navigationTitle("Share to Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .task {
            await loadGroups()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(error ?? "Unknown error occurred")
        }
    }
    
    private func loadGroups() async {
        do {
            try await groupService.fetchUserGroups()
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.showError = true
            }
        }
    }
    
    private func shareToGroup(_ group: UserGroup) {
        isLoading = true
        
        Task {
            do {
                try await groupService.sendTextMessage(groupId: group.id, text: "📝 Note: \(noteText)")
                
                await MainActor.run {
                    isLoading = false
                    onGroupSelected(group)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    self.error = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }
}

struct GroupSelectionRow: View {
    let group: UserGroup
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Group avatar or placeholder
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    if let avatarURL = group.avatarURL, let url = URL(string: avatarURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.gray)
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if let description = group.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("\(group.memberCount) members")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
} 