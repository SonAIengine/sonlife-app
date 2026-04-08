import SwiftUI

struct AgentDashboardView: View {
    @State private var stats: HarnessStats?
    @State private var sessions: [AgentSession] = []
    @State private var lessons: [FeedbackLesson] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTab: DashboardTab = .sessions
    @State private var showingCommandInput = false

    enum DashboardTab: String, CaseIterable {
        case sessions = "세션"
        case feedback = "피드백"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Phase A — 명령 발행 버튼
                Button {
                    showingCommandInput = true
                } label: {
                    HStack {
                        Image(systemName: "text.bubble.fill")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("에이전트 명령")
                                .font(.subheadline.weight(.semibold))
                            Text("자연어로 작업 위임 (메일, 코드, 리서치...)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue.opacity(0.15), .purple.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    }
                    .foregroundStyle(.primary)
                }
                .padding(.horizontal)

                // Stats cards
                if let stats {
                    statsSection(stats)
                }

                // Tab picker
                Picker("탭", selection: $selectedTab) {
                    ForEach(DashboardTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Content
                switch selectedTab {
                case .sessions:
                    sessionsSection
                case .feedback:
                    feedbackSection
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("에이전트")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .overlay {
            if isLoading && stats == nil {
                ProgressView("로딩 중...")
            }
        }
        .task { await loadAll() }
        .sheet(isPresented: $showingCommandInput) {
            CommandInputView()
        }
    }

    // MARK: - Stats

    private func statsSection(_ stats: HarnessStats) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                StatCard(
                    icon: "brain.head.profile",
                    title: "메모리",
                    value: "\(stats.totalNodes)",
                    subtitle: "전체 노드"
                )
                StatCard(
                    icon: "play.circle",
                    title: "세션",
                    value: "\(stats.kindSession)",
                    subtitle: "실행 기록"
                )
            }

            HStack(spacing: 12) {
                StatCard(
                    icon: "wrench.and.screwdriver",
                    title: "도구 호출",
                    value: "\(stats.kindToolCall)",
                    subtitle: "tool calls"
                )
                StatCard(
                    icon: "lightbulb",
                    title: "학습",
                    value: "\(stats.kindLesson)",
                    subtitle: "lessons"
                )
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        LazyVStack(spacing: 0) {
            if sessions.isEmpty && !isLoading {
                ContentUnavailableView(
                    "세션 없음",
                    systemImage: "tray",
                    description: Text("에이전트 실행 기록이 없습니다")
                )
                .padding(.top, 40)
            }
            ForEach(sessions) { session in
                NavigationLink {
                    AgentSessionDetailView(sessionId: session.id)
                } label: {
                    AgentSessionRow(session: session)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 56)
            }
        }
    }

    // MARK: - Feedback

    private var feedbackSection: some View {
        LazyVStack(spacing: 0) {
            if lessons.isEmpty && !isLoading {
                ContentUnavailableView(
                    "피드백 없음",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("아직 피드백 기록이 없습니다")
                )
                .padding(.top, 40)
            }
            ForEach(lessons) { lesson in
                FeedbackRow(lesson: lesson)
                Divider().padding(.leading, 56)
            }
        }
    }

    // MARK: - Load

    private func loadAll() async {
        isLoading = true
        errorMessage = nil
        async let s = HarnessService.fetchStats()
        async let sess = HarnessService.fetchSessions(limit: 50)
        async let fb = HarnessService.fetchFeedback(limit: 20)
        do {
            let (statsResult, sessionsResult, feedbackResult) = try await (s, sess, fb)
            stats = statsResult
            sessions = sessionsResult
            lessons = feedbackResult
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Subviews

private struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.bold().monospacedDigit())
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct AgentSessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.agentIcon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.agentDisplayName)
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 8) {
                    Text(session.createdDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if session.failureCount > 0 {
                        Label("\(session.failureCount)", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

private struct FeedbackRow: View {
    let lesson: FeedbackLesson

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: lesson.ratingIcon)
                .font(.title3)
                .foregroundStyle(ratingColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.content)
                    .font(.subheadline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(lesson.createdDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(lesson.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var ratingColor: Color {
        switch lesson.rating {
        case "good": return .green
        case "bad": return .red
        default: return .secondary
        }
    }
}
