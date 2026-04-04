import SwiftUI

struct SessionListView: View {
    let sessionManager: SessionManager

    var body: some View {
        List {
            ForEach(sessionManager.sessions) { session in
                NavigationLink {
                    SessionDetailView(session: session, sessionManager: sessionManager)
                } label: {
                    SessionRow(session: session)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    sessionManager.deleteSession(sessionManager.sessions[index])
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if sessionManager.sessions.isEmpty {
                ContentUnavailableView(
                    "세션이 없습니다",
                    systemImage: "waveform.slash",
                    description: Text("LifeLog을 시작하면 세션이 생성됩니다")
                )
            }
        }
    }
}

struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                Spacer()
                StatusBadge(status: session.status)
            }

            HStack {
                Label("\(session.chunkCount)개 청크", systemImage: "square.stack.3d.up")
                Spacer()
                Text(formatDuration(session.totalDuration))
                    .font(.subheadline.monospaced().bold())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        if m > 0 {
            return String(format: "%d분 %d초", m, s)
        }
        return "\(s)초"
    }
}

struct StatusBadge: View {
    let status: Session.Status

    var body: some View {
        Text(statusText)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(statusColor.opacity(0.2)))
            .foregroundStyle(statusColor)
    }

    private var statusText: String {
        switch status {
        case .recording: return "녹음 중"
        case .paused: return "일시정지"
        case .completed: return "완료"
        }
    }

    private var statusColor: Color {
        switch status {
        case .recording: return .red
        case .paused: return .orange
        case .completed: return .green
        }
    }
}
