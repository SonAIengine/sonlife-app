import Foundation

enum VADState: String {
    case active
    case silenceDetected
    case silencePaused
}

protocol VADMonitorDelegate: AnyObject {
    func vadDidDetectSilence()
    func vadDidDetectVoice()
    func vadStateDidChange(_ state: VADState)
}

final class VADMonitor {
    weak var delegate: VADMonitorDelegate?

    private(set) var state: VADState = .active
    private var silenceStartTime: Date?
    private var engine: RecordingEngine?
    private var timer: Timer?

    var silenceThresholdDB: Float = -40.0
    var resumeThresholdDB: Float = -35.0
    var silenceTimeoutSeconds: TimeInterval = 30.0

    var silenceDuration: TimeInterval {
        guard let start = silenceStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    func start(engine: RecordingEngine) {
        self.engine = engine
        state = .active
        silenceStartTime = nil

        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        engine = nil
        state = .active
        silenceStartTime = nil
    }

    func reset() {
        state = .active
        silenceStartTime = nil
        delegate?.vadStateDidChange(.active)
    }

    private func poll() {
        guard let engine else { return }
        let power = engine.currentAveragePower()
        processMeterReading(averagePower: power)
    }

    private func processMeterReading(averagePower: Float) {
        switch state {
        case .active:
            if averagePower < silenceThresholdDB {
                if silenceStartTime == nil {
                    silenceStartTime = Date()
                }
                transition(to: .silenceDetected)
            } else {
                silenceStartTime = nil
            }

        case .silenceDetected:
            if averagePower >= resumeThresholdDB {
                silenceStartTime = nil
                transition(to: .active)
            } else if silenceDuration >= silenceTimeoutSeconds {
                transition(to: .silencePaused)
                delegate?.vadDidDetectSilence()
            }

        case .silencePaused:
            if averagePower >= resumeThresholdDB {
                silenceStartTime = nil
                transition(to: .active)
                delegate?.vadDidDetectVoice()
            }
        }
    }

    private func transition(to newState: VADState) {
        guard state != newState else { return }
        state = newState
        delegate?.vadStateDidChange(newState)
    }
}
