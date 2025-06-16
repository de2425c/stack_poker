import Foundation

// MARK: - Unified Challenge Display Model
/// A unified model that pre-calculates all display values for a challenge
/// This ensures consistency across all views (PostEditorView, FeedView, PostDetailView)
struct ChallengeDisplayModel {
    let challenge: Challenge
    let displayTitle: String
    let displayCurrentValue: String
    let displayTargetValue: String
    let displayProgress: Double // 0-100
    let displayRemainingValue: String
    let isCompleted: Bool
    let displayType: ChallengeType
    
    // Session-specific display values
    let sessionDisplayInfo: SessionDisplayInfo?
    
    struct SessionDisplayInfo {
        let validSessionsCount: Int
        let targetSessionCount: Int?
        let totalHoursPlayed: Double
        let targetHours: Double?
        let minHoursPerSession: Double?
        let averageHoursPerSession: Double
        let remainingSessions: Int
        let remainingHours: Double
        let isHoursBased: Bool
    }
    
    init(challenge: Challenge) {
        self.challenge = challenge
        self.displayTitle = challenge.title
        self.displayType = challenge.type
        
        // Calculate display values based on challenge type
        switch challenge.type {
        case .bankroll:
            self.displayCurrentValue = "$\(Int(challenge.currentValue).formattedWithCommas)"
            self.displayTargetValue = "$\(Int(challenge.targetValue).formattedWithCommas)"
            self.displayRemainingValue = "$\(Int(challenge.remainingValue).formattedWithCommas)"
            self.displayProgress = challenge.progressPercentage
            self.isCompleted = challenge.isCompleted
            self.sessionDisplayInfo = nil
            
        case .hands:
            self.displayCurrentValue = "\(Int(challenge.currentValue))"
            self.displayTargetValue = "\(Int(challenge.targetValue))"
            self.displayRemainingValue = "\(Int(challenge.remainingValue))"
            self.displayProgress = challenge.progressPercentage
            self.isCompleted = challenge.isCompleted
            self.sessionDisplayInfo = nil
            
        case .session:
            // Determine if this is hours-based or count-based
            // Prioritize targetSessionCount over targetHours - if both exist, it's likely a session count challenge with min hours requirement
            let isHoursBased = challenge.targetSessionCount == nil && challenge.targetHours != nil
            
            if isHoursBased {
                // Hours-based session challenge
                self.displayCurrentValue = String(format: "%.1f", challenge.totalHoursPlayed)
                self.displayTargetValue = String(format: "%.1f", challenge.targetHours ?? 0)
                self.displayRemainingValue = String(format: "%.1fh", challenge.remainingHours)
            } else {
                // Session count-based challenge (may have minimum hours per session)
                self.displayCurrentValue = "\(challenge.validSessionsCount)"
                self.displayTargetValue = "\(challenge.targetSessionCount ?? Int(challenge.targetValue))"
                self.displayRemainingValue = "\(challenge.remainingSessions) sessions"
            }
            
            self.displayProgress = challenge.sessionChallengeProgress
            self.isCompleted = challenge.isSessionChallengeCompleted
            
            self.sessionDisplayInfo = SessionDisplayInfo(
                validSessionsCount: challenge.validSessionsCount,
                targetSessionCount: challenge.targetSessionCount,
                totalHoursPlayed: challenge.totalHoursPlayed,
                targetHours: challenge.targetHours,
                minHoursPerSession: challenge.minHoursPerSession,
                averageHoursPerSession: challenge.averageHoursPerSession,
                remainingSessions: challenge.remainingSessions,
                remainingHours: challenge.remainingHours,
                isHoursBased: isHoursBased
            )
        }
    }
    
