import SwiftUI

/// Phase A HITL 승인 화면.
///
/// 에이전트가 외부 부작용 도구(send_email 등)를 호출하면 백엔드가 suspend
/// 시키고 APNs로 알림을 보낸다. 사용자는 초안을 미리보고 승인/거절/수정.
///
/// FeedbackView와는 별도 — FeedbackView는 H3-A 요약 피드백, 이건 명령 승인.
struct ApprovalSheetView: View {
    let approval: ApprovalDetail
    let onResolved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editedTo: String
    @State private var editedSubject: String
    @State private var editedBody: String
    @State private var isEditing = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var resultMessage: String?

    init(approval: ApprovalDetail, onResolved: @escaping () -> Void) {
        self.approval = approval
        self.onResolved = onResolved
        _editedTo = State(initialValue: approval.args.to ?? "")
        _editedSubject = State(initialValue: approval.args.subject ?? "")
        _editedBody = State(initialValue: approval.args.body ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 요약 헤더
                    summaryHeader

                    // 메일 초안 미리보기 / 편집
                    if approval.toolName == "send_email" {
                        emailPreview
                    } else {
                        // 다른 도구는 raw args 표시 (확장 시 추가)
                        rawArgsView
                    }

                    if let error = errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if let result = resultMessage {
                        Label(result, systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.green)
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
            .navigationTitle("승인 요청")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "취소" : "편집") {
                        if isEditing {
                            // 편집 취소 — 원본 복원
                            editedTo = approval.args.to ?? ""
                            editedSubject = approval.args.subject ?? ""
                            editedBody = approval.args.body ?? ""
                        }
                        isEditing.toggle()
                    }
                    .disabled(isSubmitting || resultMessage != nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionButtons
            }
        }
    }

    // MARK: - Subviews

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: toolIcon)
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text(approval.preview.summary ?? approval.toolName)
                    .font(.subheadline.weight(.medium))
            }
            HStack(spacing: 8) {
                Label(approval.preview.agent ?? "agent", systemImage: "person.crop.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("· \(approval.toolName)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var emailPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            // To
            VStack(alignment: .leading, spacing: 4) {
                Text("받는 사람")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if isEditing {
                    TextField("To", text: $editedTo)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(editedTo)
                        .font(.body)
                }
            }

            // Subject
            VStack(alignment: .leading, spacing: 4) {
                Text("제목")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if isEditing {
                    TextField("Subject", text: $editedSubject)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(editedSubject)
                        .font(.body.weight(.medium))
                }
            }

            // Body
            VStack(alignment: .leading, spacing: 4) {
                Text("본문")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if isEditing {
                    TextEditor(text: $editedBody)
                        .frame(minHeight: 200)
                        .padding(8)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text(editedBody)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var rawArgsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Args")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            if let to = approval.args.to {
                Text("to: \(to)").font(.caption.monospaced())
            }
            if let subject = approval.args.subject {
                Text("subject: \(subject)").font(.caption.monospaced())
            }
            if let body = approval.args.body {
                Text("body: \(body)").font(.caption.monospaced()).lineLimit(5)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                Task { await reject() }
            } label: {
                Label("거절", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isSubmitting || resultMessage != nil)

            Button {
                Task { await approve() }
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Label(
                            isEditing || hasEdits ? "수정 후 승인" : "승인",
                            systemImage: "checkmark"
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSubmitting || resultMessage != nil)
        }
        .padding()
        .background(.bar)
    }

    private var toolIcon: String {
        switch approval.toolName {
        case "send_email": return "envelope.badge"
        case "git_push": return "arrow.up.doc"
        case "create_calendar_event": return "calendar.badge.plus"
        default: return "questionmark.circle"
        }
    }

    private var hasEdits: Bool {
        editedTo != (approval.args.to ?? "")
            || editedSubject != (approval.args.subject ?? "")
            || editedBody != (approval.args.body ?? "")
    }

    // MARK: - Actions

    @MainActor
    private func approve() async {
        isSubmitting = true
        errorMessage = nil
        do {
            let modified: ApprovalArgs? = hasEdits
                ? ApprovalArgs(to: editedTo, subject: editedSubject, body: editedBody)
                : nil
            let response = try await OrchestratorAPI.approve(
                token: approval.token,
                modifiedArgs: modified
            )
            Haptic.success()
            resultMessage = response.result?.summary ?? "처리 완료"
            // 잠시 보여준 후 닫기
            try? await Task.sleep(nanoseconds: 800_000_000)
            onResolved()
            dismiss()
        } catch {
            Haptic.error()
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }

    @MainActor
    private func reject() async {
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await OrchestratorAPI.reject(
                token: approval.token,
                reason: "사용자 거절"
            )
            Haptic.warning()
            resultMessage = "거절 처리 완료"
            try? await Task.sleep(nanoseconds: 600_000_000)
            onResolved()
            dismiss()
        } catch {
            Haptic.error()
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
