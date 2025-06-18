import Foundation
import FirebaseFirestore

class ManualStakerService: ObservableObject {
    private let db = Firestore.firestore()
    private var manualStakersCollectionRef: CollectionReference { 
        db.collection("manualStakers") 
    }
    
    @Published var manualStakers: [ManualStakerProfile] = []
    @Published var isLoading = false
    
    // MARK: - Create
    func createManualStaker(_ profile: ManualStakerProfile) async throws -> String {
        var profileToSave = profile
        if profileToSave.id == nil {
            profileToSave.id = manualStakersCollectionRef.document().documentID
        }
        
        try manualStakersCollectionRef.document(profileToSave.id!).setData(from: profileToSave)
        
        // Update local array
        await MainActor.run {
            if let index = manualStakers.firstIndex(where: { $0.id == profileToSave.id }) {
                manualStakers[index] = profileToSave
            } else {
                manualStakers.append(profileToSave)
                // Sort by name for consistent ordering
                manualStakers.sort { $0.name.lowercased() < $1.name.lowercased() }
            }
        }
        
        return profileToSave.id!
    }
    
    // MARK: - Read
    func fetchManualStakers(forUser userId: String) async throws -> [ManualStakerProfile] {
        await MainActor.run { isLoading = true }
        
        let query = manualStakersCollectionRef
            .whereField(ManualStakerProfile.CodingKeys.createdByUserId.rawValue, isEqualTo: userId)
            .order(by: ManualStakerProfile.CodingKeys.name.rawValue)
        
        do {
            let snapshot = try await query.getDocuments()
            
            var profiles: [ManualStakerProfile] = []
            for document in snapshot.documents {
                do {
                    var profile = try document.data(as: ManualStakerProfile.self)
                    // Ensure the ID is set from the document ID if not already set
                    if profile.id == nil {
                        profile.id = document.documentID
                    }
                    print("Loaded manual staker: \(profile.name), contactInfo: '\(profile.contactInfo ?? "nil")', ID: '\(profile.id ?? "nil")', documentID: '\(document.documentID)'")
                    profiles.append(profile)
                } catch {
                    print("Failed to decode manual staker document \(document.documentID): \(error)")
                }
            }
            
            await MainActor.run {
                self.manualStakers = profiles
                self.isLoading = false
            }
            
            return profiles
        } catch {
            await MainActor.run { isLoading = false }
            throw error
        }
    }
    
    func getManualStaker(id: String) async throws -> ManualStakerProfile {
        let document = try await manualStakersCollectionRef.document(id).getDocument()
        
        guard document.exists else {
            throw NSError(domain: "ManualStakerService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Manual staker profile not found"])
        }
        
        var profile = try document.data(as: ManualStakerProfile.self)
        // Ensure the ID is set from the document ID if not already set
        if profile.id == nil {
            profile.id = document.documentID
        }
        return profile
    }
    
    // MARK: - Update
    func updateManualStaker(_ profile: ManualStakerProfile) async throws {
        guard let profileId = profile.id else {
            throw NSError(domain: "ManualStakerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Profile ID is required for update"])
        }
        
        var updatedProfile = profile
        updatedProfile.lastUpdatedAt = Date()
        
        try manualStakersCollectionRef.document(profileId).setData(from: updatedProfile)
        
        // Update local array
        await MainActor.run {
            if let index = manualStakers.firstIndex(where: { $0.id == profileId }) {
                manualStakers[index] = updatedProfile
                // Re-sort after update in case name changed
                manualStakers.sort { $0.name.lowercased() < $1.name.lowercased() }
            }
        }
    }
    
    // MARK: - Delete
    func deleteManualStaker(profileId: String) async throws {
        try await manualStakersCollectionRef.document(profileId).delete()
        
        // Remove from local array
        await MainActor.run {
            manualStakers.removeAll { $0.id == profileId }
        }
    }
    
    // MARK: - Search
    func searchManualStakers(query: String, userId: String) -> [ManualStakerProfile] {
        let searchQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Always filter by userId first
        let userStakers = manualStakers.filter { $0.createdByUserId == userId }
        
        guard !searchQuery.isEmpty else { return userStakers }
        
        let results = userStakers.filter { profile in
            let nameMatch = profile.name.lowercased().contains(searchQuery)
            let contactMatch = profile.contactInfo?.lowercased().contains(searchQuery) == true
            return nameMatch || contactMatch
        }
        
        return results
    }
    
    // MARK: - Check for duplicates
    func hasExistingProfile(name: String, userId: String) -> Bool {
        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return manualStakers.contains { profile in
            profile.createdByUserId == userId &&
            profile.name.lowercased() == normalizedName
        }
    }
} 