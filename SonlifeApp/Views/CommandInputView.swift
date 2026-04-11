import SwiftUI

/// Phase A 명령 입력 화면.
///
/// 자연어 명령을 받아서 백엔드 orchestrator에 dispatch한다.
/// 결과가 pending_hitl이면 자동으로 ApprovalSheetView를 띄운다.
struct CommandInputView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var inputText: String = ""
    @State private var isDispatching = false
    @State private var lastResponse: CommandResponse?
    @State private var errorMessage: String?
    @State private var pendingApproval: ApprovalDetail?

    // C-6: 실시간 이벤트 스트림
    @State private var liveEvents: [LiveEvent] = []
    @State private var streamTask: Task<Void, Never>?

    struct LiveEvent: Identifiable {
        let id = UUID()
        let type: String
        let summary: String
    }

    private let examplePrompts = [
        "장하렴한테 어제 회의 정리 메일 써줘",
        "김교수님께 논문 진행상황 메일",
        "팀원들에게 다음주 회의 일정 메일",
    ]

    // C: 명령 히스토리 (로컬 UserDefaults, 최근 20개)
    @AppStorage("command_history") private var historyJson: String = "[]"
    private var history: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(historyJson.utf8))) ?? []
    }
    private func saveToHistory(_ text: String) {
        var items = history.filter { $0 != text }  // 중복 제거
        items.insert(text, at: 0)
        if items.count > 20 { items = Array(items.prefix(20)) }
        if let data = try? JSONEncoder().encode(items),
           let json = String(data: data, encoding: .utf8) {
            historyJson = json
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 입력 카드
                    VStack(alignment: .leading, spacing: 8) {
                        Label("자연어 명령", systemImage: "text.bubble")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextField(
                            "예: 장하렴한테 어제 회의 정리 메일 써줘",
                            text: $inputText,
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                        .disabled(isDispatching)
                    }

                    // 히스토리 (최근 5개)
                    if !history.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("최근 사용")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Button("전체 지우기") {
                                    Haptic.tap()
                                    historyJson = "[]"
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            ForEach(Array(history.prefix(5)), id: \.self) { item in
                                Button {
                                    Haptic.tap()
                                    inputText = item
                                } label: {
                                    HStack {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                        Text(item)
                                            .font(.footnote)
                                            .multilineTextAlignment(.leading)
                                            .lineLimit(2)
                                        Spacer()
                                    }
                                    .padding(10)
                                    .background(Color.blue.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .disabled(isDispatching)
                            }
                        }
                    }

                    // 예시 prompts
                    VStack(alignment: .leading, spacing: 8) {
                        Text("예시")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        ForEach(examplePrompts, id: \.self) { example in
                            Button {
                                Haptic.tap()
                                inputText = example
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.up.left")
                                        .font(.caption2)
                                    Text(example)
                                        .font(.footnote)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(isDispatching)
                        }
                    }

                    // 결과 / 에러
                    if let response = lastResponse {
                        responseCard(response)
                    }
                    if !liveEvents.isEmpty {
                        liveEventsCard
                    }
                    if let error = errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
            .navigationTitle("에이전트 명령")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await dispatch() }
                } label: {
                    Group {
                        if isDispatching {
                            ProgressView()
                        } else {
                            Label("전송", systemImage: "paperplane.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.bar)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isDispatching)
            }
            .sheet(item: $pendingApproval) { approval in
                ApprovalSheetView(approval: approval) {
                    pendingApproval = nil
                    dismiss()
                }
            }
        }
    }

    // MARK: - Live events card (C-6 SSE)

    private var liveEventsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.blue)
                Text("실시간")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Spacer()
                Text("\(liveEvents.count) 이벤트")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(liveEvents.suffix(10)) { event in
                HStack(spacing: 6) {
                    Image(systemName: eventIcon(event.type))
                        .font(.caption2)
                        .foregroundStyle(eventColor(event.type))
                        .frame(width: 14)
                    Text(event.summary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func eventIcon(_ type: String) -> String {
        switch type {
        case "session.started": return "play.circle"
        case "tool.called": return "hammer"
        case "tool.completed": return "checkmark.circle"
        case "tool.failed": return "xmark.circle"
        case "session.completed": return "checkmark.seal.fill"
        case "session.failed": return "exclamationmark.triangle.fill"
        case "session.suspended": return "hourglass"
        default: return "circle"
        }
    }

    private func eventColor(_ type: String) -> Color {
        switch type {
        case "tool.failed", "session.failed": return .red
        case "session.completed": return .green
        case "session.suspended": return .orange
        default: return .blue
        }
    }

    // MARK: - Response card

    private func responseCard(_ response: CommandResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: statusIcon(response.status))
                    .foregroundStyle(statusColor(response.status))
                Text("상태: \(statusLabel(response.status))")
                    .font(.subheadline.weight(.medium))
            }
            Text("Session: \(response.commandId)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            if let token = response.pendingToken {
                Text("Token: \(token.prefix(16))…")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let summary = response.preview?.summary {
                Text(summary)
                    .font(.footnote)
                    .padding(.top, 4)
            }
            if let err = response.error {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statusIcon(_ status: PhaseASessionStatus) -> String {
        switch status {
        case .running: return "circle.dotted"
        case .pendingHITL: return "hourglass"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .rejected: return "minus.circle.fill"
        }
    }

    private func statusColor(_ status: PhaseASessionStatus) -> Color {
        switch status {
        case .running: return .blue
        case .pendingHITL: return .orange
        case .completed: return .green
        case .failed, .rejected: return .red
        }
    }

    private func statusLabel(_ status: PhaseASessionStatus) -> String {
        switch status {
        case .running: return "실행 중"
        case .pendingHITL: return "승인 대기"
        case .completed: return "완료"
        case .failed: return "실패"
        case .rejected: return "거절됨"
        }
    }

    // MARK: - Dispatch

    @MainActor
    private func dispatch() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isDispatching = true
        errorMessage = nil
        lastResponse = nil
        liveEvents = []
        Haptic.tap(.medium)
        saveToHistory(trimmed)

        // 1. C-6: async dispatch — session_id 즉시 받기
        let response: CommandResponse
        do {
            response = try await OrchestratorAPI.dispatchAsync(input: trimmed)
        } catch {
            Haptic.error()
            errorMessage = error.localizedDescription
            isDispatching = false
            return
        }
        lastResponse = response
        let sessionId = response.commandId

        // 2. SSE 스트림 구독해서 이벤트 수신
        do {
            for try await event in OrchestratorAPI.sessionEventStream(sessionId: sessionId) {
                liveEvents.append(LiveEvent(
                    type: event.type,
                    summary: summarizeEvent(event),
                ))

                if event.type == "session.suspended" {
                    // HITL: approval 상세 fetch 후 sheet
                    if let token = event.data["data"] as? [String: Any],
                       let t = token["token"] as? String {
                        let approval = try? await OrchestratorAPI.fetchApproval(token: t)
                        pendingApproval = approval
                    } else if let token = event.data["token"] as? String {
                        let approval = try? await OrchestratorAPI.fetchApproval(token: token)
                        pendingApproval = approval
                    }
                    break
                }
                if event.type == "session.completed" {
                    Haptic.success()
                    try? await Task.sleep(for: .milliseconds(800))
                    dismiss()
                    break
                }
                if event.type == "session.failed" {
                    Haptic.error()
                    try? await Task.sleep(for: .milliseconds(800))
                    dismiss()
                    break
                }
            }
        } catch {
            // 스트림 오류는 조용히 — 최종 상태는 inbox가 폴링으로 갱신
            errorMessage = "stream: \(error.localizedDescription)"
        }
        isDispatching = false
    }

    private func summarizeEvent(_ event: SSEClient.Event) -> String {
        // 서버는 {"type": "...", "data": {...}} 래퍼를 보냄
        let innerData = event.data["data"] as? [String: Any] ?? event.data
        switch event.type {
        case "session.started":
            let tools = (innerData["recommended_tools"] as? [String])?.prefix(4).joined(separator: ", ") ?? ""
            return "시작 · tools: \(tools)"
        case "tool.called":
            let name = innerData["tool_name"] as? String ?? "?"
            let step = innerData["step"] as? Int ?? 0
            return "#\(step) \(name) 호출"
        case "tool.completed":
            let name = innerData["tool_name"] as? String ?? "?"
            let summary = innerData["summary"] as? String ?? ""
            return "#\(innerData["step"] ?? 0) \(name): \(summary)"
        case "tool.failed":
            let name = innerData["tool_name"] as? String ?? "?"
            let err = innerData["error"] as? String ?? ""
            return "#\(name) 실패: \(err)"
        case "session.completed":
            let tools = (innerData["tools_used"] as? [String])?.joined(separator: ", ") ?? ""
            return "완료 (\(tools))"
        case "session.failed":
            return "실패: \(innerData["error"] as? String ?? "")"
        case "session.suspended":
            return "HITL 승인 대기: \(innerData["tool_name"] as? String ?? "")"
        default:
            return event.type
        }
    }
}
