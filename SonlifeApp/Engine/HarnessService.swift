import Foundation

// MARK: - Models

struct HarnessStats: Codable {
    let totalNodes: Int
    let kindSession: Int
    let kindToolCall: Int
    let kindObservation: Int
    let kindLesson: Int
    let kindConcept: Int
    let cacheHitRate: Double
    let cacheSize: Int

    enum CodingKeys: String, CodingKey {
        case totalNodes = "total_nodes"
        case kindSession = "kind_session"
        case kindToolCall = "kind_tool_call"
        case kindObservation = "kind_observation"
        case kindLesson = "kind_lesson"
        case kindConcept = "kind_concept"
        case cacheHitRate = "cache_hit_rate"
        case cacheSize = "cache_size"
    }
}

struct AgentSession: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let agentId: String
    let createdAt: Double
    let updatedAt: Double?
    let successCount: Int
    let failureCount: Int

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case agentId = "agent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case successCount = "success_count"
        case failureCount = "failure_count"
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt)
    }

    var agentDisplayName: String {
        if agentId.starts(with: "collector:") {
            return agentId.replacingOccurrences(of: "collector:", with: "")
                .capitalized + " 수집"
        }
        return agentId.replacingOccurrences(of: "agent:", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var agentIcon: String {
        switch agentId {
        case let id where id.contains("github"): return "cat"
        case let id where id.contains("gitlab"): return "shippingbox"
        case let id where id.contains("kakao"): return "message"
        case let id where id.contains("ms365"), let id where id.contains("outlook"): return "envelope"
        case let id where id.contains("summary"): return "doc.text.magnifyingglass"
        case let id where id.contains("teams"): return "person.3"
        case let id where id.contains("calendar"): return "calendar"
        default: return "gearshape.2"
        }
    }
}

struct AgentSessionDetail: Codable {
    let id: String
    let title: String
    let description: String
    let agentId: String
    let createdAt: Double
    let successCount: Int
    let failureCount: Int
    let timeline: [TimelineEvent]

    enum CodingKeys: String, CodingKey {
        case id, title, description, timeline
        case agentId = "agent_id"
        case createdAt = "created_at"
        case successCount = "success_count"
        case failureCount = "failure_count"
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt)
    }
}

struct TimelineEvent: Codable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let content: String
    let createdAt: Double

    enum CodingKeys: String, CodingKey {
        case id, kind, title, content
        case createdAt = "created_at"
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt)
    }

    var kindIcon: String {
        switch kind {
        case "tool_call": return "wrench.and.screwdriver"
        case "observation": return "eye"
        case "session": return "play.circle"
        default: return "circle"
        }
    }
}

struct FeedbackLesson: Codable, Identifiable {
    let id: String
    let title: String
    let content: String
    let tags: [String]
    let sessionId: String
    let rating: String?
    let createdAt: Double

    enum CodingKeys: String, CodingKey {
        case id, title, content, tags, rating
        case sessionId = "session_id"
        case createdAt = "created_at"
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt)
    }

    var ratingIcon: String {
        switch rating {
        case "good": return "hand.thumbsup.fill"
        case "bad": return "hand.thumbsdown.fill"
        default: return "minus.circle"
        }
    }

    var ratingColor: String {
        switch rating {
        case "good": return "green"
        case "bad": return "red"
        default: return "secondary"
        }
    }
}

// MARK: - Service

enum HarnessService {
    static var serverURL: String {
        ChunkUploader.shared.currentServerURL
    }

    static func fetchStats() async throws -> HarnessStats {
        let data = try await get("api/harness/stats")
        return try JSONDecoder().decode(HarnessStats.self, from: data)
    }

    static func fetchSessions(limit: Int = 30, agentId: String? = nil) async throws -> [AgentSession] {
        var path = "api/harness/sessions?limit=\(limit)"
        if let agentId {
            path += "&agent_id=\(agentId)"
        }
        let data = try await get(path)
        struct Response: Codable { let sessions: [AgentSession]; let total: Int }
        return try JSONDecoder().decode(Response.self, from: data).sessions
    }

    static func fetchSessionDetail(id: String) async throws -> AgentSessionDetail {
        let data = try await get("api/harness/sessions/\(id)")
        return try JSONDecoder().decode(AgentSessionDetail.self, from: data)
    }

    static func fetchFeedback(limit: Int = 20) async throws -> [FeedbackLesson] {
        let data = try await get("api/harness/feedback?limit=\(limit)")
        struct Response: Codable { let lessons: [FeedbackLesson]; let total: Int }
        return try JSONDecoder().decode(Response.self, from: data).lessons
    }

    // MARK: - Private

    private static func get(_ path: String) async throws -> Data {
        guard let url = URL(string: serverURL)?.appendingPathComponent(path) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
