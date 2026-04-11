import UIKit

/// 앱 전역 Haptic feedback 헬퍼.
///
/// UX 폴리시용 — 주요 액션에 물리적 피드백 추가.
enum Haptic {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// 버튼/카드 탭 — 가벼운 피드백
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// 선택 변경 — Picker, segmented 등
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
