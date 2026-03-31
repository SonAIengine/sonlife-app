import AVFoundation
import Speech
import UIKit

@Observable
final class AudioRecorder: RecordingEngineDelegate, VADMonitorDelegate, AudioSessionHandlerDelegate {
    // Manual mode state
    var isRecording = false
    var isPaused = false
    var recordings: [Recording] = []
    var currentTime: TimeInterval = 0
    var errorMessage: String?

    // LifeLog state
    var isLifeLogActive = false
    var lifeLogSessionTime: TimeInterval = 0
    var currentPowerLevel: Float = -160.0
    var vadState: VADState = .active
    var vadSilenceDuration: TimeInterval = 0

    // Components
    private let engine = RecordingEngine()
    private let vad = VADMonitor()
    let sessionManager = SessionManager()
    private let audioSessionHandler = AudioSessionHandler()

    // Manual mode internals
    private var manualRecorder: AVAudioRecorder?
    private var timer: Timer?
    private let fileManager = FileManager.default

    let recordingsDirectory: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        recordingsDirectory = dir
        engine.delegate = self
        vad.delegate = self
        audioSessionHandler.delegate = self
        loadRecordings()
        observeAppLifecycle()
    }

    // MARK: - App Lifecycle (#9)

    private func observeAppLifecycle() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleAppTermination()
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleAppResignActive()
        }
    }

    private func handleAppTermination() {
        if isLifeLogActive {
            engine.stop()
            sessionManager.finalizeSession()
        }
    }

    private func handleAppResignActive() {
        // 백그라운드 진입 시 세션 메타데이터 즉시 저장 (강제 종료 대비)
        if isLifeLogActive, let session = sessionManager.activeSession {
            sessionManager.saveCurrentState()
        }
    }

    // MARK: - LifeLog Mode

    func startLifeLog() {
        do {
            try audioSessionHandler.configure()
        } catch {
            errorMessage = "오디오 세션 설정 실패: \(error.localizedDescription)"
            return
        }

        let session = sessionManager.startSession()
        isLifeLogActive = true
        lifeLogSessionTime = 0

        engine.start(urlProvider: { [weak self] index in
            guard let self, let activeSession = self.sessionManager.activeSession else {
                return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("temp.m4a")
            }
            return self.sessionManager.chunkURL(for: activeSession, index: index)
        }, startingChunkIndex: 0)

        vad.start(engine: engine)
        startLifeLogTimer()
    }

    func stopLifeLog() {
        vad.stop()
        engine.stop()
        timer?.invalidate()
        timer = nil
        sessionManager.finalizeSession()
        isLifeLogActive = false
        lifeLogSessionTime = 0
        currentPowerLevel = -160.0
        vadState = .active
    }

    private func startLifeLogTimer() {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.lifeLogSessionTime = (self.sessionManager.activeSession?.totalDuration ?? 0) + self.engine.currentTime
            self.vadSilenceDuration = self.vad.silenceDuration
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - RecordingEngineDelegate (#5 메인 스레드 보장, #7 startDate 전달)

    func engineDidFinishChunk(url: URL, duration: TimeInterval, index: Int, startDate: Date) {
        DispatchQueue.main.async { [weak self] in
            self?.sessionManager.addChunk(url: url, duration: duration, index: index, startDate: startDate)
        }
    }

    func engineDidUpdateMeters(averagePower: Float, peakPower: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.currentPowerLevel = averagePower
        }
    }

    func engineDidEncounterError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = "녹음 엔진 오류: \(error.localizedDescription)"
        }
    }

    // MARK: - VADMonitorDelegate (#5 메인 스레드 보장)

    func vadDidDetectSilence() {
        // 무음 감지 → 녹음 계속 유지 (미터링 위해)
    }

    func vadDidDetectVoice() {
        engine.splitNow()
        vad.reset()
    }

    func vadStateDidChange(_ state: VADState) {
        DispatchQueue.main.async { [weak self] in
            self?.vadState = state
        }
    }

    // MARK: - AudioSessionHandlerDelegate (#2 인덱스 중복 수정)

    func audioSessionWasInterrupted() {
        if isLifeLogActive {
            engine.stop()
            vad.stop()
            timer?.invalidate()
        }
    }

    func audioSessionInterruptionEnded(shouldResume: Bool) {
        if isLifeLogActive && shouldResume {
            guard let session = sessionManager.activeSession else { return }
            let nextIndex = session.chunkCount

            engine.start(urlProvider: { [weak self] index in
                guard let self, let activeSession = self.sessionManager.activeSession else {
                    return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("temp.m4a")
                }
                return self.sessionManager.chunkURL(for: activeSession, index: index)
            }, startingChunkIndex: nextIndex)

            vad.start(engine: engine)
            startLifeLogTimer()
        }
    }

    func audioRouteChanged(event: AudioRouteChangeEvent) {
        // iOS가 자동으로 내장 마이크로 전환
    }

    // MARK: - Manual Recording Mode

    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            errorMessage = "오디오 세션 설정 실패: \(error.localizedDescription)"
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = recordingsDirectory.appendingPathComponent("\(timestamp).m4a")

        do {
            manualRecorder = try AVAudioRecorder(url: filename, settings: RecordingEngine.manualSettings)
            manualRecorder?.record()
            isRecording = true
            isPaused = false
            currentTime = 0
            startManualTimer()
        } catch {
            errorMessage = "녹음 시작 실패: \(error.localizedDescription)"
        }
    }

    func pauseRecording() {
        manualRecorder?.pause()
        isPaused = true
        timer?.invalidate()
    }

    func resumeRecording() {
        manualRecorder?.record()
        isPaused = false
        startManualTimer()
    }

    func stopRecording() {
        guard let recorder = manualRecorder else { return }
        let url = recorder.url
        recorder.stop()
        timer?.invalidate()
        isRecording = false
        isPaused = false
        currentTime = 0
        manualRecorder = nil
        loadRecordings()
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

    // MARK: - Private

    private func startManualTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.manualRecorder else { return }
            self.currentTime = recorder.currentTime
        }
    }

    private func transcribe(url: URL) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    self?.errorMessage = "음성 인식 권한이 필요합니다."
                }
                return
            }

            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
                ?? SFSpeechRecognizer()

            guard let recognizer, recognizer.isAvailable else {
                DispatchQueue.main.async {
                    self?.errorMessage = "음성 인식을 사용할 수 없습니다."
                }
                return
            }

            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false

            recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                    let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
                    try? text.write(to: txtURL, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async {
                        self?.loadRecordings()
                    }
                } else if let error {
                    DispatchQueue.main.async {
                        self?.errorMessage = "STT 변환 실패: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
