import SwiftUI

struct LifeLogControlView: View {
    @Bindable var recorder: AudioRecorder
    @State private var showStopConfirm = false

    var body: some View {
        VStack(spacing: 12) {
            // LifeLog 토글
            HStack {
                Image(systemName: recorder.isLifeLogActive ? "waveform.circle.fill" : "waveform.circle")
                    .font(.title2)
                    .foregroundStyle(recorder.isLifeLogActive ? .red : .secondary)
                    .symbolEffect(.pulse, isActive: recorder.isLifeLogActive)
                Text("LifeLog")
                    .font(.title2.bold())
                Spacer()
                Toggle("", isOn: Binding(
                    get: { recorder.isLifeLogActive },
                    set: { newValue in
                        if newValue {
                            recorder.startLifeLog()
                        } else {
                            showStopConfirm = true
                        }
                    }
                ))
                .toggleStyle(.switch)
                .tint(.red)
                .labelsHidden()
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))

            if recorder.isLifeLogActive {
                // 세션 통계 + 레벨 미터
                VStack(spacing: 10) {
                    HStack {
                        StatView(
                            title: "녹음 시간",
                            value: formatDuration(recorder.lifeLogSessionTime),
                            icon: "clock"
                        )
                        Spacer()
                        StatView(
                            title: "청크",
                            value: "\(recorder.sessionManager.activeSession?.chunkCount ?? 0)개",
                            icon: "square.stack.3d.up"
                        )
                        Spacer()
                        StatView(
                            title: "잔여 저장",
                            value: formatRemainingHours(recorder.sessionManager.estimatedRemainingHours()),
                            icon: "internaldrive"
                        )
                    }

                    AudioLevelMeterView(level: recorder.currentPowerLevel)

                    // VAD 상태
                    HStack(spacing: 6) {
                        Circle()
                            .fill(vadColor)
                            .frame(width: 8, height: 8)
                        Text(vadStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.3), value: recorder.isLifeLogActive)
        .alert("LifeLog 종료", isPresented: $showStopConfirm) {
            Button("종료", role: .destructive) {
                recorder.stopLifeLog()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("현재 세션을 종료하시겠습니까?")
        }
    }

    private var vadColor: Color {
        switch recorder.vadState {
        case .active: return .green
        case .silenceDetected: return .yellow
        case .silencePaused: return .gray
        }
    }

    private var vadStatusText: String {
        switch recorder.vadState {
        case .active: return "녹음 중"
        case .silenceDetected:
            let remaining = max(0, Int(recorder.vadSilenceTimeout) - Int(recorder.vadSilenceDuration))
            return "무음 감지 (\(remaining)초)"
        case .silencePaused:
            return "무음 일시정지"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private func formatRemainingHours(_ hours: Double) -> String {
        if hours > 100 {
            return "\(Int(hours))h"
        }
        return String(format: "%.1fh", hours)
    }
}

struct StatView: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced).bold())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
