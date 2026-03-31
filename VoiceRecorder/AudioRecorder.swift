import AVFoundation
import Speech
import Combine

@Observable
final class AudioRecorder {
    var isRecording = false
    var isPaused = false
    var recordings: [Recording] = []
    var currentTime: TimeInterval = 0
    var errorMessage: String?

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private let fileManager = FileManager.default

    var recordingsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings")
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    init() {
        loadRecordings()
    }

    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            errorMessage = "오디오 세션 설정 실패: \(error.localizedDescription)"
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = recordingsDirectory.appendingPathComponent("\(timestamp).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: filename, settings: settings)
            audioRecorder?.record()
            isRecording = true
            isPaused = false
            currentTime = 0
            startTimer()
        } catch {
            errorMessage = "녹음 시작 실패: \(error.localizedDescription)"
        }
    }

    func pauseRecording() {
        audioRecorder?.pause()
        isPaused = true
        timer?.invalidate()
    }

    func resumeRecording() {
        audioRecorder?.record()
        isPaused = false
        startTimer()
    }

    func stopRecording() {
        guard let recorder = audioRecorder else { return }
        let url = recorder.url
        recorder.stop()
        timer?.invalidate()
        isRecording = false
        isPaused = false
        currentTime = 0
        audioRecorder = nil
        loadRecordings()

        // 자동 STT 변환
        transcribe(url: url)
    }

    func deleteRecording(_ recording: Recording) {
        try? fileManager.removeItem(at: recording.url)
        if let txtURL = recording.transcriptURL {
            try? fileManager.removeItem(at: txtURL)
        }
        loadRecordings()
    }

    func loadRecordings() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            recordings = []
            return
        }

        recordings = files
            .filter { $0.pathExtension == "m4a" }
            .compactMap { url -> Recording? in
                let attrs = try? fileManager.attributesOfItem(atPath: url.path)
                let date = attrs?[.creationDate] as? Date ?? Date()
                let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
                let hasTranscript = fileManager.fileExists(atPath: txtURL.path)
                let transcript = hasTranscript ? (try? String(contentsOf: txtURL, encoding: .utf8)) : nil
                return Recording(url: url, date: date, transcript: transcript)
            }
            .sorted { $0.date > $1.date }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder else { return }
            self.currentTime = recorder.currentTime
        }
    }

    private func transcribe(url: URL) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    self.errorMessage = "음성 인식 권한이 필요합니다."
                }
                return
            }

            // 한국어 인식기 (fallback: 기기 기본 언어)
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
                ?? SFSpeechRecognizer()

            guard let recognizer, recognizer.isAvailable else {
                DispatchQueue.main.async {
                    self.errorMessage = "음성 인식을 사용할 수 없습니다."
                }
                return
            }

            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false

            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                    let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
                    try? text.write(to: txtURL, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async {
                        self.loadRecordings()
                    }
                } else if let error {
                    DispatchQueue.main.async {
                        self.errorMessage = "STT 변환 실패: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
