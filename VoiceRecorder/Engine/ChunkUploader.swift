import Foundation

struct TranscribeSegment: Codable {
    let start: Double
    let end: Double
    let text: String
    let speaker: String?
}

struct TranscribeResult: Codable {
    let text: String
    let segments: [TranscribeSegment]
    let language: String
    let duration: Double
}

final class ChunkUploader {
    static let shared = ChunkUploader()

    private let session: URLSession
    private var serverURL: URL
    private let queue = DispatchQueue(label: "com.sonaiengine.voicerecorder.uploader")
    private var pendingUploads: [PendingUpload] = []
    private var isProcessing = false

    struct PendingUpload: Codable {
        let fileURL: String
        let sessionId: String
        let chunkIndex: Int
        var retryCount: Int = 0
    }

    private var pendingFilePath: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("pending_uploads.json")
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)

        let savedURL = UserDefaults.standard.string(forKey: "stt_server_url") ?? "http://14.6.220.78:8100"
        serverURL = URL(string: savedURL) ?? URL(string: "http://14.6.220.78:8100")!

        loadPendingUploads()
    }

    var currentServerURL: String {
        get { serverURL.absoluteString }
        set {
            if let url = URL(string: newValue) {
                serverURL = url
                UserDefaults.standard.set(newValue, forKey: "stt_server_url")
            }
        }
    }

    func upload(fileURL: URL, sessionId: String, chunkIndex: Int, completion: @escaping (TranscribeResult?) -> Void) {
        let endpoint = serverURL.appendingPathComponent("api/transcribe")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // multipart body를 임시 파일에 스트림으로 작성 (메모리 절약)
        let tmpBodyURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(boundary).body")
        guard let outputStream = OutputStream(url: tmpBodyURL, append: false) else {
            completion(nil)
            return
        }
        outputStream.open()
        defer {
            outputStream.close()
            try? FileManager.default.removeItem(at: tmpBodyURL)
        }

        func write(_ string: String) {
            let data = string.data(using: .utf8)!
            _ = data.withUnsafeBytes { outputStream.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count) }
        }

        // file part — 청크 단위로 복사
        write("--\(boundary)\r\n")
        write("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        write("Content-Type: audio/mp4\r\n\r\n")

        guard let inputStream = InputStream(url: fileURL) else {
            completion(nil)
            return
        }
        inputStream.open()
        let bufferSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(&buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                outputStream.write(buffer, maxLength: bytesRead)
            }
        }
        inputStream.close()

        write("\r\n")
        // enable_diarization part
        write("--\(boundary)\r\n")
        write("Content-Disposition: form-data; name=\"enable_diarization\"\r\n\r\n")
        write("true\r\n")
        // initial_prompt
        let vocabulary = UserDefaults.standard.string(forKey: "stt_vocabulary") ?? ""
        if !vocabulary.isEmpty {
            write("--\(boundary)\r\n")
            write("Content-Disposition: form-data; name=\"initial_prompt\"\r\n\r\n")
            write("\(vocabulary)\r\n")
        }
        write("--\(boundary)--\r\n")
        outputStream.close()

        let task = session.uploadTask(with: request, fromFile: tmpBodyURL) { data, response, error in
            if let error {
                print("[ChunkUploader] Upload failed: \(error.localizedDescription)")
                self.addToPending(fileURL: fileURL, sessionId: sessionId, chunkIndex: chunkIndex)
                completion(nil)
                return
            }

            guard let data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                self.addToPending(fileURL: fileURL, sessionId: sessionId, chunkIndex: chunkIndex)
                completion(nil)
                return
            }

            do {
                let result = try JSONDecoder().decode(TranscribeResult.self, from: data)
                completion(result)
            } catch {
                print("[ChunkUploader] Decode failed: \(error)")
                self.addToPending(fileURL: fileURL, sessionId: sessionId, chunkIndex: chunkIndex)
                completion(nil)
            }
        }
        task.resume()
    }

    // MARK: - Session Complete (Obsidian vault에 마크다운 생성)

    func notifySessionComplete(session: Session, completion: @escaping (Bool) -> Void) {
        let endpoint = serverURL.appendingPathComponent("api/session/complete")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let sessionDate = dateFormatter.string(from: session.startDate)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        var chunksPayload: [[String: Any]] = []
        for chunk in session.chunks {
            let startTime = timeFormatter.string(from: chunk.startDate)
            let endTime = timeFormatter.string(from: chunk.startDate.addingTimeInterval(chunk.duration))

            var segmentsPayload: [[String: Any]] = []
            if let segments = chunk.segments {
                for seg in segments {
                    var segDict: [String: Any] = [
                        "start": seg.start,
                        "end": seg.end,
                        "text": seg.text,
                    ]
                    if let speaker = seg.speaker {
                        segDict["speaker"] = speaker
                    }
                    segmentsPayload.append(segDict)
                }
            }

            chunksPayload.append([
                "start_time": startTime,
                "end_time": endTime,
                "duration": chunk.duration,
                "text": chunk.transcript ?? "",
                "segments": segmentsPayload,
            ])
        }

        let body: [String: Any] = [
            "session_date": sessionDate,
            "chunks": chunksPayload,
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(false)
            return
        }
        request.httpBody = jsonData

        let task = session_http.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                self.removePendingSync(sessionId: session.id)
                completion(true)
            } else {
                print("[ChunkUploader] Session complete failed: \(error?.localizedDescription ?? "unknown")")
                self.savePendingSync(session: session)
                completion(false)
            }
        }
        task.resume()
    }

    // session 프로퍼티 이름 충돌 방지
    private var session_http: URLSession { session }

    // MARK: - Obsidian Sync Retry

    private var pendingSyncPath: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("pending_obsidian_sync.json")
    }

    private func savePendingSync(session: Session) {
        queue.async {
            var pending = self.loadPendingSyncs()
            if !pending.contains(where: { $0.id == session.id }) {
                pending.append(session)
            }
            if let data = try? JSONEncoder().encode(pending) {
                try? data.write(to: self.pendingSyncPath, options: .atomic)
            }
        }
    }

    private func loadPendingSyncs() -> [Session] {
        guard let data = try? Data(contentsOf: pendingSyncPath) else { return [] }
        return (try? JSONDecoder().decode([Session].self, from: data)) ?? []
    }

    private func removePendingSync(sessionId: UUID) {
        queue.async {
            var pending = self.loadPendingSyncs()
            pending.removeAll { $0.id == sessionId }
            if let data = try? JSONEncoder().encode(pending) {
                try? data.write(to: self.pendingSyncPath, options: .atomic)
            }
        }
    }

    func retryPendingSyncs() {
        queue.async {
            let pending = self.loadPendingSyncs()
            for session in pending {
                self.notifySessionComplete(session: session) { success in
                    if success {
                        self.removePendingSync(sessionId: session.id)
                        print("[ChunkUploader] Obsidian 재동기화 성공: \(session.id.uuidString.prefix(8))")
                    }
                }
            }
        }
    }

    // MARK: - Retry Queue

    private func addToPending(fileURL: URL, sessionId: String, chunkIndex: Int, retryCount: Int = 0) {
        queue.async {
            let pending = PendingUpload(
                fileURL: fileURL.path,
                sessionId: sessionId,
                chunkIndex: chunkIndex,
                retryCount: retryCount
            )
            self.pendingUploads.append(pending)
            self.savePendingUploads()
        }
    }

    func retryPendingUploads(completion: @escaping (Int) -> Void) {
        queue.async {
            guard !self.isProcessing else {
                completion(0)
                return
            }
            self.isProcessing = true

            let uploads = self.pendingUploads
            self.pendingUploads.removeAll()
            self.savePendingUploads()

            var successCount = 0
            let group = DispatchGroup()

            for upload in uploads where upload.retryCount < 3 {
                let fileURL = URL(fileURLWithPath: upload.fileURL)
                guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

                group.enter()
                self.upload(fileURL: fileURL, sessionId: upload.sessionId, chunkIndex: upload.chunkIndex) { result in
                    if result != nil {
                        successCount += 1
                    } else {
                        self.addToPending(
                            fileURL: fileURL,
                            sessionId: upload.sessionId,
                            chunkIndex: upload.chunkIndex,
                            retryCount: upload.retryCount + 1
                        )
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.isProcessing = false
                completion(successCount)
            }
        }
    }

    private func loadPendingUploads() {
        guard let data = try? Data(contentsOf: pendingFilePath) else { return }
        pendingUploads = (try? JSONDecoder().decode([PendingUpload].self, from: data)) ?? []
    }

    private func savePendingUploads() {
        if let data = try? JSONEncoder().encode(pendingUploads) {
            try? data.write(to: pendingFilePath, options: .atomic)
        }
    }
}
