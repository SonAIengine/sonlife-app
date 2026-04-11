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
    let permission: String?  // L03 권한 등급 (read_only/draft_only/requires_approval/auto_execute)
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
    let hasSubAgent: Bool    // L07 격리 실행 존재 여부
    let parentSessionId: String?
    let origin: String       // "user" | "autonomous" — Phase D 자율 루프
    let triggerSource: String?    // 자율 세션이면 "email" / "teams" / "calendar"
    let triggerEventId: String?   // lifelog source_id 추적

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
        case hasSubAgent = "has_sub_agent"
        case parentSessionId = "parent_session_id"
        case origin
        case triggerSource = "trigger_source"
        case triggerEventId = "trigger_event_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        agentName = try c.decode(String.self, forKey: .agentName)
        triggeredBy = try c.decode(String.self, forKey: .triggeredBy)
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
        status = try c.decode(PhaseASessionStatus.self, forKey: .status)
        result = try c.decodeIfPresent(String.self, forKey: .result)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        pendingToken = try c.decodeIfPresent(String.self, forKey: .pendingToken)
        startedAt = try c.decode(String.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(String.self, forKey: .endedAt)
        usage = try c.decodeIfPresent(SessionUsage.self, forKey: .usage)
        hasSubAgent = try c.decodeIfPresent(Bool.self, forKey: .hasSubAgent) ?? false
        parentSessionId = try c.decodeIfPresent(String.self, forKey: .parentSessionId)
        origin = try c.decodeIfPresent(String.self, forKey: .origin) ?? "user"
        triggerSource = try c.decodeIfPresent(String.self, forKey: .triggerSource)
        triggerEventId = try c.decodeIfPresent(String.self, forKey: .triggerEventId)
    }

    var isAutonomous: Bool { origin == "autonomous" }

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

// MARK: - Session Detail (tool calls)

struct SessionToolCall: Codable, Identifiable {
    let id: Int
    let sessionId: String
    let stepIndex: Int?
    let toolName: String
    let status: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case stepIndex = "step_index"
        case toolName = "tool_name"
        case status
        case createdAt = "created_at"
    }

    var isSubAgent: Bool { status == "sub_agent" }
    var isAutoCompact: Bool { toolName == "_auto_compact" }
}

struct SessionDetailResponse: Codable {
    let session: OrchestratorSession
    let toolCalls: [SessionToolCall]

    enum CodingKeys: String, CodingKey {
        case session
        case toolCalls = "tool_calls"
    }
}

// MARK: - L09 Skills

struct SkillArg: Codable, Identifiable {
    let name: String
    let description: String
    let required: Bool
    let defaultValue: String?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case required
        case defaultValue = "default"
    }
}

struct Skill: Codable, Identifiable {
    let name: String
    let description: String
    let args: [SkillArg]

    var id: String { name }
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
    let totalTokens: Int
    let reasoningTokens: Int
    let costUsd: Double
    let runs: Int
    let toolCalls: Int
    let delegatedTasks: Int

    var id: String { "\(date)-\(agentName)" }

    enum CodingKeys: String, CodingKey {
        case date
        case agentName = "agent_name"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case reasoningTokens = "reasoning_tokens"
        case costUsd = "cost_usd"
        case runs
        case toolCalls = "tool_calls"
        case delegatedTasks = "delegated_tasks"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        agentName = try c.decode(String.self, forKey: .agentName)
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        reasoningTokens = try c.decodeIfPresent(Int.self, forKey: .reasoningTokens) ?? 0
        costUsd = try c.decodeIfPresent(Double.self, forKey: .costUsd) ?? 0.0
        runs = try c.decodeIfPresent(Int.self, forKey: .runs) ?? 0
        toolCalls = try c.decodeIfPresent(Int.self, forKey: .toolCalls) ?? 0
        delegatedTasks = try c.decodeIfPresent(Int.self, forKey: .delegatedTasks) ?? 0
    }
}
