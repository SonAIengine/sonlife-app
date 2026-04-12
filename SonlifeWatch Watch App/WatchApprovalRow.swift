import SwiftUI

// MARK: - D3: Watch Approval Row

struct WatchApprovalRow: View {
    let approval: WatchOrchestratorAPI.WatchApproval
    var onApprove: () -> Void
    var onReject: () -> Void

    @State private var isProcessing = false
    @State private var result: ActionResult?

    enum ActionResult {
        case approved, rejected, failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tool label
            HStack(spacing: 4) {
                Image(systemName: toolIcon)
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text(approval.toolDisplayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.blue)
            }

            // Title
            Text(approval.displayTitle)
                .font(.footnote)
                .lineLimit(3)

            // Action buttons
            if let result {
                resultBadge(result)
            } else if isProcessing {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 8) {
                    Button {
                        handleApprove()
                    } label: {
                        Label("승인", systemImage: "checkmark")
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button(role: .destructive) {
                        handleReject()
                    } label: {
                        Label("거절", systemImage: "xmark")
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var toolIcon: String {
        switch approval.toolName {
        case "send_teams_message": return "bubble.left.fill"
        case "email_send", "email_compose_draft": return "envelope.fill"
        case "calendar_create_event": return "calendar.badge.plus"
        case "commit_and_push": return "arrow.triangle.branch"
        default: return "gearshape.fill"
        }
    }

    @ViewBuilder
    private func resultBadge(_ result: ActionResult) -> some View {
        HStack {
            Spacer()
            switch result {
            case .approved:
                Label("승인됨", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            case .rejected:
                Label("거절됨", systemImage: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            case .failed:
                Label("실패", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
    }

    private func handleApprove() {
        isProcessing = true
        Task {
            do {
                try await WatchOrchestratorAPI.approve(token: approval.token)
                result = .approved
                onApprove()
            } catch {
                result = .failed
            }
            isProcessing = false
        }
    }

    private func handleReject() {
        isProcessing = true
        Task {
            do {
                try await WatchOrchestratorAPI.reject(token: approval.token)
                result = .rejected
                onReject()
            } catch {
                result = .failed
            }
            isProcessing = false
        }
    }
}
