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
        serverURL = URL(string: savedURL)!

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

        guard let fileData = try? Data(contentsOf: fileURL) else {
            completion(nil)
            return
        }

        var body = Data()
        // file part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        // enable_diarization part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"enable_diarization\"\r\n\r\n".data(using: .utf8)!)
        body.append("true\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let task = session.dataTask(with: request) { data, response, error in
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
                completion(true)
            } else {
                print("[ChunkUploader] Session complete failed: \(error?.localizedDescription ?? "unknown")")
                completion(false)
            }
        }
        task.resume()
    }

    // session 프로퍼티 이름 충돌 방지
    private var session_http: URLSession { session }

    // MARK: - Retry Queue

    private func addToPending(fileURL: URL, sessionId: String, chunkIndex: Int) {
        queue.async {
            let pending = PendingUpload(
                fileURL: fileURL.path,
                sessionId: sessionId,
                chunkIndex: chunkIndex
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