    // Create from parsed post content
    init?(from parsedInfo: (title: String, type: ChallengeType, currentValue: Double, targetValue: Double, deadline: Date?, isHoursBased: Bool?)?) {
        guard let info = parsedInfo else { return nil }
        
        // Use the unit information from parsing to determine session challenge type
        var isHoursBased = false
        if info.type == .session {
            if let unitInfo = info.isHoursBased {
                isHoursBased = unitInfo
            } else {
                // Fallback to previous heuristics if no unit info available
                let lowerTitle = info.title.lowercased()
                
                if lowerTitle.contains("hour") || lowerTitle.contains("hrs") || lowerTitle.contains("hr") {
                    isHoursBased = true
                } else if info.currentValue.truncatingRemainder(dividingBy: 1) != 0 || info.targetValue.truncatingRemainder(dividingBy: 1) != 0 {
                    isHoursBased = true
                } else if info.targetValue <= 10.0 {
                    isHoursBased = true
                } else {
                    isHoursBased = false
                }
            }
        }
        
        let targetHours = (info.type == .session && isHoursBased) ? info.targetValue : nil
        let targetSessionCount = (info.type == .session && !isHoursBased) ? Int(info.targetValue) : nil
        let totalHoursPlayed = (info.type == .session && isHoursBased) ? info.currentValue : 0
        let validSessionsCount = (info.type == .session && !isHoursBased) ? Int(info.currentValue) : 0
        
        // Create a temporary challenge object for display
        let tempChallenge = Challenge(
            userId: "",
            type: info.type,
            title: info.title,
            description: "",
            targetValue: info.targetValue,
            currentValue: info.currentValue,
            endDate: info.deadline,
            // Session-specific fields - properly set based on detection
            targetHours: targetHours,
            targetSessionCount: targetSessionCount,
            totalHoursPlayed: totalHoursPlayed,
            validSessionsCount: validSessionsCount
        )
        
        self.init(challenge: tempChallenge)
    }
    
    // Generate post content for sharing
    func generatePostContent(isStarting: Bool, userComment: String? = nil) -> String {
        let actionText = isStarting ? "🎯 Started a new challenge:" : "🎯 Challenge Update:"
        
        // Format progress and target with proper units for session challenges
        let progressText: String
        let targetText: String
        
        if challenge.type == .session, let sessionInfo = sessionDisplayInfo {
            if sessionInfo.isHoursBased {
                progressText = "\(String(format: "%.1f", sessionInfo.totalHoursPlayed)) hours"
                targetText = "\(String(format: "%.1f", sessionInfo.targetHours ?? 0)) hours"
            } else {
                progressText = "\(sessionInfo.validSessionsCount) sessions"
                targetText = "\(sessionInfo.targetSessionCount ?? 0) sessions"
            }
        } else if challenge.type == .session {
            // Fallback for session challenges without proper sessionDisplayInfo
            // Prioritize targetSessionCount over targetHours (session count challenges with min hours)
            if challenge.targetSessionCount != nil {
                progressText = "\(challenge.validSessionsCount) sessions"
                targetText = "\(challenge.targetSessionCount ?? 0) sessions"
            } else if challenge.targetHours != nil {
                progressText = "\(String(format: "%.1f", challenge.totalHoursPlayed)) hours"
                targetText = "\(String(format: "%.1f", challenge.targetHours ?? 0)) hours"
            } else {
                // Last resort: check if title matches target and is integer for session count
                if let titleAsNumber = Double(challenge.title), 
                   titleAsNumber == challenge.targetValue,
                   titleAsNumber == floor(titleAsNumber),
                   titleAsNumber >= 1 && titleAsNumber <= 100 {
                    progressText = "\(Int(challenge.currentValue)) sessions"
                    targetText = "\(Int(challenge.targetValue)) sessions"
                } else {
                    progressText = displayCurrentValue
                    targetText = displayTargetValue
                }
            }
        } else {
            progressText = displayCurrentValue
            targetText = displayTargetValue
        }
        
        var shareText = """
        \(actionText) \(displayTitle)
        
        Progress: \(progressText)
        Target: \(targetText)
        """
        
        // Add percentage for updates
        if !isStarting {
            shareText += "\n\(Int(displayProgress))% Complete"
        }
        
        // Add deadline if available
        if let deadline = challenge.endDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            shareText += "\nDeadline: \(formatter.string(from: deadline))"
        }
        
        // Add hashtags
        let hashtag = isStarting ? "#PokerChallenge" : "#ChallengeProgress"
        shareText += "\n\n\(hashtag) #\(challenge.type.rawValue.capitalized)Goal"
        
        // Add user comment if provided
        if let comment = userComment, !comment.isEmpty {
            shareText += "\n\n\(comment)"
        }
        
