import Foundation

struct Session: Identifiable, Codable {
    let id: UUID
    let startDate: Date
    var endDate: Date?
    var chunks: [Chunk]
    var status: Status
    var speakerNames: [String: String]

    enum Status: String, Codable {
        case recording
        case paused
        case completed
    }

    enum CodingKeys: String, CodingKey {
        case id, startDate, endDate, chunks, status, speakerNames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        chunks = try container.decode([Chunk].self, forKey: .chunks)
        status = try container.decode(Status.self, forKey: .status)
        speakerNames = try container.decodeIfPresent([String: String].self, forKey: .speakerNames) ?? [:]
    }

    var totalDuration: TimeInterval {
        chunks.reduce(0) { $0 + $1.duration }
    }

    var chunkCount: Int { chunks.count }

    var directoryName: String { id.uuidString }

    init(id: UUID = UUID(), startDate: Date = Date()) {
        self.id = id
        self.startDate = startDate
        self.endDate = nil
        self.chunks = []
        self.status = .recording
        self.speakerNames = [:]
    }
}
