import SwiftUI
import AVFoundation

struct RecordingDetailView: View {
    let recording: Recording
    let recorder: AudioRecorder
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 재생 컨트롤
                VStack(spacing: 12) {
                    // Seek 가능한 Slider
                    Slider(
                        value: Binding(
                            get: { duration > 0 ? playbackTime : 0 },
                            set: { newValue in
                                player?.currentTime = newValue
                                playbackTime = newValue
                            }
                        ),
                        in: 0...max(duration, 0.01)
                    )
                    .tint(.blue)

                    HStack {
                        Text(formatTime(playbackTime))
                            .font(.caption.monospaced())
                        Spacer()
                        Text(formatTime(duration))
                            .font(.caption.monospaced())
                    }
                    .foregroundStyle(.secondary)

                    // 재생 버튼
                    HStack(spacing: 30) {
                        Button {
                            seek(by: -10)
                        } label: {
                            Image(systemName: "gobackward.10")
                                .font(.title2)
                        }
                        .accessibilityLabel("10초 뒤로")

                        Button {
                            togglePlayback()
                        } label: {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 50))
                        }
                        .accessibilityLabel(isPlaying ? "일시정지" : "재생")

                        Button {
                            seek(by: 10)
                        } label: {
                            Image(systemName: "goforward.10")
                                .font(.title2)
                        }
                        .accessibilityLabel("10초 앞으로")
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))

                // STT 결과
                VStack(alignment: .leading, spacing: 8) {
                    Text("STT 결과")
                        .font(.headline)

                    if let transcript = recording.transcript {
                        Text(transcript)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemGroupedBackground)))
                    } else {
                        Text("변환 중이거나 변환 결과가 없습니다.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(recording.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareFiles()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .alert("녹음 삭제", isPresented: $showDeleteConfirm) {
            Button("삭제", role: .destructive) {
                recorder.deleteRecording(recording)
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 녹음을 삭제하시겠습니까?")
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    private func setupPlayer() {
        do {
            player = try AVAudioPlayer(contentsOf: recording.url)
            player?.prepareToPlay()
            duration = player?.duration ?? 0
        } catch {
            // 재생 실패 시 무시
        }
    }

    private func togglePlayback() {
        guard let player else { return }

        if isPlaying {
            player.pause()
            timer?.invalidate()
            isPlaying = false
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            player.play()
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] t in
                playbackTime = player.currentTime
                if !player.isPlaying {
                    isPlaying = false
                    t.invalidate()
                }
            }
        }
    }

    private func stopPlayback() {
        player?.stop()
        timer?.invalidate()
        isPlaying = false
    }

    private func seek(by seconds: TimeInterval) {
        guard let player else { return }
        let newTime = max(0, min(player.duration, player.currentTime + seconds))
        player.currentTime = newTime
        playbackTime = newTime
    }

    private func shareFiles() {
        var items: [Any] = [recording.url]
        if let txtURL = recording.transcriptURL {
            items.append(txtURL)
        }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
