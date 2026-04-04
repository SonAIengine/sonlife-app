import ActivityKit
import Foundation

struct RecordingAttributes: ActivityAttributes {
    let sessionStartDate: Date

    struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var chunkCount: Int
        var isActive: Bool
        var vadState: String // "active", "silenceDetected", "silencePaused"
        var lastTranscript: String
    }
}
