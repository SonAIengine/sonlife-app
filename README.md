# VoiceRecorder

iOS 음성 녹음 앱 — 백그라운드 녹음, 자동 STT 변환, 파일 공유

## 기능

- 🎙️ 백그라운드 녹음 (앱 전환 후에도 계속 녹음)
- 📝 자동 한국어 STT 변환 (Apple Speech Framework, 온디바이스)
- 📂 녹음 파일(.m4a) + 텍스트(.txt) Files 앱/공유 시트로 내보내기
- ⏯️ 재생, 일시정지, 10초 앞/뒤 이동
- 🗑️ 녹음 삭제

## 요구사항

- iOS 17.0+
- Xcode 16.0+
- 무료 Apple 계정으로 설치 가능 (7일마다 재설치 필요)

## 빌드

```bash
# xcodegen으로 프로젝트 생성 (project.yml 기반)
xcodegen generate

# Xcode에서 열기
open VoiceRecorder.xcodeproj
```

1. Xcode에서 Signing & Capabilities → Team에 본인 Apple 계정 선택
2. 아이폰 연결 후 빌드 & 실행

## 라이선스

MIT
