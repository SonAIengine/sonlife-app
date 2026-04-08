import Foundation

// MARK: - Phase A Orchestrator Models
//
// 백엔드 src/orchestrator/* + src/harness/* 의 API 응답에 대응.
// 기존 HarnessService.AgentSession 과는 별도 스키마.

enum PhaseASessionStatus: String, Codable {
    case running
    case pendingHITL = "pending_hitl"
    case completed
    case failed
    case rejected
}

// MARK: - Command Dispatch

struct CommandRequest: Codable {
    let input: String
    let inputType: String
    let source: String
    let urgency: String

    enum CodingKeys: String, CodingKey {
        case input
        case inputType = "input_type"
        case source
        case urgency
    }
}

struct CommandResponse: Codable {
    let commandId: String
    let status: PhaseASessionStatus
    let pendingToken: String?
    let preview: ApprovalPreview?
    let result: CommandResult?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case commandId = "command_id"
        case status
        case pendingToken = "pending_token"
        case preview
        case result
        case error
    }
}

struct CommandResult: Codable {
    let summary: String?
    let draft: EmailDraft?
    let sendResult: SendResult?

    enum CodingKeys: String, CodingKey {
        case summary
        case draft
        case sendResult = "send_result"
    }
}

struct SendResult: Codable {
    let status: String
    let to: String?
    let subject: String?
}

// MARK: - Approval

struct ApprovalPreview: Codable {
    let tool: String?
    let agent: String?
    let summary: String?
    let args: ApprovalArgs?
}

struct ApprovalArgs: Codable {
    let to: String?
    let subject: String?
    let body: String?
}

struct ApprovalDetail: Codable, Identifiable {
    let token: String
    let sessionId: String
    let toolName: String
    let args: ApprovalArgs
    let preview: ApprovalPreview
    let decision: String
    let createdAt: String
    let resolvedAt: String?

    var id: String { token }

    enum CodingKeys: String, CodingKey {
        case token
        case sessionId = "session_id"
        case toolName = "tool_name"
        case args
        case preview
        case decision
        case createdAt = "created_at"
        case resolvedAt = "resolved_at"
    }
}

struct ApprovalRequest: Codable {
    let decision: String  // "approve" | "reject" | "modify"
    let modifiedArgs: ApprovalArgs?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case decision
        case modifiedArgs = "modified_args"
        case reason
    }
}

// MARK: - Email Draft (구조화)

struct EmailDraft: Codable {
    let to: String
    let subject: String
    let body: String
}

// MARK: - Phase A Session (orchestrator)

struct OrchestratorSession: Codable, Identifiable {
    let id: String
    let agentName: String
    let triggeredBy: String
    let prompt: String?
    let status: PhaseASessionStatus
    let result: String?
    let error: String?
    let pendingToken: String?
    let startedAt: String
    let endedAt: String?
    let usage: SessionUsage?

    enum CodingKeys: String, CodingKey {
        case id
        case agentName = "agent_name"
        case triggeredBy = "triggered_by"
        case prompt
        case status
        case result
        case error
        case pendingToken = "pending_token"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case usage
    }

    var statusDisplay: String {
        switch status {
        case .running: return "실행 중"
        case .pendingHITL: return "승인 대기"
        case .completed: return "완료"
        case .failed: return "실패"
        case .rejected: return "거절됨"
        }
    }

    var statusIcon: String {
        switch status {
        case .running: return "circle.dotted"
        case .pendingHITL: return "hourglass"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .rejected: return "minus.circle.fill"
        }
    }
}

struct SessionUsage: Codable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Budget

struct BudgetSummary: Codable {
    let agents: [AgentBudgetUsage]
    let globalCostUsd: Double

    enum CodingKeys: String, CodingKey {
        case agents
        case globalCostUsd = "global_cost_usd"
    }
}

struct AgentBudgetUsage: Codable, Identifiable {
    let date: String
    let agentName: String
    let inputTokens: Int
    let outputTokens: Int
    let costUsd: Double
    let runs: Int

    var id: String { "\(date)-\(agentName)" }

    enum CodingKeys: String, CodingKey {
        case date
        case agentName = "agent_name"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case costUsd = "cost_usd"
        case runs
    }
}
