import SwiftUI
import UserNotifications

@main
struct SonlifeAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(AppTheme(rawValue: selectedTheme)?.colorScheme)
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[APNs] 권한 요청 에러: \(error.localizedDescription)")
            }
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            } else {
                print("[APNs] 알림 권한 거부됨")
            }
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[APNs] token: \(tokenString)")
        FeedbackService.registerDevice(token: tokenString)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[APNs] 등록 실패: \(error.localizedDescription)")
    }

    // 포그라운드 수신
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // 푸시 탭 핸들러
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let type = userInfo["type"] as? String {
            switch type {
            case "feedback_request":
                if let sessionId = userInfo["session_id"] as? String {
                    let summary = userInfo["summary_preview"] as? String ?? ""
                    NotificationCenter.default.post(
                        name: .showFeedback,
                        object: nil,
                        userInfo: ["session_id": sessionId, "summary": summary]
                    )
                }
            case "approval_request":
                // Phase A — 에이전트 HITL 승인
                if let token = userInfo["token"] as? String {
                    NotificationCenter.default.post(
                        name: .showApproval,
                        object: nil,
                        userInfo: ["token": token]
                    )
                }
            default:
                break
            }
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let showFeedback = Notification.Name("SonLifeShowFeedback")
    static let showApproval = Notification.Name("SonLifeShowApproval")
}
