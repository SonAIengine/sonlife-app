import AVFoundation

protocol RecordingEngineDelegate: AnyObject {
    func engineDidFinishChunk(url: URL, duration: TimeInterval, index: Int, startDate: Date)
    func engineDidUpdateMeters(averagePower: Float, peakPower: Float)
    func engineDidEncounterError(_ error: Error)
}

final class RecordingEngine {
    weak var delegate: RecordingEngineDelegate?

    private(set) var isRecording = false
    private var currentRecorder: AVAudioRecorder?
    private var meteringTimer: Timer?
    private var chunkTimer: Timer?
    private var currentChunkStartTime: Date?
    private(set) var currentChunkIndex = 0
    private var currentChunkURL: URL?
    private var chunkDuration: TimeInterval
    private var audioSettings: [String: Any]
    private var urlProvider: ((Int) -> URL)?
    private var isSplitting = false

    static let lifeLogSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        AVEncoderBitRateKey: 32000
    ]

    static let manualSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    init(chunkDuration: TimeInterval = 300, audioSettings: [String: Any] = lifeLogSettings) {
        self.chunkDuration = chunkDuration
        self.audioSettings = audioSettings
    }

    func start(urlProvider: @escaping (Int) -> URL, startingChunkIndex: Int = 0) {
        self.urlProvider = urlProvider
        currentChunkIndex = startingChunkIndex
        startChunk(index: startingChunkIndex)

        let mTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateMeters()
        }
        RunLoop.main.add(mTimer, forMode: .common)
        meteringTimer = mTimer

        let cTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkChunkSplit()
        }
        RunLoop.main.add(cTimer, forMode: .common)
        chunkTimer = cTimer

        isRecording = true
    }

    func stop() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        chunkTimer?.invalidate()
        chunkTimer = nil

        finalizeCurrentChunk()
        isRecording = false
    }

    func currentAveragePower() -> Float {
        // updateMeters()는 meteringTimer에서 0.1초마다 호출하므로 여기서는 중복 호출하지 않음
        currentRecorder?.averagePower(forChannel: 0) ?? -160.0
    }

    var currentTime: TimeInterval {
        currentRecorder?.currentTime ?? 0
    }

    func splitNow() {
        guard !isSplitting else { return }
        isSplitting = true
        defer { isSplitting = false }

        let nextIndex = currentChunkIndex + 1
        finalizeCurrentChunk()
        startChunk(index: nextIndex)
    }

    // MARK: - Private

    private func startChunk(index: Int) {
        guard let urlProvider else { return }
        let url = urlProvider(index)
        currentChunkIndex = index

        do {
            let recorder = try AVAudioRecorder(url: url, settings: audioSettings)
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            recorder.record()
            currentRecorder = recorder
            currentChunkURL = url
            currentChunkStartTime = Date()
        } catch {
            delegate?.engineDidEncounterError(error)
        }
    }

    private func finalizeCurrentChunk() {
        guard let recorder = currentRecorder,
              let url = currentChunkURL,
              let startTime = currentChunkStartTime else { return }

        let duration = recorder.currentTime
        recorder.stop()
        currentRecorder = nil

        if duration > 0.5 {
            delegate?.engineDidFinishChunk(url: url, duration: duration, index: currentChunkIndex, startDate: startTime)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func checkChunkSplit() {
        guard let recorder = currentRecorder, !isSplitting else { return }
        if recorder.currentTime >= chunkDuration {
            splitNow()
        }
    }

    private func updateMeters() {
        guard let recorder = currentRecorder else { return }
        recorder.updateMeters()
        let avg = recorder.averagePower(forChannel: 0)
        let peak = recorder.peakPower(forChannel: 0)
        delegate?.engineDidUpdateMeters(averagePower: avg, peakPower: peak)
    }
}
