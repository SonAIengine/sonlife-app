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

    private let examplePrompts = [
        "장하렴한테 어제 회의 정리 메일 써줘",
        "김교수님께 논문 진행상황 메일",
        "팀원들에게 다음주 회의 일정 메일",
    ]

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

                    // 예시 prompts
                    VStack(alignment: .leading, spacing: 8) {
                        Text("예시")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        ForEach(examplePrompts, id: \.self) { example in
                            Button {
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
        do {
            let response = try await OrchestratorAPI.dispatch(input: trimmed)
            lastResponse = response

            // pending_hitl이면 approval sheet 자동 오픈
            if response.status == .pendingHITL, let token = response.pendingToken {
                let approval = try await OrchestratorAPI.fetchApproval(token: token)
                pendingApproval = approval
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isDispatching = false
    }
}
