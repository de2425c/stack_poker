import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import Combine
import UIKit

enum GroupError: Error {
    case notAuthenticated
    case groupNotFound
    case userNotFound
    case invalidData
    case userAlreadyMember
    case inviteAlreadyExists
    case inviteNotFound
    case ownerCannotLeave
    case permissionDenied
    case selfInvite
}

// Add asyncMap to sequence for concurrent operations
extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var values = [T]()
        for element in self {
            try await values.append(transform(element))
        }
        return values
    }
}

@MainActor
class GroupService: ObservableObject {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    @Published var userGroups: [UserGroup] = []
    @Published var pendingInvites: [GroupInvite] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var availableUsers: [UserListItem] = []
    @Published var groupMembers: [GroupMemberInfo] = []
    @Published var groupMessages: [GroupMessage] = []
    
    // Simple pagination tracking
    private var messageListener: ListenerRegistration?
    private var lastMessageDocument: DocumentSnapshot?
    
    private let userService = UserService()
    
    // Cleanup listener
    deinit {
        messageListener?.remove()
        messageListener = nil
        lastMessageDocument = nil
    }
    
    // Create a new group
    func createGroup(name: String, description: String?, image: UIImage? = nil, leaderboardType: String? = nil) async throws -> UserGroup {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw GroupError.notAuthenticated
        }
        
        // Create a new group document
        let groupRef = db.collection("groups").document()
        let groupId = groupRef.documentID
        
        let timestamp = Timestamp(date: Date())
        var groupData: [String: Any] = [
            "name": name,
            "description": description ?? "",
            "createdAt": timestamp,
            "ownerId": userId,
            "memberCount": 1,
            "leaderboardType": "most_hours" // Default to most hours
        ]
        
        // Add leaderboard type if provided
        if let leaderboardType = leaderboardType {
            groupData["leaderboardType"] = leaderboardType
        }
        
        // If image is provided, upload it first
        if let image = image {
            do {
                let imageURL = try await uploadGroupImage(image, groupId: groupId)
                groupData["avatarURL"] = imageURL
            } catch {
                // Continue creating the group without the image
            }
        }
        
        // Add the group to Firestore
        try await groupRef.setData(groupData)
        
        // Add the user as a member
        let memberRef = groupRef.collection("members").document(userId)
        try await memberRef.setData([
            "userId": userId,
            "role": GroupMember.MemberRole.owner.rawValue,
            "joinedAt": timestamp
        ])
        
        // Add the group to the user's group collection for easy querying
        let userGroupRef = db.collection("users").document(userId).collection("groups").document(groupId)
        try await userGroupRef.setData([
            "groupId": groupId,
            "joinedAt": timestamp,
            "role": GroupMember.MemberRole.owner.rawValue
        ])
        
        // Create and return the group
        let newGroup = UserGroup(
            id: groupId,
            name: name,
            description: description,
            createdAt: timestamp.dateValue(),
            ownerId: userId,
            avatarURL: groupData["avatarURL"] as? String,
            memberCount: 1,
            leaderboardType: leaderboardType
        )
        
        // Update the published groups list
        self.userGroups.append(newGroup)
        self.userGroups.sort { $0.createdAt > $1.createdAt }
        
