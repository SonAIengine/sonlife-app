import SwiftUI

struct AgentSessionDetailView: View {
    let sessionId: String

    @State private var detail: AgentSessionDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        sessionHeader(detail)
                        timelineSection(detail.timeline)
                    }
                    .padding()
                }
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "로드 실패",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ProgressView("로딩 중...")
            }
        }
        .navigationTitle("세션 상세")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetail() }
    }

    // MARK: - Header

    private func sessionHeader(_ detail: AgentSessionDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(detail.title)
                .font(.headline)

            if !detail.description.isEmpty {
                Text(detail.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Label(detail.createdDate.formatted(.dateTime.month(.abbreviated).day().hour().minute().second()),
                      systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)

                if detail.successCount > 0 {
                    Label("\(detail.successCount)", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if detail.failureCount > 0 {
                    Label("\(detail.failureCount)", systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Timeline

    private func timelineSection(_ events: [TimelineEvent]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("타임라인")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)

            if events.isEmpty {
                HStack {
                    Spacer()
                    Text("이벤트 없음")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    HStack(alignment: .top, spacing: 12) {
                        // Timeline dot + line
                        VStack(spacing: 0) {
                            Circle()
                                .fill(event.kind == "tool_call" ? Color.blue : Color.orange)
                                .frame(width: 10, height: 10)
                                .padding(.top, 5)

                            if index < events.count - 1 {
                                Rectangle()
                                    .fill(Color(.separator))
                                    .frame(width: 1)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 10)

                        // Content
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: event.kindIcon)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(event.title)
                                    .font(.subheadline.weight(.medium))
                            }

                            if !event.content.isEmpty {
                                Text(event.content)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.tertiarySystemFill))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }

                            Text(event.createdDate.formatted(.dateTime.hour().minute().second()))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.bottom, 16)
                    }
                }
            }
        }
    }

    // MARK: - Load

    private func loadDetail() async {
        isLoading = true
        do {
            detail = try await HarnessService.fetchSessionDetail(id: sessionId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
