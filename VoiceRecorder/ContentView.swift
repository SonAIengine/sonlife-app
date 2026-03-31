import SwiftUI

struct ContentView: View {
    @State private var recorder = AudioRecorder()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 녹음 목록
                List {
                    ForEach(recorder.recordings) { recording in
                        NavigationLink {
                            RecordingDetailView(recording: recording, recorder: recorder)
                        } label: {
                            RecordingRow(recording: recording)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            recorder.deleteRecording(recorder.recordings[index])
                        }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if recorder.recordings.isEmpty {
                        ContentUnavailableView(
                            "녹음이 없습니다",
                            systemImage: "mic.slash",
                            description: Text("아래 버튼을 눌러 녹음을 시작하세요")
                        )
                    }
                }

                Divider()

                // 녹음 컨트롤
                RecordingControlView(recorder: recorder)
                    .padding()
                    .background(.ultraThinMaterial)
            }
            .navigationTitle("음성 녹음기")
            .alert("오류", isPresented: .init(
                get: { recorder.errorMessage != nil },
                set: { if !$0 { recorder.errorMessage = nil } }
            )) {
                Button("확인") { recorder.errorMessage = nil }
            } message: {
                Text(recorder.errorMessage ?? "")
            }
        }
    }
}

struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.date.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)

            if let transcript = recording.transcript {
                Text(transcript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("STT 변환 중...")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RecordingControlView: View {
    @Bindable var recorder: AudioRecorder

    var body: some View {
        VStack(spacing: 12) {
            if recorder.isRecording {
                Text(formatTime(recorder.currentTime))
                    .font(.system(.title, design: .monospaced))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 40) {
                if recorder.isRecording {
                    // 일시정지/재개
                    Button {
                        if recorder.isPaused {
                            recorder.resumeRecording()
                        } else {
                            recorder.pauseRecording()
                        }
                    } label: {
                        Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                            .font(.title)
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(.gray.opacity(0.2)))
                    }

                    // 정지
                    Button {
                        recorder.stopRecording()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(.red))
                    }
                } else {
                    // 녹음 시작
                    Button {
                        recorder.startRecording()
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 70, height: 70)
                            .background(Circle().fill(.red))
                    }
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let tenths = Int((time - Double(Int(time))) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}