        return shareText
    }
    
    // Generate completion post content
    func generateCompletionPostContent() -> String {
        if challenge.type == .session, let sessionInfo = sessionDisplayInfo {
            var sessionDetails = ""
            
            if let targetCount = sessionInfo.targetSessionCount {
                sessionDetails += "\nSessions: \(sessionInfo.validSessionsCount)/\(targetCount)"
            }
            
            if let minHours = sessionInfo.minHoursPerSession {
                sessionDetails += "\nMinimum per session: \(String(format: "%.1f", minHours)) hours"
            }
            
            sessionDetails += "\nTotal hours played: \(String(format: "%.1f", sessionInfo.totalHoursPlayed))"
            sessionDetails += "\nAverage per session: \(String(format: "%.1f", sessionInfo.averageHoursPerSession)) hours"
            
            // Add proper unit-aware target/final lines for card parsing
            let targetText: String
            let finalText: String
            
            if sessionInfo.isHoursBased {
                finalText = "\(String(format: "%.1f", sessionInfo.totalHoursPlayed)) hours"
                targetText = "\(String(format: "%.1f", sessionInfo.targetHours ?? 0)) hours"
            } else {
                finalText = "\(sessionInfo.validSessionsCount) sessions"
                targetText = "\(sessionInfo.targetSessionCount ?? 0) sessions"
            }
            
            sessionDetails += "\n\nTarget: \(targetText)"
            sessionDetails += "\nFinal: \(finalText)"
            
            return """
            🎉 Session Challenge Completed!
            \(displayTitle)
            \(sessionDetails)
            
            #ChallengeCompleted #SessionGoal
            """
        } else {
            return """
            🎉 Challenge Completed!
            \(displayTitle)
            
            Target: \(displayTargetValue)
            Final: \(displayCurrentValue)
            
            #ChallengeCompleted #\(challenge.type.rawValue.capitalized)Goal
            """
        }
    }
}

// MARK: - Challenge Post Parser
/// Unified parser for challenge posts
struct ChallengePostParser {
    static func parse(_ content: String) -> ChallengeDisplayModel? {
        // Try parsing in order: completed, update, start
        if let completed = parseChallengeCompleted(content) {
            return ChallengeDisplayModel(from: completed)
        } else if let update = parseChallengeUpdate(content) {
            return ChallengeDisplayModel(from: update)
        } else if let start = parseChallengeStart(content) {
            return ChallengeDisplayModel(from: start)
        }
        return nil
    }
    
    static func extractUserComment(_ content: String) -> String? {
        let lines = content.components(separatedBy: "\n")
        var foundHashtag = false
        var commentLines: [String] = []
        
        for line in lines {
            if line.contains("#PokerChallenge") || line.contains("#ChallengeProgress") || line.contains("#ChallengeCompleted") {
                foundHashtag = true
                continue
            }
            
            if foundHashtag && !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commentLines.append(line)
            }
        }
        
