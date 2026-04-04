import SwiftUI
import AVFoundation

struct SessionDetailView: View {
    let session: Session
    let sessionManager: SessionManager
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playingChunkIndex: Int?
    @State private var playbackTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var syncStatus: SyncStatus = .idle

    private var fullTranscript: String {
        session.chunks
            .compactMap(\.transcript)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var body: some View {
        List {
            Section("세션 정보") {
                LabeledContent("시작", value: session.startDate.formatted(date: .abbreviated, time: .shortened))
                if let end = session.endDate {
                    LabeledContent("종료", value: end.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("총 시간", value: formatDuration(session.totalDuration))
                LabeledContent("청크 수", value: "\(session.chunkCount)개")
                LabeledContent("상태") {
                    StatusBadge(status: session.status)
                }
            }

            // 전체 텍스트
            if !fullTranscript.isEmpty {
                Section("텍스트") {
                    Text(fullTranscript)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }

            Section("청크 목록") {
                ForEach(session.chunks) { chunk in
                    ChunkRow(
                        chunk: chunk,
                        isPlaying: playingChunkIndex == chunk.chunkIndex && isPlaying,
                        onTap: { toggleChunkPlayback(chunk) }
                    )
                }
            }
        }
        .navigationTitle("세션 상세")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        syncToObsidian()
                    } label: {
                        switch syncStatus {
                        case .idle:
                            Image(systemName: "arrow.triangle.2.circlepath")
                        case .syncing:
                            ProgressView()
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .disabled(syncStatus == .syncing || session.chunks.isEmpty)

                    Button {
                        shareSession()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onDisappear {
            stopPlayback()
        }
    }

    private func toggleChunkPlayback(_ chunk: Chunk) {
        if playingChunkIndex == chunk.chunkIndex && isPlaying {
            stopPlayback()
            return
        }

        stopPlayback()
        let url = chunk.url(in: sessionManager.sessionsDirectory.appendingPathComponent(session.id.uuidString))

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
            duration = player?.duration ?? 0
            playingChunkIndex = chunk.chunkIndex
            isPlaying = true

            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] t in
                guard let player else {
                    t.invalidate()
                    return
                }
                playbackTime = player.currentTime
                if !player.isPlaying {
                    isPlaying = false
                    playingChunkIndex = nil
                    t.invalidate()
                }
            }
        } catch {
            // 재생 실패 시 무시
        }
    }

    private func stopPlayback() {
        player?.stop()
        timer?.invalidate()
        isPlaying = false
        playingChunkIndex = nil
        playbackTime = 0
    }

    private func shareSession() {
        let urls = session.chunks.compactMap { chunk -> URL? in
            let url = chunk.url(in: sessionManager.sessionsDirectory.appendingPathComponent(session.id.uuidString))
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        guard !urls.isEmpty else { return }
        let activityVC = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    private func syncToObsidian() {
        syncStatus = .syncing

        // 미전사 청크가 있으면 먼저 STT 업로드
        let untranscribedChunks = session.chunks.filter { $0.transcript == nil && !$0.isSilence }
        let sessionDir = sessionManager.sessionsDirectory.appendingPathComponent(session.id.uuidString)

        if untranscribedChunks.isEmpty {
            sendSessionComplete()
            return
        }

        let group = DispatchGroup()
        for chunk in untranscribedChunks {
            let fileURL = chunk.url(in: sessionDir)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            group.enter()
            ChunkUploader.shared.upload(fileURL: fileURL, sessionId: session.id.uuidString, chunkIndex: chunk.chunkIndex) { result in
                if let result {
                    let segments = result.segments.map {
                        Chunk.TranscriptSegment(start: $0.start, end: $0.end, text: $0.text, speaker: $0.speaker)
                    }
                    DispatchQueue.main.async {
                        self.sessionManager.updateChunkTranscript(
                            sessionId: session.id,
                            chunkIndex: chunk.chunkIndex,
                            transcript: result.text,
                            segments: segments
                        )
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            // 세션 데이터 새로고침 후 Obsidian 동기화
            self.sessionManager.loadAllSessions()
            if let updated = self.sessionManager.sessions.first(where: { $0.id == session.id }) {
                ChunkUploader.shared.notifySessionComplete(session: updated) { success in
                    DispatchQueue.main.async {
                        self.syncStatus = success ? .success : .failure
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            self.syncStatus = .idle
                        }
                    }
                }
            } else {
                self.sendSessionComplete()
            }
        }
    }

    private func sendSessionComplete() {
        ChunkUploader.shared.notifySessionComplete(session: session) { success in
            DispatchQueue.main.async {
                syncStatus = success ? .success : .failure
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    syncStatus = .idle
                }
            }
        }
    }

    private enum SyncStatus {
        case idle, syncing, success, failure
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
}

struct ChunkRow: View {
    let chunk: Chunk
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(isPlaying ? .red : .blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("청크 \(chunk.chunkIndex + 1)")
                        .font(.subheadline.bold())
                    Text(chunk.startDate.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let transcript = chunk.transcript, !transcript.isEmpty {
                        Text(transcript)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Text(formatChunkDuration(chunk.duration))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                if chunk.isSilence {
                    Image(systemName: "speaker.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func formatChunkDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
