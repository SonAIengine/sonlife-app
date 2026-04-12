import Foundation

/// 앱 ↔ 위젯 데이터 공유 (App Group UserDefaults).
///
/// 메인 앱이 `WidgetData.save(...)` 로 쓰고,
/// 위젯이 `WidgetData.load()` 로 읽는다.
enum WidgetData {
    static let suiteName = "group.com.sonaiengine.sonlifeapp"
    private static let key = "pending_approvals_snapshot"

    struct Snapshot: Codable {
        let pendingCount: Int
        let runningCount: Int
        let items: [Item]
        let updatedAt: Date

        struct Item: Codable {
            let token: String
            let title: String
            let toolLabel: String
            let source: String?
            let createdAt: String
        }
    }

    static func save(_ snapshot: Snapshot) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> Snapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key)
        else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}
