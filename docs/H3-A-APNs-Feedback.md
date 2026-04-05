# H3-A: APNs 푸시 + 피드백 UI 통합 가이드

SonLife 서버의 하네스(H3-A)에 연결하기 위한 iOS 앱 변경사항.

**목표**: 서버가 요약 완료하면 푸시 알림 수신 → 앱 열어서 👍/👎 피드백 → 서버로 전송 → synaptic-memory 강화

## 필요한 준비

### 1. Apple Developer Portal 작업 (한 번만)

1. https://developer.apple.com/account → Certificates, Identifiers & Profiles
2. **App ID**: `com.sonaiengine.voicerecorder` 확인 → **Push Notifications capability 활성화**
3. **Keys** → `+` → **Apple Push Notifications service (APNs)** 체크 → Continue
4. 생성된 `.p8` 파일 다운로드 (한 번만 가능)
5. **Key ID (10자)** 복사
6. **Team ID**: `XMF443BPZ9` (이미 project.yml에 있음)

### 2. SonLife 서버 `.env` 설정

`/home/son/projects/app/sonlife/.env`에 추가:
```env
APNS_KEY_PATH=/home/son/.secrets/AuthKey_XXXXXXXXXX.p8
APNS_KEY_ID=XXXXXXXXXX
APNS_TEAM_ID=XMF443BPZ9
APNS_BUNDLE_ID=com.sonaiengine.voicerecorder
APNS_USE_SANDBOX=1
```

---

## iOS 앱 변경사항

### 1. `VoiceRecorder/Info.plist`

```xml
<!-- 기존 키들 유지 + 추가 -->
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>remote-notification</string>  <!-- 추가 -->
</array>
```

### 2. `VoiceRecorder/VoiceRecorder.entitlements`

```xml
<!-- 기존 유지 + 추가 -->
<key>aps-environment</key>
<string>development</string>  <!-- 배포 시 production -->
```

### 3. `VoiceRecorder/VoiceRecorderApp.swift`

```swift
import SwiftUI
import UserNotifications

@main
struct VoiceRecorderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        // APNs 등록
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
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

    // 앱 포그라운드 상태에서 푸시 수신
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
        if let type = userInfo["type"] as? String, type == "feedback_request",
           let sessionId = userInfo["session_id"] as? String {
            let summary = userInfo["summary_preview"] as? String ?? ""
            // FeedbackView로 네비게이션 (NotificationCenter 사용)
            NotificationCenter.default.post(
                name: .showFeedback,
                object: nil,
                userInfo: ["session_id": sessionId, "summary": summary]
            )
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let showFeedback = Notification.Name("SonLifeShowFeedback")
}
```

### 4. `VoiceRecorder/Engine/FeedbackService.swift` (신규)

```swift
import Foundation
import UIKit

enum FeedbackService {
    static var serverURL: String {
        UserDefaults.standard.string(forKey: "server_url") ?? "http://14.6.220.78:8100"
    }

    static var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    /// APNs 디바이스 토큰을 서버에 등록
    static func registerDevice(token: String) {
        guard let url = URL(string: "\(serverURL)/api/devices/register") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "device_id": deviceId,
            "device_token": token,
            "platform": "ios",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("[FeedbackService] 디바이스 등록 실패: \(error)")
            } else {
                print("[FeedbackService] 디바이스 등록 완료: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
        }.resume()
    }

    /// 사용자 피드백 서버에 전송
    static func sendFeedback(
        sessionId: String,
        rating: String?,
        comment: String = "",
        source: String = "ios-button",
        completion: @escaping (Bool) -> Void
    ) {
        guard let url = URL(string: "\(serverURL)/api/feedback") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "session_id": sessionId,
            "comment": comment,
            "source": source,
        ]
        if let rating = rating {
            body["rating"] = rating
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, response, error in
            let success = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(success) }
        }.resume()
    }
}
```

### 5. `VoiceRecorder/Views/FeedbackView.swift` (신규)

Apple HIG 스타일 — SF Symbols + `.borderedProminent` / `.bordered` 버튼.

