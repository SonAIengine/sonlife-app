import Foundation

@Observable
final class SessionManager {
    var sessions: [Session] = []
    var activeSession: Session?

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    let sessionsDirectory: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("LifeLog")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sessionsDirectory = dir
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        loadAllSessions()
        recoverInterruptedSessions()
    }

    func startSession() -> Session {
        let session = Session()
        let sessionDir = sessionsDirectory.appendingPathComponent(session.directoryName)
        try? fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        activeSession = session
        saveSessionMetadata(session)
        return session
    }

    func addChunk(url: URL, duration: TimeInterval, index: Int, startDate: Date) {
        guard var session = activeSession else { return }
        var chunk = Chunk(sessionId: session.id, chunkIndex: index, startDate: startDate)
        chunk.duration = duration
        session.chunks.append(chunk)
        activeSession = session
        saveSessionMetadata(session)
    }

    func markChunkAsSilence(index: Int) {
        guard var session = activeSession else { return }
        if let chunkIdx = session.chunks.firstIndex(where: { $0.chunkIndex == index }) {
            session.chunks[chunkIdx].isSilence = true
            activeSession = session
            saveSessionMetadata(session)
        }
    }

    func updateChunkTranscript(sessionId: UUID, chunkIndex: Int, transcript: String, segments: [Chunk.TranscriptSegment]) {
        // 활성 세션에서 찾기
        if var session = activeSession, session.id == sessionId {
            if let idx = session.chunks.firstIndex(where: { $0.chunkIndex == chunkIndex }) {
                session.chunks[idx].transcript = transcript
                session.chunks[idx].segments = segments
                activeSession = session
                saveSessionMetadata(session)
            }
            return
        }
        // 완료된 세션에서 찾기
        if let sessionIdx = sessions.firstIndex(where: { $0.id == sessionId }) {
            if let chunkIdx = sessions[sessionIdx].chunks.firstIndex(where: { $0.chunkIndex == chunkIndex }) {
                sessions[sessionIdx].chunks[chunkIdx].transcript = transcript
                sessions[sessionIdx].chunks[chunkIdx].segments = segments
                saveSessionMetadata(sessions[sessionIdx])
            }
        }
    }

    func finalizeSession() {
        guard var session = activeSession else { return }
        session.status = .completed
        session.endDate = Date()
        activeSession = nil
        saveSessionMetadata(session)
        cleanupSilenceChunks(session)
        loadAllSessions()
    }

    func deleteSession(_ session: Session) {
        let sessionDir = sessionsDirectory.appendingPathComponent(session.directoryName)
        try? fileManager.removeItem(at: sessionDir)
        loadAllSessions()
    }

    func chunkURL(for session: Session, index: Int) -> URL {
        sessionsDirectory
            .appendingPathComponent(session.directoryName)
            .appendingPathComponent(String(format: "chunk-%03d.m4a", index))
    }

    // 앱 백그라운드 진입 시 즉시 저장 (#9)
    func saveCurrentState() {
        guard let session = activeSession else { return }
        saveSessionMetadata(session)
    }

    func estimatedRemainingHours() -> Double {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let freeBytes = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let bytesPerHour: Double = 14_400_000
        return Double(freeBytes) / bytesPerHour
    }

    // MARK: - Persistence

    private func saveSessionMetadata(_ session: Session) {
        let dir = sessionsDirectory.appendingPathComponent(session.directoryName)
        let metaURL = dir.appendingPathComponent("session.json")
        if let data = try? encoder.encode(session) {
            try? data.write(to: metaURL, options: .atomic)
        }
    }

    func loadAllSessions() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            sessions = []
            return
        }

        sessions = contents
            .compactMap { dir -> Session? in
                let metaURL = dir.appendingPathComponent("session.json")
                guard let data = try? Data(contentsOf: metaURL) else { return nil }
                return try? decoder.decode(Session.self, from: data)
            }
            .sorted { $0.startDate > $1.startDate }
    }

    // 앱 재시작 시 미완료 세션 복구 (#9)
    private func recoverInterruptedSessions() {
        for i in sessions.indices {
            if sessions[i].status == .recording || sessions[i].status == .paused {
                sessions[i].status = .completed
                sessions[i].endDate = sessions[i].chunks.last?.startDate ?? sessions[i].startDate
                saveSessionMetadata(sessions[i])
            }
        }
    }

    private func cleanupSilenceChunks(_ session: Session) {
        let sessionDir = sessionsDirectory.appendingPathComponent(session.directoryName)
        for chunk in session.chunks where chunk.isSilence {
            let chunkURL = sessionDir.appendingPathComponent(chunk.filename)
            try? fileManager.removeItem(at: chunkURL)
        }
    }
}
