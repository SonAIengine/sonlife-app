# SonLife iOS App

> Personal Life OS — 내 모든 삶을 한곳에 모으고 AI 에이전트가 돕는 시스템의 iOS 클라이언트

SonLife 생태계의 사용자 인터페이스 레이어. 현재는 **음성 녹음 + STT**가 주 기능이지만, 에이전트 컨트롤 타워로 확장될 예정.

## SonLife 전체 아키텍처에서의 위치

```
[외부 데이터 소스]           [SonLife Server (홈서버)]        [SonLife iOS App]
 메일/캘린더/Teams ──┐
 카카오톡 ────────┼──► lifelog_db + Daily Note        ◄──► 음성 녹음
 GitHub/GitLab ──┘       │          │                      세션 관리
 음성 녹음 ◄─────────────┘          │                      에이전트 UI (계획)
                                      ▼
                              [PydanticAI Agents]
                               - CollectorAgent (자동 수집)
                               - SummaryAgent (하루 요약)
                               - BriefingAgent (아침 브리핑)
```

관련 레포:
- [SonAIengine/sonlife](https://github.com/SonAIengine/sonlife) — 백엔드 서버 (STT + lifelog + 에이전트)
- [SonAIengine/obsidian-vault](https://github.com/SonAIengine/obsidian-vault) — 지식 베이스

## 현재 기능 (음성 녹음)

- 🎙️ LifeLog 연속 녹음 (5분 청킹, VAD)
- 📝 실시간 한국어 STT 전사 + 화자 분리/식별 (서버 연동)
- 📂 Manual 녹음 (단일 파일 세션)
- 📍 청크별 GPS + 역지오코딩
- 🏝️ Live Activity / Dynamic Island
- ▶️ 세션 재생 + 세그먼트 하이라이트
- 👥 화자 이름 매핑
- 🧠 LLM 요약 선택 (Claude / Ollama)
- ⚙️ 설정 (서버 URL, 커스텀 용어, 테마)

## 개발 로드맵

### Phase 1 (완료) — 녹음 코어 ✅
- LifeLog 연속 녹음 엔진
- 서버 STT + 화자 분리 연동
- Daily Note 자동 생성 (서버 측)
- Live Activity, 재생 하이라이트

### Phase 2 — lifelog 열람 뷰
- `GET /api/lifelog/entries`로 Daily Note 조회
- 타임라인 뷰 (메일/캘린더/음성/카톡/GitHub 통합)
- 소스별 필터 + 날짜 네비게이션
- 검색 (키워드, 소스, 화자)
- 상세 보기 (원본 링크, 관련 엔트리 추천)

### Phase 3 — 에이전트 컨트롤 타워
- 에이전트 상태 대시보드 (CollectorAgent, SummaryAgent, BriefingAgent)
- 에이전트 수동 트리거 (pull-to-refresh로 수집 즉시 실행)
- 에이전트 로그 뷰
- 스케줄 조정 UI

### Phase 4 — 에이전트 메시지 허브
- 에이전트가 보낸 승인 요청 수신 ("이 메일 보낼까요?")
- 승인 / 거절 / 수정 → 에이전트 실행
- APNs 푸시 알림
- 응답 히스토리

### Phase 5 — 자동화 규칙 엔진
- 사용자 정의 규칙 ("주말에 받은 메일은 자동 요약")
- 규칙 편집 UI
- 규칙 실행 로그

### Phase 6 — 확장
- Apple Watch 연동 (녹음 제어, 알림)
- Widget 강화 (오늘의 브리핑, 미완료 액션아이템)
- 전문검색 (앱 내 lifelog 검색)
- RAG 질의 ("지난주 김교수님이 뭐라고 했지?")

## 기술 스택

- **iOS 17.0+**, Swift 5.9, SwiftUI, @Observable
- **Bundle ID**: com.sonaiengine.voicerecorder (→ com.sonaiengine.sonlife 변경 예정)
- **빌드**: xcodegen + project.yml
- **네트워킹**: URLSession (async/await)
- **서버**: SonLife backend (FastAPI, 8100 포트)

## 빌드

```bash
# xcodegen으로 프로젝트 생성 (project.yml 기반)
xcodegen generate

# Xcode에서 열기
open VoiceRecorder.xcodeproj
```

1. Xcode에서 Signing & Capabilities → Team에 본인 Apple 계정 선택
2. 서버 URL 설정 (앱 설정 → SonLife Server)
3. 아이폰 연결 후 빌드 & 실행

## 요구사항

- iOS 17.0+
- Xcode 16.0+
- 무료 Apple 계정으로 설치 가능 (7일마다 재설치 필요)
- SonLife 백엔드 서버 (LAN 또는 VPN 접근)

## 라이선스

MIT
