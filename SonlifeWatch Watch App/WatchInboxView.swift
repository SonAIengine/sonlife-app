import SwiftUI

// MARK: - D3: Watch Inbox View (Main Screen)
//
// Apple Watch 메인 화면.
// App Group의 WidgetData.Snapshot을 1차 소스로 사용하고,
// pull-to-refresh 시 API를 직접 호출한다.

struct WatchInboxView: View {
    @State private var pendingCount = 0
    @State private var runningCount = 0
    @State private var approvals: [WatchOrchestratorAPI.WatchApproval] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showApprovalList = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Summary cards
                    HStack(spacing: 12) {
                        statusCard(
                            count: pendingCount,
                            label: "승인 대기",
                            icon: "hourglass",
                            color: .orange
                        )
                        statusCard(
                            count: runningCount,
                            label: "실행 중",
                            icon: "circle.dotted",
                            color: .blue
                        )
                    }

                    if isLoading {
                        ProgressView("로딩 중...")
                            .padding()
                    } else if let error = errorMessage {
                        VStack(spacing: 4) {
                            Image(systemName: "wifi.slash")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    } else if approvals.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                            Text("대기 작업 없음")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 20)
                    } else {
                        // Approval list (max 3)
                        ForEach(approvals.prefix(3)) { approval in
                            WatchApprovalRow(
                                approval: approval,
                                onApprove: { refreshData() },
                                onReject: { refreshData() }
                            )
                            .padding(.horizontal, 4)

                            if approval.id != approvals.prefix(3).last?.id {
                                Divider()
                            }
                        }

                        if approvals.count > 3 {
                            Text("외 \(approvals.count - 3)건")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("SonLife")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadFromAppGroup()
                refreshData()
            }
        }
    }

    // MARK: - Status Card

    private func statusCard(count: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text("\(count)")
                .font(.title2.weight(.bold).monospacedDigit())
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Data Loading

    /// App Group에서 캐시된 WidgetData 로드 (빠른 초기 표시)
    private func loadFromAppGroup() {
        guard let defaults = UserDefaults(suiteName: "group.com.sonaiengine.sonlifeapp"),
              let data = defaults.data(forKey: "pending_approvals_snapshot"),
              let snapshot = try? JSONDecoder().decode(WidgetDataSnapshot.self, from: data)
        else { return }

        pendingCount = snapshot.pendingCount
        runningCount = snapshot.runningCount
    }

    /// API에서 최신 데이터 fetch
    private func refreshData() {
        Task {
            isLoading = approvals.isEmpty
            errorMessage = nil
            do {
                let fetched = try await WatchOrchestratorAPI.fetchPendingApprovals()
                approvals = fetched
                pendingCount = fetched.count
                isLoading = false
            } catch {
                errorMessage = "서버 연결 실패"
                isLoading = false
            }
        }
    }
}

// MARK: - Minimal WidgetData Snapshot (Watch standalone decode)

private struct WidgetDataSnapshot: Codable {
    let pendingCount: Int
    let runningCount: Int
}
