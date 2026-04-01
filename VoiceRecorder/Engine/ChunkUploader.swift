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