        let comment = commentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return comment.isEmpty ? nil : comment
    }
    
    private static func cleanNumericString(_ raw: String) -> String {
        return raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "hours", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "hrs", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "hr", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "h", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "sessions", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "session", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func extractUnitsAndValue(from line: String, prefix: String) -> (value: Double, hasHourUnits: Bool, hasSessionUnits: Bool) {
        let content = line.replacingOccurrences(of: prefix, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercaseContent = content.lowercased()
        
        let hasHourUnits = lowercaseContent.contains("hour") || lowercaseContent.contains("hrs") || lowercaseContent.contains("hr")
        let hasSessionUnits = lowercaseContent.contains("session")
        let cleanedValue = cleanNumericString(content)
        let value = Double(cleanedValue) ?? 0
        
        return (value, hasHourUnits, hasSessionUnits)
    }
    
    private static func parseChallengeUpdate(_ content: String) -> (title: String, type: ChallengeType, currentValue: Double, targetValue: Double, deadline: Date?, isHoursBased: Bool?)? {
        guard content.contains("🎯 Challenge Update:") else { return nil }
        
        let lines = content.components(separatedBy: "\n")
        guard let firstLine = lines.first else { return nil }
        
        let title = firstLine.replacingOccurrences(of: "🎯 Challenge Update: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        var currentValue: Double = 0
        var targetValue: Double = 0
        var challengeType: ChallengeType = .bankroll
        var deadline: Date? = nil
        var hasHourUnits = false
        var hasSessionUnits = false
        
        for line in lines {
            if line.hasPrefix("Progress: ") {
                let (value, hourUnits, sessionUnits) = extractUnitsAndValue(from: line, prefix: "Progress: ")
                currentValue = value
                if hourUnits { hasHourUnits = true }
                if sessionUnits { hasSessionUnits = true }
            }
            if line.hasPrefix("Target: ") {
                let (value, hourUnits, sessionUnits) = extractUnitsAndValue(from: line, prefix: "Target: ")
                targetValue = value
                if hourUnits { hasHourUnits = true }
                if sessionUnits { hasSessionUnits = true }
            }
            if line.hasPrefix("Deadline: ") {
                let dateString = line.replacingOccurrences(of: "Deadline: ", with: "")
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                deadline = formatter.date(from: dateString)
            }
            if line.contains("#BankrollGoal") {
                challengeType = .bankroll
            } else if line.contains("#HandsGoal") {
                challengeType = .hands
            } else if line.contains("#SessionGoal") {
                challengeType = .session
            }
        }
        
        let isHoursBased = challengeType == .session ? hasHourUnits : nil
        
        return (title, challengeType, currentValue, targetValue, deadline, isHoursBased)
    }
    
    private static func parseChallengeStart(_ content: String) -> (title: String, type: ChallengeType, currentValue: Double, targetValue: Double, deadline: Date?, isHoursBased: Bool?)? {
        guard content.contains("🎯 Started a new challenge:") else { return nil }
        
        let lines = content.components(separatedBy: "\n")
        guard let firstLine = lines.first else { return nil }
        
        let title = firstLine.replacingOccurrences(of: "🎯 Started a new challenge: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        var currentValue: Double = 0
        var targetValue: Double = 0
        var challengeType: ChallengeType = .bankroll
        var deadline: Date? = nil
        var hasHourUnits = false
        var hasSessionUnits = false
        
        // Check hashtags first to determine challenge type
        for line in lines {
            if line.contains("#BankrollGoal") {
                challengeType = .bankroll
            } else if line.contains("#HandsGoal") {
                challengeType = .hands
            } else if line.contains("#SessionGoal") {
                challengeType = .session
            }
        }
        
        // Parse values and detect units
        for line in lines {
            if line.hasPrefix("Progress: ") {
                let (value, hourUnits, sessionUnits) = extractUnitsAndValue(from: line, prefix: "Progress: ")
                currentValue = value
                if hourUnits { hasHourUnits = true }
                if sessionUnits { hasSessionUnits = true }
            }
            if line.hasPrefix("Target: ") {
                let (value, hourUnits, sessionUnits) = extractUnitsAndValue(from: line, prefix: "Target: ")
                targetValue = value
                if hourUnits { hasHourUnits = true }
                if sessionUnits { hasSessionUnits = true }
            }
            if line.hasPrefix("Deadline: ") {
                let dateString = line.replacingOccurrences(of: "Deadline: ", with: "")
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                deadline = formatter.date(from: dateString)
            }
        }
        
        if targetValue == 0 { return nil }
        
        // Enhanced heuristics for session challenges when units are unclear
        if challengeType == .session && !hasHourUnits && !hasSessionUnits {
            // If title is just a number and target matches, it's likely a session count challenge
            if let titleAsNumber = Double(title), titleAsNumber == targetValue {
                // Session count challenges typically have integer targets between 1-100
                if targetValue == floor(targetValue) && targetValue >= 1 && targetValue <= 100 {
                    hasSessionUnits = true
                    hasHourUnits = false
                } else {
                    // Likely hours if it's a decimal or very small number
                    hasHourUnits = true
                    hasSessionUnits = false
                }
            } else {
                // Look at target value characteristics - improved logic
                // If target is a small integer (1-50), more likely to be session count
                // If target is decimal or very small (< 1), more likely to be hours
                if targetValue == floor(targetValue) && targetValue >= 1 && targetValue <= 50 {
                    hasSessionUnits = true
                    hasHourUnits = false
                } else if targetValue < 1.0 || targetValue.truncatingRemainder(dividingBy: 1) != 0 {
                    hasHourUnits = true
                    hasSessionUnits = false
                } else if targetValue <= 10.0 {
                    // Small numbers could be either, but lean towards hours for very small values
                    hasHourUnits = true
                    hasSessionUnits = false
                } else {
                    // Larger integers are more likely session counts
                    hasSessionUnits = true
                    hasHourUnits = false
                }
            }
        }
        
        let isHoursBased = challengeType == .session ? hasHourUnits : nil
        
        return (title, challengeType, currentValue, targetValue, deadline, isHoursBased)
    }
    
    private static func parseChallengeCompleted(_ content: String) -> (title: String, type: ChallengeType, currentValue: Double, targetValue: Double, deadline: Date?, isHoursBased: Bool?)? {
        guard content.contains("🎉 Challenge Completed") || content.contains("🎉 Session Challenge Completed") else { return nil }
        
        let lines = content.components(separatedBy: "\n")
        guard lines.count >= 2 else { return nil }
        
        // Determine title as first non-empty line after the header (line 0)
        var title = ""
        for idx in 1..<lines.count {
            let candidate = lines[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                title = candidate
                break
            }
        }
        if title.isEmpty { title = "Session Challenge" }
        // Initialize vars
        var currentValue: Double = 0
        var targetValue: Double = 0
        var challengeType: ChallengeType = .bankroll
        var hasHourUnits = false
        var hasSessionUnits = false
        var foundSessionsLine = false
        // reset parsing pointer
        
        // First pass: look for Sessions: line which is the strongest indicator
        for line in lines {
            if line.hasPrefix("Sessions:") {
                let parts = line.replacingOccurrences(of: "Sessions:", with: "").split(separator: "/")
                if parts.count == 2 {
                    let cur = cleanNumericString(String(parts[0]))
                    let tgt = cleanNumericString(String(parts[1]))
                    let curValue = Double(cur) ?? 0
                    let tgtValue = Double(tgt) ?? 0
                    
                    // Use sessions line as primary source
                    if tgtValue > 0 {
                        currentValue = curValue
                        targetValue = tgtValue
                        challengeType = .session
                        hasSessionUnits = true
                        foundSessionsLine = true
                        break // Stop here if we found sessions line
                    }
                }
            }
        }
        
        // If no Sessions: line found, look for other indicators
        if !foundSessionsLine {
            // Look for explicit hour indicators in content
            for line in lines {
                if line.lowercased().contains("hour") || line.lowercased().contains("hrs") || line.lowercased().contains("hr") {
                    hasHourUnits = true
                    challengeType = .session
                }
            }
            
            // Check title for hour indicators
            if title.lowercased().contains("hour") || title.lowercased().contains("hrs") || title.lowercased().contains("hr") {
                hasHourUnits = true
                challengeType = .session
            }
            
            // Parse Final/Target values
            for line in lines {
                if line.hasPrefix("Final:") {
                    let (value, hourUnits, sessionUnits) = extractUnitsAndValue(from: line, prefix: "Final:")
                    currentValue = value
                    if hourUnits { hasHourUnits = true }
                    if sessionUnits { hasSessionUnits = true }
                }
                if line.hasPrefix("Target:") {
                    let (value, hourUnits, sessionUnits) = extractUnitsAndValue(from: line, prefix: "Target:")
                    targetValue = value
                    if hourUnits { hasHourUnits = true }
                    if sessionUnits { hasSessionUnits = true }
                }
                // Look for total hours played line as strong indicator
                if line.lowercased().hasPrefix("total hours played:") {
                    let cleaned = cleanNumericString(line.replacingOccurrences(of: "Total hours played:", with: "", options: .caseInsensitive))
                    currentValue = Double(cleaned) ?? currentValue
                    challengeType = .session
                    hasHourUnits = true
                }
                if line.contains("#BankrollGoal") {
                    challengeType = .bankroll
                } else if line.contains("#HandsGoal") {
                    challengeType = .hands
                } else if line.contains("#SessionGoal") {
                    challengeType = .session
                }
            }
            
            // Additional heuristics for detecting hours-based challenges
            if challengeType == .session && !hasHourUnits && !hasSessionUnits {
                // If target is small (typically <= 10 for hours) and current/target have decimals, likely hours
                if targetValue <= 10.0 || currentValue.truncatingRemainder(dividingBy: 1) != 0 || targetValue.truncatingRemainder(dividingBy: 1) != 0 {
                    hasHourUnits = true
                }
            }
        }
        
        if targetValue == 0 { targetValue = currentValue }
        
        // For completed challenges, force currentValue to equal targetValue to visually represent completion
        currentValue = targetValue
        
        // For session challenges, determine if hours-based (but prioritize sessions line)
        let isHoursBased = challengeType == .session ? (foundSessionsLine ? false : hasHourUnits) : nil
        
        return (title, challengeType, currentValue, targetValue, nil, isHoursBased)
    }
} 