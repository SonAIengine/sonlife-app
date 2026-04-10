# Phase A — iOS 클라이언트 구현 상태

> 작성: 2026-04-09 | 마지막 갱신: 2026-04-10
> 짝: [sonlife/docs/PHASE-A-STATUS.md](https://github.com/SonAIengine/sonlife/blob/main/docs/PHASE-A-STATUS.md)
> 비전 원본: [AGENT-SYSTEM-VISION.md](./AGENT-SYSTEM-VISION.md)

---

## TL;DR

- **컨트롤 타워 UI 완성**: 자연어 명령 발행 + HITL 승인 + 실행 기록 조회
- **Phase A Orchestrator API 통합**: OrchestratorAPI 서비스로 `/api/command`, `/api/approval`, `/api/sessions` 연동
- **APNs type 확장**: 기존 `feedback_request` + 신규 `approval_request` 핸들링
- **기존 H3-A FeedbackView와 공존** — 별도 namespace (모델 이름 충돌 없음)
- **Xcode Build 통과**

## 백엔드 대응 상태 (2026-04-10)

백엔드는 이후 다음 변화들을 반영:
- **범용 agent_runner** (specialist 제거) — iOS API 계약은 불변
- **graph-tool-call 동적 tool 선택** — iOS 입장에선 투명
- **Tool manifest (@sonlife_tool + auto-discovery)** — iOS 영향 없음
- **`coding_execute` composite tool** — 코딩 승인 시 diff payload가 달라짐 ⚠️

**iOS 측 미지원 갭**:
- **ApprovalSheetView의 코드 diff 렌더링** — 현재 email 전용 레이아웃. `coding_execute` → `commit_and_push` 승인 요청이 오면 diff를 제대로 보여주지 못함. 이게 **다음 iOS 작업의 최우선 항목**.

---

## 현재 iOS 화면 구성

```
ContentView (메인)
├── LifeLog (녹음 — 기존)
├── 녹음 (Manual — 기존)
└── 에이전트 (AgentDashboardView)
    │
    ├── [명령] 버튼 → CommandInputView                    ★ 신규
    │                └── 결과가 pending_hitl이면
    │                    ApprovalSheetView 자동 오픈       ★ 신규
    │
    ├── [실행 기록] NavigationLink                          ★ 신규
    │   └── OrchestratorSessionHistoryView
    │       └── 탭 → OrchestratorSessionDetailSheet
    │
    ├── Stats 카드 (기존 HarnessService)
    ├── 세션 탭 (기존 H3-A)
    └── 피드백 탭 (기존 H3-A)

+ 시트 (루트 ContentView)
  ├── FeedbackView ← APNs type="feedback_request"        (기존)
  └── ApprovalSheetView ← APNs type="approval_request"    ★ 신규
```

---

## 파일 구조 (변경점)

```
SonlifeApp/
├── SonlifeAppApp.swift                   AppDelegate: approval_request 핸들러 추가
├── ContentView.swift                     approvalContext 시트 + showApproval observer
│
├── Models/
│   ├── Session.swift                     기존
│   ├── Recording.swift                   기존
│   ├── Chunk.swift                       기존
│   └── OrchestratorModels.swift          ★ 신규 — Phase A 모델
│
├── Engine/
│   ├── HarnessService.swift              기존 (H3-A, synaptic-memory)
│   ├── FeedbackService.swift             기존 (H3-A 피드백)
│   └── OrchestratorAPI.swift             ★ 신규 — Phase A API 클라이언트
│
├── Views/
│   ├── AgentDashboardView.swift          수정 — 명령/실행기록 2-column 버튼
│   ├── CommandInputView.swift            ★ 신규 — 자연어 명령 입력
│   ├── ApprovalSheetView.swift           ★ 신규 — HITL 승인 시트
│   ├── OrchestratorSessionHistoryView.swift ★ 신규 — 실행 기록 리스트 + 상세
│   ├── FeedbackView.swift                기존 (H3-A)
│   ├── SessionListView.swift             기존 (녹음 세션)
│   ├── AgentSessionDetailView.swift      기존 (H3-A)
│   ├── SessionDetailView.swift           기존 (녹음)
│   ├── LifeLogControlView.swift          기존
│   ├── RecordingDetailView.swift         기존
│   ├── AudioLevelMeterView.swift         기존
│   └── SettingsView.swift                기존
```

---

## Phase A 모델 (OrchestratorModels.swift)

기존 `HarnessService.AgentSession`과는 **별개 namespace**. 동시 공존.

```swift
enum PhaseASessionStatus: String, Codable {
    case running, pendingHITL = "pending_hitl", completed, failed, rejected
}

struct CommandRequest / CommandResponse
struct ApprovalPreview / ApprovalArgs / ApprovalDetail (Identifiable) / ApprovalRequest
struct EmailDraft / SendResult / CommandResult
struct OrchestratorSession (Identifiable) / SessionUsage
struct BudgetSummary / AgentBudgetUsage
```

---

## OrchestratorAPI (Engine/)

```swift
enum OrchestratorAPI {
    static func dispatch(input: String) async throws -> CommandResponse
    static func fetchApproval(token: String) async throws -> ApprovalDetail
    static func approve(token: String, modifiedArgs: ApprovalArgs?) async throws
    static func reject(token: String, reason: String?) async throws
    static func fetchSessions(limit: Int = 30) async throws -> [OrchestratorSession]
    static func fetchPendingApprovals() async throws -> [ApprovalDetail]
    static func fetchBudget() async throws -> BudgetSummary
}
```

base URL은 `ChunkUploader.shared.currentServerURL` 사용 (기존 설정 재사용).

---

## APNs 핸들링 (확장됨)

`SonlifeAppApp.swift`의 `AppDelegate.userNotificationCenter(...didReceive:)`:

```swift
if let type = userInfo["type"] as? String {
    switch type {
    case "feedback_request":
        // 기존 H3-A 요약 피드백
        NotificationCenter.default.post(name: .showFeedback, ...)

    case "approval_request":
        // Phase A HITL 승인
        if let token = userInfo["token"] as? String {
            NotificationCenter.default.post(name: .showApproval, userInfo: ["token": token])
        }

    default: break
    }
}
```

ContentView가 `showApproval` Notification을 수신하면 `OrchestratorAPI.fetchApproval(token:)` 호출하여 상세를 가져온 뒤 `ApprovalSheetView` 시트 띄움.

---

## 화면별 주요 동작

### CommandInputView
1. 자연어 TextField + 예시 prompt 3개
2. 전송 → `OrchestratorAPI.dispatch(input:)`
3. 응답이 `pending_hitl`이면 `fetchApproval(token)` 호출 후 `ApprovalSheetView` sheet 자동 표시
4. 응답 카드: session_id, status, pending_token, preview.summary

### ApprovalSheetView
- 현재는 **이메일 발송 전용 레이아웃** (To / Subject / Body)
- 편집 모드 토글로 직접 수정 → 승인 시 `modify` 분기
- 승인: `OrchestratorAPI.approve(token:, modifiedArgs:)` — hasEdits면 modified_args 전송
- 거절: `OrchestratorAPI.reject(token:, reason:)`
- ⚠️ **CodingAgent의 diff payload 미지원** — Step 10 이후 diff 렌더링 분기 필요

### OrchestratorSessionHistoryView
- `OrchestratorAPI.fetchSessions(limit: 50)` + pull-to-refresh
- 상태별 색상 (running 파랑, pending 주황, completed 초록, failed/rejected 빨강)
- 탭 → `OrchestratorSessionDetailSheet`:
  - Header (agent + status + session_id monospace)
  - 명령 / 결과 / 에러 카드
  - LLM 사용량 카드 (input/output/total tokens)
  - 메타 (triggered_by, started_at, ended_at, pending_token)

---

## 기존 기능과의 공존

| 기능 | 담당 Service | 관련 UI |
|------|-------------|---------|
| 녹음 + STT | AudioRecorder, ChunkUploader | LifeLogControlView, SessionListView |
| H3-A 요약 피드백 | FeedbackService | FeedbackView (sheet) |
| H3-A 세션 리스트 (synaptic-memory) | HarnessService | AgentDashboardView (세션 탭) |
| **Phase A 명령 발행** | **OrchestratorAPI** | **CommandInputView** |
| **Phase A HITL 승인** | **OrchestratorAPI** | **ApprovalSheetView** |
| **Phase A 실행 기록** | **OrchestratorAPI** | **OrchestratorSessionHistoryView** |

iOS 앱은 기존 H3-A 기능과 신규 Phase A 기능을 **독립적 namespace**로 같이 유지한다. 모델 이름 충돌 방지를 위해 Phase A 쪽은 `Phase`, `Orchestrator` 접두사 또는 별도 파일 분리.

---

## Commit History (Phase A, iOS)

```
b8f447d  feat(ios): Step 9  — Phase A 에이전트 실행 기록 뷰
62b2f53  feat(ios): Step 6  — Phase A 명령 입력 + HITL 승인 UI
238b4cf  docs:      멀티에이전트 시스템 비전/아키텍처 문서
1465bb9  feat:      에이전트 대시보드 + 개발자 피드백 테스트 버튼 (기존)
5d3dc8f  feat:      H3-A APNs 푸시 + 피드백 UI iOS 통합 (기존)
```

---

## 알려진 갭 (다음 작업)

### 단기 — Phase A 완성
1. **ApprovalSheetView에 diff 렌더링 분기 추가** — CodingAgent approval 지원
   - `approval.toolName == "commit_and_push"`일 때 FileChange 리스트 + full_diff (syntax highlight 선택)
   - 편집 모드는 off (코드 diff는 직접 수정 안 함)
   - 버튼: "승인하여 commit+push" / "거절 (worktree 폐기)"
   - 구현 규모: 1 파일 확장 (~150 lines)

2. **Budget 위젯** — AgentDashboardView 상단에 오늘의 비용 카드
   - `OrchestratorAPI.fetchBudget()` 호출
   - 에이전트별 $0.xx + global 합계 표시
   - 한도 대비 progress bar
   - 구현 규모: 신규 SwiftUI 카드 1개 (~80 lines)

### 중기
3. **Rich approval notifications** — APNs mutable-content + Notification Service Extension으로 custom preview
4. **Session detail에서 tool_calls 표시** — 현재는 session 자체만 표시. `/api/sessions/{id}`로 tool call 이력 가져와서 타임라인 렌더링
5. **Widget Extension 확장** — 홈 화면 위젯에 "pending approvals 수" 배지

### 장기
6. **macOS multiplatform** — 데스크톱에서도 승인 가능 (SwiftUI multiplatform)
7. **Voice command** — 기존 STT 재사용해서 음성으로 명령 발행
8. **Notification categories with quick actions** — 알림 자체에서 "Quick Approve" 가능

---

## 빌드 / 실행

```bash
cd /Users/sonseongjun/Projects/personal/sonlife-app
xcodegen generate       # project.yml → SonlifeApp.xcodeproj
open SonlifeApp.xcodeproj
# 또는 CLI 빌드
xcodebuild -scheme SonlifeApp -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build
```

**서버 URL**: 앱 설정에서 `http://14.6.220.78:8100` (home 서버) 또는 로컬 개발 IP로 변경.

**APNs**: 
- Development 환경은 `aps-environment: development` (Xcode signing 시 자동)
- 실제 푸시 활성화는 서버측 `.p8` 키 필요 (현재는 stub)

---

**이 문서는 2026-04-09 스냅샷.** 새 기능이 추가되면 PHASE-A-STATUS.md와 AGENT-SYSTEM-VISION.md를 함께 갱신한다.
