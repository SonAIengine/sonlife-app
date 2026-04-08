import Foundation

/// Phase A Orchestrator API client.
///
/// Endpoints (백엔드 src/server.py):
/// - POST /api/command           : 자연어 명령 발행
/// - POST /api/approval/{token}  : HITL 승인/거절/수정
/// - GET  /api/approvals/{token} : 승인 요청 상세
/// - GET  /api/sessions          : 최근 에이전트 실행 기록
/// - GET  /api/sessions/{id}     : 세션 상세
/// - GET  /api/budget            : 오늘의 비용/사용량
enum OrchestratorAPI {

    static var serverURL: String {
        ChunkUploader.shared.currentServerURL
    }

    // MARK: - Command

    static func dispatch(input: String) async throws -> CommandResponse {
        let body = CommandRequest(
            input: input,
            inputType: "text",
            source: "ios_app",
            urgency: "normal"
        )
        return try await post("api/command", body: body)
    }

    // MARK: - Approval

    static func fetchApproval(token: String) async throws -> ApprovalDetail {
        let data = try await get("api/approvals/\(token)")
        return try jsonDecoder().decode(ApprovalDetail.self, from: data)
    }

    static func approve(
        token: String,
        modifiedArgs: ApprovalArgs? = nil
    ) async throws -> CommandResponse {
        let body = ApprovalRequest(
            decision: modifiedArgs == nil ? "approve" : "modify",
            modifiedArgs: modifiedArgs,
            reason: nil
        )
        return try await post("api/approval/\(token)", body: body)
    }

    static func reject(token: String, reason: String?) async throws -> CommandResponse {
        let body = ApprovalRequest(
            decision: "reject",
            modifiedArgs: nil,
            reason: reason
        )
        return try await post("api/approval/\(token)", body: body)
    }

    // MARK: - Sessions

    static func fetchSessions(limit: Int = 30) async throws -> [OrchestratorSession] {
        let data = try await get("api/sessions?limit=\(limit)")
        struct Response: Codable {
            let sessions: [OrchestratorSession]
            let total: Int
        }
        return try jsonDecoder().decode(Response.self, from: data).sessions
    }

    // MARK: - Budget

    static func fetchBudget() async throws -> BudgetSummary {
        let data = try await get("api/budget")
        return try jsonDecoder().decode(BudgetSummary.self, from: data)
    }

    // MARK: - Pending approvals (대기 중)

    static func fetchPendingApprovals() async throws -> [ApprovalDetail] {
        let data = try await get("api/approvals/pending")
        struct Response: Codable {
            let pending: [ApprovalDetail]
            let total: Int
        }
        return try jsonDecoder().decode(Response.self, from: data).pending
    }

    // MARK: - Private

    private static func get(_ path: String) async throws -> Data {
        guard let url = URL(string: serverURL)?.appendingPathComponent(path) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func post<T: Encodable>(_ path: String, body: T) async throws -> CommandResponse {
        guard let url = URL(string: serverURL)?.appendingPathComponent(path) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode != 200 {
            // 에러 메시지 추출 시도
            let snippet = String(data: data, encoding: .utf8) ?? "(no body)"
            throw NSError(
                domain: "OrchestratorAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(snippet.prefix(200))"]
            )
        }
        return try jsonDecoder().decode(CommandResponse.self, from: data)
    }

    private static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // PhaseA 모델은 자체 CodingKeys 사용 — keyDecodingStrategy 미적용
        return decoder
    }
}
