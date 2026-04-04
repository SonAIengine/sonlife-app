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
    @State private var expandedChunkIndex: Int?

    var body: some View {
        ScrollViewReader { listProxy in
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

                Section("타임라인") {
                    ForEach(session.chunks) { chunk in
                        let isChunkPlaying = playingChunkIndex == chunk.chunkIndex && isPlaying
                        ChunkRow(
                            chunk: chunk,
                            isPlaying: isChunkPlaying,
                            isExpanded: expandedChunkIndex == chunk.chunkIndex,
                            playbackTime: isChunkPlaying ? playbackTime : nil,
                            onPlayTap: { toggleChunkPlayback(chunk) },
                            onExpandTap: {
                                let newIndex = expandedChunkIndex == chunk.chunkIndex ? nil : chunk.chunkIndex
                                withAnimation {
                                    expandedChunkIndex = newIndex
                                }
                                if newIndex != nil {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        withAnimation {
                                            listProxy.scrollTo(chunk.id, anchor: .top)
                                        }
                                    }
                                }
                            }
                        )
                        .id(chunk.id)
                    }
                }
            }
        }
        .navigationTitle(session.startDate.formatted(date: .abbreviated, time: .shortened))
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
        // 재생 시 자동 펼침
        withAnimation {
            expandedChunkIndex = chunk.chunkIndex
        }
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
    let isExpanded: Bool
    var playbackTime: TimeInterval?
    let onPlayTap: () -> Void
    let onExpandTap: () -> Void

    private func isSegmentActive(_ seg: Chunk.TranscriptSegment) -> Bool {
        guard let time = playbackTime else { return false }
        return time >= seg.start && time < seg.end
    }

    private func isSegmentPast(_ seg: Chunk.TranscriptSegment) -> Bool {
        guard let time = playbackTime else { return false }
        return time >= seg.end
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack {
                Button(action: onPlayTap) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(isPlaying ? .red : .blue)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(chunk.startDate.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline.bold())
                        Text(formatChunkDuration(chunk.duration))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        if chunk.isSilence {
                            Image(systemName: "speaker.slash")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    if !isExpanded, let transcript = chunk.transcript, !transcript.isEmpty {
                        Text(transcript)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onExpandTap)

            // 펼침 영역 — 재생 위치 하이라이트
            if isExpanded {
                Divider()
                    .padding(.vertical, 8)

                if let segments = chunk.segments, !segments.isEmpty {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                                HStack(alignment: .top, spacing: 8) {
                                    if let speaker = seg.speaker {
                                        Text(speaker)
                                            .font(.caption2.bold())
                                            .foregroundStyle(isSegmentActive(seg) ? .white : .blue)
                                            .frame(width: 80, alignment: .leading)
                                    }
                                    Text(seg.text)
                                        .font(.callout)
                                        .foregroundStyle(
                                            isSegmentActive(seg) ? .white :
                                            playbackTime != nil && !isSegmentPast(seg) ? .secondary :
                                            .primary
                                        )
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSegmentActive(seg) ? Color.blue : Color.clear)
                                )
                                .id(idx)
                            }
                        }
                        .onChange(of: playbackTime) { _, _ in
                            if let segments = chunk.segments,
                               let activeIdx = segments.firstIndex(where: { isSegmentActive($0) }) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(activeIdx, anchor: .center)
                                }
                            }
                        }
                    }
                } else if let transcript = chunk.transcript, !transcript.isEmpty {
                    Text(transcript)
                        .font(.callout)
                } else if chunk.isSilence {
                    Text("무음 구간")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("STT 미완료")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    private func formatChunkDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