```swift
import SwiftUI

struct FeedbackView: View {
    let sessionId: String
    let summaryPreview: String

    @Environment(\.dismiss) private var dismiss
    @State private var comment: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 요약 미리보기
                    if !summaryPreview.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("오늘 요약", systemImage: "sparkles")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(summaryPreview)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // 코멘트 영역
                    VStack(alignment: .leading, spacing: 8) {
                        Text("한 마디 남기기 (선택)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextField("어떤 점이 좋았나요? 아쉬웠나요?", text: $comment, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                    }

                    if let error = errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("요약 피드백")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Accept / Decline 버튼 (하단 고정)
                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        sendFeedback(rating: "bad")
                    } label: {
                        Label("개선 필요", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isSending)

                    Button {
                        sendFeedback(rating: "good")
                    } label: {
                        Label("마음에 듦", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isSending)
                }
                .padding()
                .background(.bar)
            }
        }
    }

    private func sendFeedback(rating: String) {
        isSending = true
        errorMessage = nil
        FeedbackService.sendFeedback(
            sessionId: sessionId,
            rating: rating,
            comment: comment,
            source: "ios-button"
        ) { success in
            isSending = false
            if success {
                dismiss()
            } else {
                errorMessage = "전송 실패. 다시 시도해주세요."
            }
        }
    }
}
```

**디자인 메모:**
- `.borderedProminent` + `checkmark`: 기본 추천 액션 (마음에 듦)
- `.bordered` + `role: .destructive`: 주의 액션 (개선 필요)
- `safeAreaInset(edge: .bottom)`: 하단 고정, 스크롤과 분리
- SF Symbols로 텍스트-아이콘 조합 (이모지 대신)

### 6. `VoiceRecorder/ContentView.swift` 수정

```swift
struct ContentView: View {
    // 기존 state 유지 + 추가
    @State private var feedbackContext: FeedbackContext?

    var body: some View {
        TabView { /* 기존 탭들 */ }
            .sheet(item: $feedbackContext) { ctx in
                FeedbackView(sessionId: ctx.sessionId, summaryPreview: ctx.summary)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showFeedback)) { notif in
                if let sessionId = notif.userInfo?["session_id"] as? String {
                    let summary = notif.userInfo?["summary"] as? String ?? ""
                    feedbackContext = FeedbackContext(sessionId: sessionId, summary: summary)
                }
            }
    }
}

struct FeedbackContext: Identifiable {
    let id = UUID()
    let sessionId: String
    let summary: String
}
```

---

## 빌드 & 테스트

```bash
# 1. xcodegen으로 프로젝트 재생성
cd /home/son/projects/app/sonlife-app
xcodegen generate

# 2. Xcode에서 빌드
open VoiceRecorder.xcodeproj
```

Xcode에서:
1. **Signing & Capabilities**: Team 확인(XMF443BPZ9), **Push Notifications** capability 추가
2. 실제 디바이스에 빌드 (시뮬레이터는 APNs 미지원)
3. 앱 실행 → 알림 권한 허용 → 디바이스 토큰 콘솔 출력 확인
4. 서버 DB에 등록되었는지 확인:
   ```bash
   uv run python -c "
   from src.lifelog_db import LifelogDB
   db = LifelogDB('/home/son/projects/personal/obsidian-vault/.lifelog.sqlite')
   print(db.get_active_devices())
   "
   ```

## 서버 측 테스트 푸시 발송

```bash
# 디바이스 등록 후 수동 테스트
curl -X POST http://14.6.220.78:8100/api/harness/test-push \
  -H "Content-Type: application/json" \
  -d '{"session_id":"test","title":"테스트","body":"푸시 작동 확인"}'
```

## E2E 검증 흐름

1. iOS 앱 실행 → 권한 허용 → 서버에 토큰 등록
2. 서버 `SummaryAgent` 실행 (23:55 또는 수동)
3. 요약 완료 → 자동 푸시 발송
4. iOS에 푸시 배너 표시 → 탭 → FeedbackView 열림
5. 👍 또는 👎 탭 → `POST /api/feedback` 전송
6. 서버 synaptic-memory:
   - `reinforce([session_id], success=...)` 호출
   - comment 있으면 `lesson` 노드 생성 (LEARNED_FROM 엣지)
7. 다음 요약 실행 시 과거 lesson 참조 (H4 단계에서 구현)
