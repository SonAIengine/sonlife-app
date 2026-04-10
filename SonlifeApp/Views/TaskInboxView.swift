import SwiftUI

/// Phase A+ — 작업 인박스 (메인 화면).
///
/// 3 섹션으로 에이전트 작업 상태를 한 화면에 표시:
/// - 승인 대기: HITL pending (`/api/approvals/pending`)
/// - 진행 중: running + 각 세션에 SSE 라이브 스트림 (B: 폴링 → 실시간)
/// - 완료: completed / failed / rejected 통합, 실패는 빨간색으로 구분
///
/// 실시간 전략 (B):
/// - 5초 폴링으로 목록 동기화 (fallback)
/// - 새로 나타난 running 세션에 SSE 스트림 자동 open
/// - 세션 종료 이벤트(completed/failed/suspended) 수신 시 즉시 loadAll()
///
/// 상단 바:
/// - 왼쪽 햄버거: 하위 메뉴 (LifeLog / 녹음 / 대시보드 / 설정)
/// - 오른쪽 +: 새 명령 입력
struct TaskInboxView: View {
    @Bindable var recorder: AudioRecorder

    @State private var pendingApprovals: [ApprovalDetail] = []
    @State private var runningSessions: [OrchestratorSession] = []
    @State private var doneSessions: [OrchestratorSession] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var showingCommandInput = false
    @State private var showingMenu = false
    @State private var showingSkillPicker = false
    @State private var selectedApproval: ApprovalDetail?
    @State private var selectedSession: OrchestratorSession?

    // B: 라이브 상태 — session_id → 최신 이벤트 정보
    @State private var liveStates: [String: LiveSessionState] = [:]
    @State private var streamTasks: [String: Task<Void, Never>] = [:]

