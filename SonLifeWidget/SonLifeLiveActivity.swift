import ActivityKit
import SwiftUI
import WidgetKit

struct SonLifeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            // 잠금화면 표시
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.circle.fill")
                            .foregroundStyle(.red)
                        Text("SonLife")
                            .font(.caption.bold())
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(formatTime(context.state.elapsedSeconds))
                        .font(.system(.body, design: .monospaced).bold())
                        .foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            Label("\(context.state.chunkCount)", systemImage: "square.stack.3d.up")
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(vadColor(context.state.vadState))
                                    .frame(width: 6, height: 6)
                                Text(vadText(context.state.vadState))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if !context.state.lastTranscript.isEmpty {
                            Text(context.state.lastTranscript)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {}
            } compactLeading: {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.red)
            } compactTrailing: {
                Text(formatTime(context.state.elapsedSeconds))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
            } minimal: {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private func vadColor(_ state: String) -> Color {
        switch state {
        case "active": return .green
        case "silenceDetected": return .yellow
        default: return .gray
        }
    }

    private func vadText(_ state: String) -> String {
        switch state {
        case "active": return "녹음 중"
        case "silenceDetected": return "무음 감지"
        default: return "일시정지"
        }
    }
}

struct LockScreenView: View {
    let context: ActivityViewContext<RecordingAttributes>

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundStyle(.red)
                    Text("SonLife 녹음 중")
                        .font(.subheadline.bold())
                }

                if !context.state.lastTranscript.isEmpty {
                    Text(context.state.lastTranscript)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatTime(context.state.elapsedSeconds))
                    .font(.system(.title3, design: .monospaced).bold())
                    .foregroundStyle(.red)

                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up")
                    Text("\(context.state.chunkCount)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
