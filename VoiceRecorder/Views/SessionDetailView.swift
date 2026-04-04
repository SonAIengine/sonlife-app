import SwiftUI
import AVFoundation

struct SessionDetailView: View {
    let sessionId: UUID
    let sessionManager: SessionManager
    var recorder: AudioRecorder?

    private var session: Session {
        sessionManager.activeSession?.id == sessionId
            ? sessionManager.activeSession!
            : sessionManager.sessions.first(where: { $0.id == sessionId })
                ?? Session(id: sessionId)
    }
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playingChunkIndex: Int?
    @State private var playbackTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var syncStatus: SyncStatus = .idle
    @State private var expandedChunkIndex: Int?
    @State private var renamingSpeaker: String?
    @State private var speakerNewName: String = ""
    @State private var uploadingChunkIndices: Set<Int> = []

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
                            speakerNames: session.speakerNames,
                            isUploading: uploadingChunkIndices.contains(chunk.chunkIndex),
                            onPlayTap: { toggleChunkPlayback(chunk) },
                            onSpeakerTap: { speakerId in
                                speakerNewName = session.speakerNames[speakerId] ?? ""
                                renamingSpeaker = speakerId
                            },
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

                    // 현재 녹음 중인 청크 표시
                    if let recorder, recorder.isLifeLogActive,
                       sessionManager.activeSession?.id == sessionId {
                        HStack {
                            Image(systemName: "waveform.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.red)
                                .symbolEffect(.pulse)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("청크 \(recorder.currentChunkIndex + 1)")
                                        .font(.subheadline.bold())
                                    Text(formatChunkTime(recorder.currentChunkTime))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Text("녹음 중...")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
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
        .alert("화자 이름 지정", isPresented: .init(
            get: { renamingSpeaker != nil },
            set: { if !$0 { renamingSpeaker = nil } }
        )) {
            TextField("이름", text: $speakerNewName)
            Button("저장") {
                if let speakerId = renamingSpeaker, !speakerNewName.isEmpty {
                    sessionManager.updateSpeakerName(
                        sessionId: session.id,
                        speakerId: speakerId,
                        name: speakerNewName
                    )
                    sessionManager.loadAllSessions()
                    // 서버에 화자 등록 (embedding DB)
                    registerSpeakerOnServer(speakerId: speakerId, name: speakerNewName)
                }
                renamingSpeaker = nil
            }
            Button("취소", role: .cancel) { renamingSpeaker = nil }
        } message: {
            if let speakerId = renamingSpeaker {
                Text("\(speakerId)의 이름을 입력하세요")
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

        // 순차 처리 (GPU OOM 방지)
        uploadChunksSequentially(chunks: untranscribedChunks, sessionDir: sessionDir, index: 0)
    }

    private func uploadChunksSequentially(chunks: [Chunk], sessionDir: URL, index: Int) {
        guard index < chunks.count else {
            // 모든 청크 업로드 완료 → Obsidian 동기화
            sessionManager.loadAllSessions()
            if let updated = sessionManager.sessions.first(where: { $0.id == sessionId }) {
                ChunkUploader.shared.notifySessionComplete(session: updated) { success in
                    DispatchQueue.main.async {
                        self.syncStatus = success ? .success : .failure
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            self.syncStatus = .idle
                        }
                    }
                }
            } else {
                sendSessionComplete()
            }
            return
        }

        let chunk = chunks[index]
        let fileURL = chunk.url(in: sessionDir)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            uploadChunksSequentially(chunks: chunks, sessionDir: sessionDir, index: index + 1)
            return
        }

        uploadingChunkIndices.insert(chunk.chunkIndex)
        ChunkUploader.shared.upload(fileURL: fileURL, sessionId: sessionId.uuidString, chunkIndex: chunk.chunkIndex) { result in
            DispatchQueue.main.async {
                self.uploadingChunkIndices.remove(chunk.chunkIndex)
                if let result {
                    let segments = result.segments.map {
                        Chunk.TranscriptSegment(start: $0.start, end: $0.end, text: $0.text, speaker: $0.speaker)
                    }
                    self.sessionManager.updateChunkTranscript(
                        sessionId: self.sessionId,
                        chunkIndex: chunk.chunkIndex,
                        transcript: result.text,
                        segments: segments
                    )
                }
                // 다음 청크 처리
                self.uploadChunksSequentially(chunks: chunks, sessionDir: sessionDir, index: index + 1)
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

    private func registerSpeakerOnServer(speakerId: String, name: String) {
        guard let chunk = session.chunks.first(where: { $0.transcript != nil && !$0.isSilence }) else { return }
        let sessionDir = sessionManager.sessionsDirectory.appendingPathComponent(session.id.uuidString)
        let audioURL = chunk.url(in: sessionDir)
        guard FileManager.default.fileExists(atPath: audioURL.path),
              let fileData = try? Data(contentsOf: audioURL) else { return }

        let serverURL = ChunkUploader.shared.currentServerURL
        guard let endpoint = URL(string: serverURL)?.appendingPathComponent("api/speakers/register-from-audio") else { return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\n\(name)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"speaker_label\"\r\n\r\n\(speakerId)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\nContent-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error {
                print("[SpeakerRegister] 등록 실패: \(error.localizedDescription)")
            } else {
                print("[SpeakerRegister] \(name) 등록 완료")
            }
        }.resume()
    }

    private enum SyncStatus {
        case idle, syncing, success, failure
    }

    private func formatChunkTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d / 5:00", m, s)
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
    var speakerNames: [String: String] = [:]
    var isUploading: Bool = false
    let onPlayTap: () -> Void
    var onSpeakerTap: ((String) -> Void)?
    let onExpandTap: () -> Void

    private func displayName(for speakerId: String) -> String {
        speakerNames[speakerId] ?? speakerId
    }

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
                        if let placemark = chunk.location?.placemark {
                            HStack(spacing: 2) {
                                Image(systemName: "location.fill")
                                Text(placemark)
                            }
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        }
                    }

                    if !isExpanded {
                        if let transcript = chunk.transcript, !transcript.isEmpty {
                            Text(transcript)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } else if isUploading {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("STT 변환 중...")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
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
                                        Text(displayName(for: speaker))
                                            .font(.caption2.bold())
                                            .foregroundStyle(isSegmentActive(seg) ? .white : .blue)
                                            .frame(width: 80, alignment: .leading)
                                            .onTapGesture {
                                                onSpeakerTap?(speaker)
                                            }
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
                    if isUploading {
                        HStack {
                            ProgressView()
                            Text("STT 변환 중...")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Text("STT 미완료")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
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
