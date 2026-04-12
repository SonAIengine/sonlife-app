import Foundation

// MARK: - D3: Watch Orchestrator API (minimal, standalone)
//
// WatchKit에서 사용할 최소 API 클라이언트.
// 메인 앱의 OrchestratorAPI와 동일 엔드포인트를 사용하되,
// Watch 독립 실행을 위해 자체 네트워크 레이어를 갖는다.

enum WatchOrchestratorAPI {

    /// App Group UserDefaults에서 서버 URL 로드
    static var serverURL: String {
        let defaults = UserDefaults(suiteName: "group.com.sonaiengine.sonlifeapp")
        return defaults?.string(forKey: "stt_server_url") ?? "http://14.6.220.78:8101"
    }

    // MARK: - Pending Approvals

    struct PendingResponse: Codable {
        let pending: [WatchApproval]
        let total: Int
    }

    struct WatchApproval: Codable, Identifiable {
        let token: String
        let toolName: String
        let preview: WatchPreview
        let createdAt: String

        var id: String { token }

        enum CodingKeys: String, CodingKey {
            case token
            case toolName = "tool_name"
            case preview
            case createdAt = "created_at"
        }

        var displayTitle: String {
            preview.summary ?? toolName
        }

        var toolDisplayName: String {
            switch toolName {
            case "send_teams_message": return "Teams"
            case "email_send": return "이메일"
            case "email_compose_draft": return "이메일 초안"
            case "calendar_create_event": return "일정"
            case "commit_and_push": return "Git Push"
            default: return toolName
            }
        }
    }

    struct WatchPreview: Codable {
        let tool: String?
        let agent: String?
        let summary: String?
    }

    static func fetchPendingApprovals() async throws -> [WatchApproval] {
        let data = try await get("api/approvals/pending")
        return try JSONDecoder().decode(PendingResponse.self, from: data).pending
    }

    // MARK: - Approve / Reject

    struct ApprovalBody: Codable {
        let decision: String
        let reason: String?
    }

    struct ApprovalResponse: Codable {
        let status: String
    }

    static func approve(token: String) async throws {
        let body = ApprovalBody(decision: "approve", reason: nil)
        _ = try await post("api/approval/\(token)", body: body)
    }

    static func reject(token: String, reason: String = "Watch에서 거절") async throws {
        let body = ApprovalBody(decision: "reject", reason: reason)
        _ = try await post("api/approval/\(token)", body: body)
    }

    // MARK: - Private

    private static func get(_ path: String) async throws -> Data {
        let base = serverURL.hasSuffix("/") ? serverURL : serverURL + "/"
        guard let url = URL(string: base + path) else {
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

    private static func post<T: Encodable>(_ path: String, body: T) async throws -> Data {
        let base = serverURL.hasSuffix("/") ? serverURL : serverURL + "/"
        guard let url = URL(string: base + path) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