        return newGroup
    }
    
    // Fetch groups the user is a member of
    func fetchUserGroups() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw GroupError.notAuthenticated
        }
        
        self.isLoading = true
        self.error = nil
        
        do {
            let fetchedGroups = try await _fetchUserGroupsData(userId: userId)
            
            self.userGroups = fetchedGroups
            self.isLoading = false
        } catch {
            self.error = error
            self.isLoading = false
            throw error
        }
    }
    
    private func _fetchUserGroupsData(userId: String) async throws -> [UserGroup] {
        // Get the user's groups
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("groups")
            .getDocuments()
        
        var groups: [UserGroup] = []
        
        // Fetch each group's details
        for doc in snapshot.documents {
            guard let groupId = doc.data()["groupId"] as? String else { continue }
            
            do {
                let groupDoc = try await db.collection("groups").document(groupId).getDocument()
                
                if let groupData = groupDoc.data(), groupDoc.exists {
                    var data = groupData
                    data["id"] = groupId
                    
                    let group = try UserGroup(dictionary: data, id: groupId)
                    groups.append(group)
                }
            } catch {
                // Continue with next group
            }
        }
        
        // Sort groups by last message time (most recent first), fallback to creation date
        groups.sort { group1, group2 in
            if let time1 = group1.lastMessageTime, let time2 = group2.lastMessageTime {
                return time1 > time2
            } else if group1.lastMessageTime != nil {
                return true // group1 has messages, group2 doesn't
            } else if group2.lastMessageTime != nil {
                return false // group2 has messages, group1 doesn't
            } else {
                return group1.createdAt > group2.createdAt // both have no messages, sort by creation
            }
        }
        return groups
    }
    
    // Send an invite to a user to join a group
    func inviteUserToGroup(username: String, groupId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw GroupError.notAuthenticated
        }
        
        // First, get the group to confirm existence and get name
        let groupDoc = try await db.collection("groups").document(groupId).getDocument()
        
        guard let groupData = groupDoc.data(), groupDoc.exists else {
            throw GroupError.groupNotFound
        }
        
        let groupName = groupData["name"] as? String ?? "Unknown Group"
        
        // Find the user by username
        let userQuery = try await db.collection("users")
            .whereField("username", isEqualTo: username)
            .getDocuments()
        
        guard let userDoc = userQuery.documents.first, let inviteeId = userDoc.data()["id"] as? String else {
            throw GroupError.userNotFound
        }
        
        // Check if the user is already a member
        let memberDoc = try await db.collection("groups")
            .document(groupId)
            .collection("members")
            .document(inviteeId)
            .getDocument()
        
        if memberDoc.exists {
            throw GroupError.userAlreadyMember
        }
        
        // Check if an invite is already pending
        let inviteQuery = try await db.collection("users")
            .document(inviteeId)
            .collection("groupInvites")
            .whereField("groupId", isEqualTo: groupId)
            .whereField("status", isEqualTo: GroupInvite.InviteStatus.pending.rawValue)
            .getDocuments()
        
        if !inviteQuery.documents.isEmpty {
            throw GroupError.inviteAlreadyExists
        }
        
        // Get the current user's name
        let currentUserDoc = try await db.collection("users")
            .document(currentUserId)
            .getDocument()
        
        let currentUserData = currentUserDoc.data()
        let inviterName = currentUserData?["displayName"] as? String ?? currentUserData?["username"] as? String ?? "Unknown User"
        
        // Create the invite
        let inviteRef = db.collection("users")
            .document(inviteeId)
            .collection("groupInvites")
            .document()
        
        let inviteId = inviteRef.documentID
        let timestamp = Timestamp(date: Date())
        
        let inviteData: [String: Any] = [
            "id": inviteId,
            "groupId": groupId,
            "groupName": groupName,
            "inviterId": currentUserId,
            "inviterName": inviterName,
            "inviteeId": inviteeId,
            "createdAt": timestamp,
            "status": GroupInvite.InviteStatus.pending.rawValue
        ]
        
        // Save the invite
        try await inviteRef.setData(inviteData)
    }
    
    // Fetch pending group invites for the current user
    func fetchPendingInvites() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw GroupError.notAuthenticated
        }
        
        self.isLoading = true
        self.error = nil
        
        do {
            let fetchedInvites = try await _fetchPendingInvitesData(userId: userId)
            
            self.pendingInvites = fetchedInvites
            self.isLoading = false
        } catch {
            self.error = error
            self.isLoading = false
            throw error
        }
    }
    
    private func _fetchPendingInvitesData(userId: String) async throws -> [GroupInvite] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("groupInvites")
            .whereField("status", isEqualTo: GroupInvite.InviteStatus.pending.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        var invites: [GroupInvite] = []

        for doc in snapshot.documents {
            if let data = doc.data() as? [String: Any] {
                do {
                    let invite = try GroupInvite(dictionary: data, id: doc.documentID)
                    invites.append(invite)
                } catch {
                    // Log or handle individual parsing error if needed
                }
            }
        }
        return invites
    }
    
    // Accept a group invite
    func acceptInvite(inviteId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw GroupError.notAuthenticated
        }
        
        // Get the invite
        let inviteRef = db.collection("users")
            .document(userId)
            .collection("groupInvites")
            .document(inviteId)
        
        let inviteDoc = try await inviteRef.getDocument()
        
        guard let inviteData = inviteDoc.data(), inviteDoc.exists else {
            throw GroupError.inviteNotFound
        }
        
        guard let groupId = inviteData["groupId"] as? String else {
            throw GroupError.invalidData
        }
        
        // Update the invite status
        try await inviteRef.updateData([
            "status": GroupInvite.InviteStatus.accepted.rawValue
        ])
        
        // Add the user as a member of the group
        let timestamp = Timestamp(date: Date())
        let memberRef = db.collection("groups")
            .document(groupId)
            .collection("members")
            .document(userId)
        
        try await memberRef.setData([
            "userId": userId,
            "role": GroupMember.MemberRole.member.rawValue,
            "joinedAt": timestamp
        ])
        
        // Add the group to the user's groups collection
        let userGroupRef = db.collection("users")
            .document(userId)
            .collection("groups")
            .document(groupId)
        
        try await userGroupRef.setData([
            "groupId": groupId,
            "joinedAt": timestamp,
            "role": GroupMember.MemberRole.member.rawValue
        ])
        
        // Increment the group's member count
        let groupRef = db.collection("groups").document(groupId)
        try await groupRef.updateData([
            "memberCount": FieldValue.increment(Int64(1))
        ])
        
        // Update the local pending invites list
        self.pendingInvites.removeAll { $0.id == inviteId }
        
        // Refresh the user's groups
        try await fetchUserGroups()
    }
    
    // Decline a group invite
    func declineInvite(inviteId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw GroupError.notAuthenticated
        }
        
        // Update the invite status
        let inviteRef = db.collection("users")
            .document(userId)
            .collection("groupInvites")
            .document(inviteId)
        
        try await inviteRef.updateData([
            "status": GroupInvite.InviteStatus.declined.rawValue
        ])
        
        // Update the local pending invites list
        self.pendingInvites.removeAll { $0.id == inviteId }
    }
    
    // Leave a group
    func leaveGroup(groupId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw GroupError.notAuthenticated
        }
        
        // Get the group to check if the user is the owner
        let groupDoc = try await db.collection("groups").document(groupId).getDocument()
        
        guard let groupData = groupDoc.data(), groupDoc.exists else {
            throw GroupError.groupNotFound
        }
        
        let ownerId = groupData["ownerId"] as? String
        
        // Owner cannot leave the group (they must delete it or transfer ownership)
        if ownerId == userId {
            throw GroupError.ownerCannotLeave
        }
        
        // Remove the user from the group's members
        let memberRef = db.collection("groups")
            .document(groupId)
            .collection("members")
            .document(userId)
        
        try await memberRef.delete()
        
        // Remove the group from the user's groups
        let userGroupRef = db.collection("users")
            .document(userId)
            .collection("groups")
            .document(groupId)
        
        try await userGroupRef.delete()
        
        // Decrement the group's member count
        let groupRef = db.collection("groups").document(groupId)
        try await groupRef.updateData([
            "memberCount": FieldValue.increment(Int64(-1))
        ])
        
        // Update the local groups list
        self.userGroups.removeAll { $0.id == groupId }
    }
    
    // Fetch users for the invite dropdown
    func fetchAvailableUsers() async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw GroupError.notAuthenticated
        }

        self.isLoading = true
        self.error = nil // Also clear previous error

        do {
            let fetchedUsers = try await _fetchAvailableUsersData(currentUserId: currentUserId)
            
            self.availableUsers = fetchedUsers
            self.isLoading = false
            
        } catch {
            self.error = error
            self.isLoading = false
            throw error
        }
    }

    private func _fetchAvailableUsersData(currentUserId: String) async throws -> [UserListItem] {
        let snapshot = try await db.collection("users")
            .getDocuments()

        var users: [UserListItem] = []

        for doc in snapshot.documents {
            let data = doc.data()
            let userId = doc.documentID

            // Don't include the current user
            if userId == currentUserId {
                continue
            }

            if let username = data["username"] as? String {
                let displayName = data["displayName"] as? String
                let avatarURL = data["avatarURL"] as? String

                let user = UserListItem(
                    id: userId,
                    username: username,
                    displayName: displayName,
                    avatarURL: avatarURL
                )
                users.append(user)
            }
        }

        // Sort by username
        users.sort { $0.username < $1.username }
        return users
    }
    
    // Fetch all members of a group
    func fetchGroupMembers(groupId: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw GroupError.notAuthenticated
        }

        self.isLoading = true
        self.groupMembers = [] // Clear previous members
        self.error = nil // Clear previous error

        do {
            let fetchedMembers = try await _fetchGroupMembersData(groupId: groupId)
            
            self.groupMembers = fetchedMembers
            self.isLoading = false
            
        } catch {
            self.error = error
            self.isLoading = false
            throw error
        }
    }

    private func _fetchGroupMembersData(groupId: String) async throws -> [GroupMemberInfo] {
        // Get all members from the group's members collection
        let snapshot = try await db.collection("groups")
            .document(groupId)
            .collection("members")
            .getDocuments()

        var members: [GroupMemberInfo] = []

        // For each member, get their user profile
        for doc in snapshot.documents {
            let data = doc.data()
            let userId = doc.documentID

            if let role = data["role"] as? String,
               let joinedAt = (data["joinedAt"] as? Timestamp)?.dateValue() {

                // Get the user's profile
                let userDoc = try await db.collection("users")
                    .document(userId)
                    .getDocument()

                if let userData = userDoc.data() {
                    let username = userData["username"] as? String ?? "Unknown"
                    let displayName = userData["displayName"] as? String
                    let avatarURL = userData["avatarURL"] as? String

                    let member = GroupMemberInfo(
                        id: userId,
                        username: username,
                        displayName: displayName,
                        avatarURL: avatarURL,
                        role: role,
                        joinedAt: joinedAt
                    )
                    members.append(member)
                }
            }
        }

        // Sort by role (owner first) then by join date
        members.sort { member1, member2 in
            if member1.role == GroupMember.MemberRole.owner.rawValue && 
               member2.role != GroupMember.MemberRole.owner.rawValue {
                return true
            } else if member1.role != GroupMember.MemberRole.owner.rawValue && 
                      member2.role == GroupMember.MemberRole.owner.rawValue {
                return false
            } else {
                return member1.joinedAt < member2.joinedAt
            }
        }
        return members
    }
    
    // Upload a group profile image with completion handler (like UserService)
    func uploadGroupImageWithCompletion(_ image: UIImage, groupId: String, completion: @escaping (Result<String, Error>) -> Void) {
        let fileName = "group_\(groupId)_\(UUID().uuidString).jpg"
        let storageRef = storage.reference().child("groups/\(fileName)")
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(NSError(domain: "ImageError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not convert image."])))
            return
        }
        
        // Add metadata to help with parsing
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        storageRef.putData(imageData, metadata: metadata) { metadata, error in
            if let error = error {
                print("❌ Upload error: \(error)")
                completion(.failure(error))
                return
            }
            
            print("✅ Upload successful, getting download URL...")
            
            // Add a small delay to ensure the upload is fully processed
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                storageRef.downloadURL { url, error in
                    if let error = error {
                        print("❌ Download URL error: \(error)")
                        completion(.failure(error))
                        return
                    }
                    
                    if let urlString = url?.absoluteString {
                        print("✅ Got download URL: \(urlString)")
                        // Ensure we're using HTTPS
                        let httpsUrlString = urlString.replacingOccurrences(of: "http://", with: "https://")
                        completion(.success(httpsUrlString))
                    } else {
                        print("❌ No URL returned")
                        completion(.failure(NSError(domain: "URLError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No URL returned."])))
                    }
                }
            }
        }
    }

    // Upload a group profile image and return its download URL
    func uploadGroupImage(_ image: UIImage, groupId: String) async throws -> String {
        
        // Compress the image to reduce upload size
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw GroupError.invalidData
        }
        
        // Create a unique file name for the image
        let fileName = "group_\(groupId)_\(Date().timeIntervalSince1970).jpg"
        
        // Get the Firebase Storage reference
        let storageRef = storage.reference().child("groups/\(fileName)")
        
        
        // Upload the image to Firebase Storage
        do {
            // Upload the image
            _ = try await storageRef.putData(imageData, metadata: nil)
            
            // Add a small delay to allow Firebase to process the upload
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            
            // Get the download URL with retries
            var downloadURL: URL?
            var retryCount = 0
            let maxRetries = 3
            
            while downloadURL == nil && retryCount < maxRetries {
                do {
                    downloadURL = try await storageRef.downloadURL()
                } catch {
                    retryCount += 1
                    if retryCount < maxRetries {
                        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 second delay between retries
                    }
                }
            }
            
            guard let finalURL = downloadURL else {
                throw NSError(domain: "GroupService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL after \(maxRetries) attempts"])
            }
            
            return finalURL.absoluteString
        } catch {
            throw error
        }
    }
    
    // Update the group avatar URL directly
    func updateGroupAvatar(groupId: String, avatarURL: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw GroupError.notAuthenticated
        }
        
        // Check if the user is the group owner or fetch the group if needed
        let groupDoc = try await db.collection("groups")
            .document(groupId)
            .getDocument()
        
        guard let groupData = groupDoc.data(),
              let ownerId = groupData["ownerId"] as? String,
              ownerId == userId else {
            throw GroupError.permissionDenied
        }
        
        // Update the group's avatarURL field
        try await db.collection("groups")
            .document(groupId)
            .updateData(["avatarURL": avatarURL])
        
        // Update the group in the local list
        if let index = self.userGroups.firstIndex(where: { $0.id == groupId }) {
            var updatedGroup = self.userGroups[index]
            updatedGroup.avatarURL = avatarURL
            self.userGroups[index] = updatedGroup
        }
    }
    
    // MARK: - Chat Methods
    
    // Simple message fetching with pagination
    func fetchGroupMessages(groupId: String, limit: Int = 30, loadMore: Bool = false) async throws {
        guard Auth.auth().currentUser != nil else {
            throw GroupError.notAuthenticated
        }

        print("🔍 fetchGroupMessages called - groupId: \(groupId), limit: \(limit), loadMore: \(loadMore)")

        // Clean up any existing listener when switching groups
        if !loadMore {
            messageListener?.remove()
            messageListener = nil
            lastMessageDocument = nil
        }

        do {
            // Build query
            var query = db.collection("groups")
                .document(groupId)
                .collection("messages")
                .order(by: "timestamp", descending: true)
                .limit(to: limit)

            // If loading more, start after the last document
            if loadMore, let lastDoc = lastMessageDocument {
                query = query.start(afterDocument: lastDoc)
            }

            // Execute query
            print("📋 Executing query...")
            let snapshot = try await query.getDocuments()
            print("📦 Got \(snapshot.documents.count) documents from Firestore")
            
            var newMessages: [GroupMessage] = []
            
            // Parse messages
            for doc in snapshot.documents {
                do {
                    let message = try GroupMessage(dictionary: doc.data(), id: doc.documentID)
                    newMessages.append(message)
                    print("✅ Parsed message: \(message.id)")
                } catch {
                    print("❌ Failed to parse message \(doc.documentID): \(error)")
                }
            }
            
            print("📊 Parsed \(newMessages.count) messages successfully")
            
            // Store last document for pagination
            lastMessageDocument = snapshot.documents.last
            
            if loadMore {
                // Append to existing messages (older messages go at the beginning)
                self.groupMessages = newMessages + self.groupMessages
                print("📈 Load more: total messages now: \(self.groupMessages.count)")
            } else {
                // Replace all messages
                self.groupMessages = newMessages
                print("🔄 Initial load: \(self.groupMessages.count) messages")
                
                // Set up real-time listener for new messages only
                setupNewMessageListener(groupId: groupId)
            }
            
            // Sort by timestamp (oldest first)
            self.groupMessages.sort { $0.timestamp < $1.timestamp }
            print("✅ Final message count after sort: \(self.groupMessages.count)")
            
        } catch {
            print("❌ Error fetching messages: \(error)")
            throw error
        }
    }
    
    // Listen only for new messages (not the entire collection)
    private func setupNewMessageListener(groupId: String) {
        let now = Timestamp(date: Date())
        
        messageListener = db.collection("groups")
            .document(groupId)
            .collection("messages")
            .whereField("timestamp", isGreaterThan: now)
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let snapshot = snapshot else { return }
                
                for change in snapshot.documentChanges {
                    if change.type == .added {
                        if let message = try? GroupMessage(dictionary: change.document.data(), id: change.document.documentID) {
                            // Check if message already exists
                            if !self.groupMessages.contains(where: { $0.id == message.id }) {
                                self.groupMessages.append(message)
                                // Keep sorted
                                self.groupMessages.sort { $0.timestamp < $1.timestamp }
                                print("📨 New message received via listener: \(message.id)")
                            }
                        }
                    }
                }
            }
    }
    
    // Clean up when leaving a group
    func cleanupGroupListener() {
        messageListener?.remove()
        messageListener = nil
        lastMessageDocument = nil
        groupMessages = []
    }

    // Send a text message
    func sendTextMessage(groupId: String, text: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw GroupError.notAuthenticated
        }
        
        // Get the user's info
        let userDoc = try await db.collection("users").document(userId).getDocument()
        guard let userData = userDoc.data() else {
            throw GroupError.invalidData
        }
        
        let username = userData["username"] as? String ?? "Unknown"
        let displayName = userData["displayName"] as? String
        let senderName = displayName ?? username
        let avatarURL = userData["avatarURL"] as? String
        
        // Create a message document
        let messageRef = db.collection("groups")
            .document(groupId)
            .collection("messages")
            .document()
        
        let timestamp = Timestamp(date: Date())
        
        let messageData: [String: Any] = [
            "groupId": groupId,
            "senderId": userId,
            "senderName": senderName,
            "senderAvatarURL": avatarURL as Any,
            "timestamp": timestamp,
            "messageType": GroupMessage.MessageType.text.rawValue,
            "text": text
        ]
        
        // Save the message
        try await messageRef.setData(messageData)
        
        // Update the group's last message information
        try await db.collection("groups").document(groupId).updateData([
            "lastMessage": text,
            "lastMessageTime": timestamp
        ])
        
        // Notify that a message was sent to update group order
        NotificationCenter.default.post(name: NSNotification.Name("GroupMessageSent"), object: nil)
    }
    
    // Send an image message
    func sendImageMessage(groupId: String, image: UIImage) async throws {
        
        guard let userId = Auth.auth().currentUser?.uid else {
            throw GroupError.notAuthenticated
        }
        
        // Get the user's info
        let userDoc = try await db.collection("users").document(userId).getDocument()
        guard let userData = userDoc.data() else {
            throw GroupError.invalidData
        }
        
        let username = userData["username"] as? String ?? "Unknown"
        let displayName = userData["displayName"] as? String
        let senderName = displayName ?? username
        let avatarURL = userData["avatarURL"] as? String
        
        
        // Resize large images before uploading to reduce storage and bandwidth
        let maxSize: CGFloat = 1200
        let resizedImage: UIImage
        
        if image.size.width > maxSize || image.size.height > maxSize {
            let scale = maxSize / max(image.size.width, image.size.height)
            let newWidth = image.size.width * scale
            let newHeight = image.size.height * scale
            let newSize = CGSize(width: newWidth, height: newHeight)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            if let resized = UIGraphicsGetImageFromCurrentImageContext() {
                resizedImage = resized
            } else {
                resizedImage = image
            }
            UIGraphicsEndImageContext()
            
        } else {
            resizedImage = image
        }
        
        // Try multiple compression levels if needed
        var compressionQuality: CGFloat = 0.7
        var imageData = resizedImage.jpegData(compressionQuality: compressionQuality)
        
        // If we still don't have image data, try PNG as a fallback
        if imageData == nil {
            imageData = resizedImage.pngData()
        }
        
        guard let finalImageData = imageData else {
            throw GroupError.invalidData
        }
        
        
        let uuid = UUID().uuidString
        let storageRef = storage.reference().child("group_messages/\(groupId)/\(uuid).jpg")
        
        
        // Upload the image to Firebase Storage
        do {
            // Upload the image
            _ = try await storageRef.putData(finalImageData, metadata: nil)
            
            // Add a small delay to allow Firebase to process the upload
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            
            // Get the download URL with retries
            var downloadURL: URL?
            var retryCount = 0
            let maxRetries = 3
            
            while downloadURL == nil && retryCount < maxRetries {
                do {
                    downloadURL = try await storageRef.downloadURL()
                } catch {
                    retryCount += 1
                    if retryCount < maxRetries {
                        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 second delay between retries
                    }
                }
            }
            
            guard let finalURL = downloadURL else {
                throw NSError(domain: "GroupService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL after \(maxRetries) attempts"])
            }
            
            let imageURL = finalURL.absoluteString
            
            // Create the message document
            let messageRef = db.collection("groups")
                .document(groupId)
                .collection("messages")
                .document()
            
            let timestamp = Timestamp(date: Date())
            
            let messageData: [String: Any] = [
                "groupId": groupId,
                "senderId": userId,
                "senderName": senderName,
                "senderAvatarURL": avatarURL as Any,
                "timestamp": timestamp,
                "messageType": GroupMessage.MessageType.image.rawValue,
                "imageURL": imageURL
            ]
            
            // Save the message
            try await messageRef.setData(messageData)
            
            // Update the group's last message information
            try await db.collection("groups").document(groupId).updateData([
                "lastMessage": "📷 Photo",
                "lastMessageTime": timestamp
            ])
            
            // Notify that a message was sent to update group order
            NotificationCenter.default.post(name: NSNotification.Name("GroupMessageSent"), object: nil)
            
            return
        } catch {
            throw error
        }
    }
    
    // Send a hand history message
    func sendHandMessage(groupId: String, handHistoryId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw GroupError.notAuthenticated
        }
        
        // Get the user's info
        let userDoc = try await db.collection("users").document(userId).getDocument()
        guard let userData = userDoc.data() else {
            throw GroupError.invalidData
        }
        
        let username = userData["username"] as? String ?? "Unknown"
        let displayName = userData["displayName"] as? String
        let senderName = displayName ?? username
        let avatarURL = userData["avatarURL"] as? String
        
        // Create the message document
        let messageRef = db.collection("groups")
            .document(groupId)
            .collection("messages")
            .document()
        
        let timestamp = Timestamp(date: Date())
        
        let messageData: [String: Any] = [
            "groupId": groupId,
            "senderId": userId,
            "senderName": senderName,
            "senderAvatarURL": avatarURL as Any,
            "timestamp": timestamp,
            "messageType": GroupMessage.MessageType.hand.rawValue,
            "handHistoryId": handHistoryId,
            "handOwnerUserId": userId
        ]
        
        // Save the message
        try await messageRef.setData(messageData)
        
        // Update the group's last message information
        try await db.collection("groups").document(groupId).updateData([
            "lastMessage": "🃏 Poker Hand",
            "lastMessageTime": timestamp
        ])
        
        // Notify that a message was sent to update group order
        NotificationCenter.default.post(name: NSNotification.Name("GroupMessageSent"), object: nil)
    }
    
    // Add sendHomeGameMessage function
    func sendHomeGameMessage(groupId: String, homeGame: HomeGame) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw GroupError.notAuthenticated
        }
        
        // Get the user's info
        let userDoc = try await db.collection("users").document(userId).getDocument()
        guard let userData = userDoc.data() else {
            throw GroupError.invalidData
        }
        
        let username = userData["username"] as? String ?? "Unknown"
        let displayName = userData["displayName"] as? String
        let senderName = displayName ?? username
        let avatarURL = userData["avatarURL"] as? String
        
        // First, store the home game in Firestore
        let homeGameRef = db.collection("homeGames").document(homeGame.id)
        try await homeGameRef.setData([
            "id": homeGame.id,
            "title": homeGame.title,
            "createdAt": Timestamp(date: homeGame.createdAt),
            "creatorId": homeGame.creatorId,
            "creatorName": homeGame.creatorName,
            "groupId": homeGame.groupId,
            "status": homeGame.status.rawValue,
            "players": homeGame.players.map { player in
                [
                    "id": player.id,
                    "userId": player.userId,
                    "displayName": player.displayName,
                    "currentStack": player.currentStack,
                    "totalBuyIn": player.totalBuyIn,
                    "joinedAt": Timestamp(date: player.joinedAt),
                    "status": player.status.rawValue
                ]
            },
            "buyInRequests": homeGame.buyInRequests.map { request in
                [
                    "id": request.id,
                    "userId": request.userId,
                    "displayName": request.displayName,
                    "amount": request.amount,
                    "requestedAt": Timestamp(date: request.requestedAt),
                    "status": request.status.rawValue
                ]
            },
            "cashOutRequests": homeGame.cashOutRequests.map { request in
                [
                    "id": request.id,
                    "userId": request.userId,
                    "displayName": request.displayName,
                    "amount": request.amount,
                    "requestedAt": Timestamp(date: request.requestedAt),
                    "processedAt": request.processedAt.map { Timestamp(date: $0) },
                    "status": request.status.rawValue
                ]
            },
            "gameHistory": homeGame.gameHistory.map { event in
                [
                    "id": event.id,
                    "timestamp": Timestamp(date: event.timestamp),
                    "eventType": event.eventType.rawValue,
                    "userId": event.userId,
                    "userName": event.userName,
                    "amount": event.amount,
                    "description": event.description
                ]
            }
        ])
        
        // Create the message document
        let messageRef = db.collection("groups")
            .document(groupId)
            .collection("messages")
            .document()
        
        let timestamp = Timestamp(date: Date())
        
        let messageData: [String: Any] = [
            "groupId": groupId,
            "senderId": userId,
            "senderName": senderName,
            "senderAvatarURL": avatarURL as Any,
            "timestamp": timestamp,
            "messageType": GroupMessage.MessageType.homeGame.rawValue,
            "homeGameId": homeGame.id,
            "title": homeGame.title
        ]
        
        // Save the message
        try await messageRef.setData(messageData)
        
        // Update the group's last message information
        try await db.collection("groups").document(groupId).updateData([
            "lastMessage": "🏠 Home Game: \(homeGame.title)",
            "lastMessageTime": timestamp,
            "lastMessageAt": FieldValue.serverTimestamp(),
            "lastMessageType": GroupMessage.MessageType.homeGame.rawValue
        ])
        
        // Notify that a message was sent to update group order
        NotificationCenter.default.post(name: NSNotification.Name("GroupMessageSent"), object: nil)
    }
    
    // Delete a group (only owner can do this)
    func deleteGroup(groupId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw GroupError.notAuthenticated
        }
        
        // Get the group to check if the user is the owner
        let groupDoc = try await db.collection("groups").document(groupId).getDocument()
        
        guard let groupData = groupDoc.data(), groupDoc.exists else {
            throw GroupError.groupNotFound
        }
        
        let ownerId = groupData["ownerId"] as? String
        
        // Only owner can delete the group
        guard ownerId == userId else {
            throw GroupError.permissionDenied
        }
        
        // Delete all messages in the group
        let messagesSnapshot = try await db.collection("groups")
            .document(groupId)
            .collection("messages")
            .getDocuments()
        
        // Delete messages in batches
        let batch = db.batch()
        for doc in messagesSnapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
        
        // Delete all members
        let membersSnapshot = try await db.collection("groups")
            .document(groupId)
            .collection("members")
            .getDocuments()
        
        // Remove group from all members' user collections
        for memberDoc in membersSnapshot.documents {
            let memberId = memberDoc.documentID
            
            // Remove from user's groups collection
            try await db.collection("users")
                .document(memberId)
                .collection("groups")
                .document(groupId)
                .delete()
            
            // Delete member document
            try await memberDoc.reference.delete()
        }
        
        // Delete any pending invites for this group
        let usersSnapshot = try await db.collection("users").getDocuments()
        for userDoc in usersSnapshot.documents {
            let invitesSnapshot = try await userDoc.reference
                .collection("groupInvites")
                .whereField("groupId", isEqualTo: groupId)
                .getDocuments()
            
            for inviteDoc in invitesSnapshot.documents {
                try await inviteDoc.reference.delete()
            }
        }
        
        // Finally, delete the group document itself
        try await db.collection("groups").document(groupId).delete()
        
        // Update the local groups list
        self.userGroups.removeAll { $0.id == groupId }
    }
    
    // Update the group's leaderboard type
    func updateGroupLeaderboard(groupId: String, leaderboardType: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw GroupError.notAuthenticated
        }
        
        let groupRef = db.collection("groups").document(groupId)
        let groupDoc = try await groupRef.getDocument()
        
        guard let groupData = groupDoc.data(),
              let ownerId = groupData["ownerId"] as? String,
              ownerId == userId else {
            throw GroupError.permissionDenied
        }
        
        try await groupRef.updateData(["leaderboardType": leaderboardType])
        
        // Update the local userGroups cache
        if let index = userGroups.firstIndex(where: { $0.id == groupId }) {
            userGroups[index].leaderboardType = leaderboardType
        }
    }
    
    // MARK: - Leaderboard Functionality
    
    func getLeaderboard(groupId: String, type: String) async throws -> [LeaderboardEntry] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw GroupError.notAuthenticated
        }

        // 1. Fetch all members of the group
        let membersSnapshot = try await db.collection("groups").document(groupId).collection("members").getDocuments()
        let memberIds = membersSnapshot.documents.map { $0.documentID }
        
        guard !memberIds.isEmpty else {
            return [] // No members in the group
        }

        // 2. Fetch all user profiles for the members in parallel
        let userProfiles = try await memberIds.asyncMap { memberId -> UserProfile? in
            return try? await userService.fetchUserProfile(userId: memberId)
        }.compactMap { $0 }

        // 3. Fetch all sessions for all members in parallel
        let memberHours = try await memberIds.asyncMap { memberId -> (String, Double) in
            var totalDuration: TimeInterval = 0
            
            // Assuming sessions are stored in a 'sessions' subcollection under each user
            let sessionsSnapshot = try await db.collection("users").document(memberId).collection("sessions").getDocuments()
            
            for document in sessionsSnapshot.documents {
                // Look for 'duration' or 'elapsedTime' and ensure it's a number
                if let duration = document.data()["duration"] as? TimeInterval {
                    totalDuration += duration
                } else if let elapsedTime = document.data()["elapsedTime"] as? TimeInterval {
                    totalDuration += elapsedTime
                } else if let hoursPlayed = document.data()["hoursPlayed"] as? Double {
                    totalDuration += (hoursPlayed * 3600.0) // Convert hours to seconds
                }
            }
            
            let totalHours = totalDuration / 3600.0
            return (memberId, totalHours)
        }

        // 4. Await results and build leaderboard
        let hoursDictionary = Dictionary(uniqueKeysWithValues: memberHours)

        let leaderboardEntries = userProfiles.map { profile -> LeaderboardEntry in
            let userHours = hoursDictionary[profile.id] ?? 0.0
            return LeaderboardEntry(id: profile.id, user: profile, totalHours: userHours)
        }

        // 5. Sort the leaderboard by hours descending
        let sortedLeaderboard = leaderboardEntries.sorted { $0.totalHours > $1.totalHours }
        
        return sortedLeaderboard
    }
}