    var body: some View {
        List {
            if !pendingApprovals.isEmpty {
                Section {
                    ForEach(pendingApprovals) { approval in
                        Button {
                            selectedApproval = approval
                        } label: {
                            PendingApprovalRow(approval: approval)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    InboxSectionHeader(
                        icon: "hourglass.circle.fill",
                        color: .orange,
                        title: "승인 대기",
                        count: pendingApprovals.count
                    )
                }
            }

            if !runningSessions.isEmpty {
                Section {
                    ForEach(runningSessions) { session in
                        Button {
                            selectedSession = session
                        } label: {
                            InboxSessionRow(session: session, liveState: liveStates[session.id])
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    InboxSectionHeader(
                        icon: "circle.dotted",
                        color: .blue,
                        title: "진행 중",
                        count: runningSessions.count
                    )
                }
            }

            Section {
                if doneSessions.isEmpty {
                    HStack {
                        Spacer()
                        Text(isLoading ? "불러오는 중..." : "완료된 작업이 없습니다")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(doneSessions) { session in
                        Button {
                            selectedSession = session
                        } label: {
                            InboxSessionRow(session: session, liveState: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                InboxSectionHeader(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    title: "완료",
                    count: doneSessions.count
                )
            }

            if let error = errorMessage, pendingApprovals.isEmpty, runningSessions.isEmpty, doneSessions.isEmpty {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("작업")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingMenu = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .imageScale(.large)
                }
                .accessibilityLabel("메뉴")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingCommandInput = true
                    } label: {
                        Label("텍스트 명령", systemImage: "text.bubble")
                    }
                    Button {
                        showingSkillPicker = true
                    } label: {
                        Label("스킬 실행", systemImage: "sparkles")
                    }
                } label: {
                    Image(systemName: "plus")
                        .imageScale(.large)
                }
                .accessibilityLabel("새 작업")
            }
        }
        .refreshable {
            await loadAll()
        }
        .task {
            // 5초 폴링: 진행 중 세션 라이브 업데이트. 뷰 이탈 시 Task 자동 취소.
            while !Task.isCancelled {
                await loadAll()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .sheet(isPresented: $showingCommandInput) {
            CommandInputView()
        }
        .sheet(isPresented: $showingSkillPicker) {
            SkillPickerView()
        }
        .sheet(isPresented: $showingMenu) {
            InboxMenuSheet(recorder: recorder)
        }
        .sheet(item: $selectedApproval) { approval in
            ApprovalSheetView(approval: approval) {
                selectedApproval = nil
                Task { await loadAll() }
            }
        }
        .sheet(item: $selectedSession) { session in
            OrchestratorSessionDetailSheet(session: session)
        }
    }

    @MainActor
    private func loadAll() async {
        do {
            async let pending = OrchestratorAPI.fetchPendingApprovals()
            async let sessions = OrchestratorAPI.fetchSessions(limit: 50)
            let (p, s) = try await (pending, sessions)
            pendingApprovals = p
            runningSessions = s.filter { $0.status == .running }
            doneSessions = s.filter {
                $0.status == .completed || $0.status == .failed || $0.status == .rejected
            }
            errorMessage = nil

            // B: 진행 중 세션의 SSE 스트림 관리 — 새로 생긴 세션에 open, 없어진 세션에 cancel
            syncStreams()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - B: SSE 스트림 diff 동기화

    @MainActor
    private func syncStreams() {
        let currentIds = Set(runningSessions.map { $0.id })

        // 새로 나타난 세션에 스트림 open
        for sid in currentIds where streamTasks[sid] == nil {
            openStream(for: sid)
        }

        // 더 이상 진행 중이 아닌 세션의 스트림 종료
        for (sid, task) in streamTasks where !currentIds.contains(sid) {
            task.cancel()
            streamTasks.removeValue(forKey: sid)
            liveStates.removeValue(forKey: sid)
        }
    }

    private func openStream(for sessionId: String) {
        let task = Task { @MainActor in
            do {
                for try await event in OrchestratorAPI.sessionEventStream(sessionId: sessionId) {
                    if Task.isCancelled { break }
                    ingestEvent(event, sessionId: sessionId)
                    if isTerminalEvent(event.type) {
                        await loadAll()   // 목록 즉시 refresh
                        break
                    }
                }
            } catch {
                // 스트림 실패는 폴링이 커버함 — silent
            }
        }
        streamTasks[sessionId] = task
    }

    private func ingestEvent(_ event: SSEClient.Event, sessionId: String) {
        var state = liveStates[sessionId] ?? LiveSessionState()
        state.eventCount += 1

        // 서버 payload 구조: {"type": "...", "data": {...}}
        let inner = event.data["data"] as? [String: Any] ?? event.data

        switch event.type {
        case "tool.called":
            state.lastToolName = inner["tool_name"] as? String
            state.currentStep = inner["step"] as? Int ?? state.currentStep
            state.lastEventType = "tool.called"
            state.phase = "\(state.lastToolName ?? "tool") 호출 중"
        case "tool.completed":
            state.lastToolName = inner["tool_name"] as? String
            state.currentStep = inner["step"] as? Int ?? state.currentStep
            state.lastEventType = "tool.completed"
            state.phase = "\(state.lastToolName ?? "tool") 완료"
        case "tool.failed":
            state.lastEventType = "tool.failed"
            state.phase = "도구 실패"
        case "session.started":
            state.lastEventType = "session.started"
            state.phase = "시작됨"
        case "session.completed":
            state.lastEventType = "session.completed"
            state.phase = "완료"
        case "session.failed":
            state.lastEventType = "session.failed"
            state.phase = "실패"
        case "session.suspended":
            state.lastEventType = "session.suspended"
            state.phase = "승인 대기"
        default:
            break
        }
        liveStates[sessionId] = state
    }

    private func isTerminalEvent(_ type: String) -> Bool {
        type == "session.completed" || type == "session.failed"
            || type == "session.suspended" || type == "end"
    }
}

// MARK: - B: 라이브 세션 상태

struct LiveSessionState: Equatable {
    var lastEventType: String = ""
    var lastToolName: String? = nil
    var currentStep: Int = 0
    var eventCount: Int = 0
    var phase: String = ""
}

// MARK: - Section header

private struct InboxSectionHeader: View {
    let icon: String
    let color: Color
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .textCase(nil)
    }
}

// MARK: - Pending approval row

private struct PendingApprovalRow: View {
    let approval: ApprovalDetail

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(approval.toolName)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    PermissionBadge(permission: approval.preview.permission)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 2)
    }

    private var titleText: String {
        if let summary = approval.preview.summary, !summary.isEmpty {
            return summary
        }
        if let subject = approval.args.subject, !subject.isEmpty {
            return subject
        }
        return approval.toolName
    }
}

// MARK: - Permission badge (L03)

struct PermissionBadge: View {
    let permission: String?

    var body: some View {
        if let p = permission, !p.isEmpty {
            Text(label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.2))
                .foregroundStyle(color)
                .clipShape(Capsule())
        } else {
            EmptyView()
        }
    }

    private var label: String {
        switch permission {
        case "read_only": return "읽기"
        case "draft_only": return "초안"
        case "auto_execute": return "자동"
        case "requires_approval": return "승인"
        default: return permission ?? ""
        }
    }

    private var color: Color {
        switch permission {
        case "read_only": return .blue
        case "draft_only": return .indigo
        case "auto_execute": return .teal
        case "requires_approval": return .red
        default: return .secondary
        }
    }
}

// MARK: - Session row (진행 중 / 완료 공통)

private struct InboxSessionRow: View {
    let session: OrchestratorSession
    let liveState: LiveSessionState?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 28)
                .symbolEffect(.pulse, options: .repeating, isActive: isLive)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(titleText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if session.hasSubAgent {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                            .accessibilityLabel("격리 실행")
                    }
                    if session.parentSessionId != nil {
                        Text("sub")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text(session.agentName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    if let live = liveState, !live.phase.isEmpty, session.status == .running {
                        // 라이브 상태 우선 표시
                        Text(live.phase)
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                        if live.currentStep > 0 {
                            Text("#\(live.currentStep)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Text(session.statusDisplay)
                            .font(.caption)
                            .foregroundStyle(statusColor)
                    }
                    Spacer()
                    Text(formattedDate)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var isLive: Bool {
        session.status == .running && liveState != nil
    }

    private var iconName: String {
        if isLive {
            return "dot.radiowaves.left.and.right"
        }
        return session.statusIcon
    }

    private var titleText: String {
        if let prompt = session.prompt, !prompt.isEmpty {
            return prompt
        }
        if let result = session.result, !result.isEmpty {
            return result
        }
        return session.agentName
    }

    private var statusColor: Color {
        switch session.status {
        case .running: return .blue
        case .pendingHITL: return .orange
        case .completed: return .green
        case .failed: return .red
        case .rejected: return .gray
        }
    }

    private var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: session.startedAt)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: session.startedAt)
        }
        guard let date else { return String(session.startedAt.prefix(16)) }
        let display = DateFormatter()
        display.dateFormat = "MM/dd HH:mm"
        return display.string(from: date)
    }
}

// MARK: - Menu sheet (하위 메뉴)

private struct InboxMenuSheet: View {
    @Bindable var recorder: AudioRecorder
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("입력") {
                    NavigationLink {
                        LifeLogView(recorder: recorder)
                    } label: {
                        Label("LifeLog", systemImage: "waveform.path.ecg")
                    }
                    NavigationLink {
                        ManualRecordingView(recorder: recorder)
                    } label: {
                        Label("녹음", systemImage: "mic")
                    }
                }

                Section("에이전트") {
                    NavigationLink {
                        BudgetView()
                    } label: {
                        Label("예산 · 사용량", systemImage: "dollarsign.circle")
                    }
                    NavigationLink {
                        AgentDashboardView()
                    } label: {
                        Label("대시보드", systemImage: "chart.bar.xaxis")
                    }
                    NavigationLink {
                        OrchestratorSessionHistoryView()
                    } label: {
                        Label("실행 기록 전체", systemImage: "clock.arrow.circlepath")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("설정", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("메뉴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
