import SwiftUI

/// Phase A+ — 작업 인박스 (메인 화면).
///
/// 3 섹션으로 에이전트 작업 상태를 한 화면에 표시:
/// - 승인 대기: HITL pending (`/api/approvals/pending`)
/// - 진행 중: running (5초 폴링)
/// - 완료: completed / failed / rejected 통합, 실패는 빨간색으로 구분
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
    @State private var selectedApproval: ApprovalDetail?
    @State private var selectedSession: OrchestratorSession?

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
                            InboxSessionRow(session: session)
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
                            InboxSessionRow(session: session)
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
                Button {
                    showingCommandInput = true
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
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
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
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("컨펌 필요")
                        .font(.caption)
                        .foregroundStyle(.orange)
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

// MARK: - Session row (진행 중 / 완료 공통)

private struct InboxSessionRow: View {
    let session: OrchestratorSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.statusIcon)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(session.agentName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(session.statusDisplay)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                    Spacer()
                    Text(formattedDate)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
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