enum GroupServiceError: Error, CustomStringConvertible {
    case notAuthenticated
    case groupNotFound
    case userNotFound
    case invalidData
    case userAlreadyMember
    case inviteAlreadyExists
    case inviteNotFound
    case ownerCannotLeave
    case permissionDenied
    
    var description: String {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .groupNotFound:
            return "Group not found"
        case .userNotFound:
            return "User not found"
        case .invalidData:
            return "Invalid data"
        case .userAlreadyMember:
            return "User is already a member of this group"
        case .inviteAlreadyExists:
            return "This user has already been invited to this group"
        case .inviteNotFound:
            return "Invite not found"
        case .ownerCannotLeave:
            return "The owner cannot leave the group"
        case .permissionDenied:
            return "You don't have permission to perform this action"
        }
    }
    
    var message: String {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to perform this action"
        case .groupNotFound:
            return "The group could not be found"
        case .userNotFound:
            return "The user could not be found. Please check the username."
        case .invalidData:
            return "Invalid data provided"
        case .userAlreadyMember:
            return "This user is already a member of this group"
        case .inviteAlreadyExists:
            return "This user has already been invited to this group"
        case .inviteNotFound:
            return "The invite could not be found"
        case .ownerCannotLeave:
            return "You are the owner of this group. You must transfer ownership or delete the group instead."
        case .permissionDenied:
            return "You don't have permission to perform this action"
        }
    }
} 
