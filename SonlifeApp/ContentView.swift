import AVFoundation
import SwiftUI

enum AppMode: String, CaseIterable {
    case lifeLog = "LifeLog"
    case manual = "녹음"
    case agent = "에이전트"
}

struct FeedbackContext: Identifiable {
    let id = UUID()
    let sessionId: String
    let summary: String
}

struct ContentView: View {
    @State private var recorder = AudioRecorder()
    @State private var mode: AppMode = .lifeLog
    @State private var feedbackContext: FeedbackContext?

    var body: some View {
        VStack(spacing: 0) {
            // 모드 선택
            Picker("Mode", selection: $mode) {
                ForEach(AppMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // 탭별 독립 NavigationStack
            switch mode {
            case .lifeLog:
                NavigationStack {
                    LifeLogView(recorder: recorder)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    SettingsView()
                                } label: {
                                    Image(systemName: "gearshape")
                                }
                            }
                        }
                }
            case .manual:
                NavigationStack {
                    ManualRecordingView(recorder: recorder)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    SettingsView()
                                } label: {
                                    Image(systemName: "gearshape")
                                }
                            }
                        }
                }
            case .agent:
                NavigationStack {
                    AgentDashboardView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    SettingsView()
                                } label: {
                                    Image(systemName: "gearshape")
                                }
                            }
                        }
                }
            }
        }
        .alert("오류", isPresented: .init(
            get: { recorder.errorMessage != nil },
            set: { if !$0 { recorder.errorMessage = nil } }
        )) {
            Button("확인") { recorder.errorMessage = nil }
        } message: {
            Text(recorder.errorMessage ?? "")
        }
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

// MARK: - LifeLog Tab

struct LifeLogView: View {
    @Bindable var recorder: AudioRecorder

    var body: some View {
        VStack(spacing: 0) {
            LifeLogControlView(recorder: recorder)
                .padding(.top, 8)

            SessionListView(sessionManager: recorder.sessionManager, recorder: recorder)
        }
        .navigationTitle("LifeLog")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Manual Recording Tab

struct ManualRecordingView: View {
    @Bindable var recorder: AudioRecorder

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(recorder.recordings) { recording in
                    NavigationLink {
                        RecordingDetailView(recording: recording, recorder: recorder)
                    } label: {
                        RecordingRow(recording: recording)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        recorder.deleteRecording(recorder.recordings[index])
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if recorder.recordings.isEmpty {
                    ContentUnavailableView(
                        "녹음이 없습니다",
                        systemImage: "mic.slash",
                        description: Text("아래 버튼을 눌러 녹음을 시작하세요")
                    )
                }
            }

            RecordingControlView(recorder: recorder)
                .padding()
        }
        .navigationTitle("녹음")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Recording Row

struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(recording.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                Spacer()
                Text(formatDuration(recording.duration))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let transcript = recording.transcript {
                Text(transcript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("STT 변환 중...")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Recording Control

struct RecordingControlView: View {
    @Bindable var recorder: AudioRecorder

    var body: some View {
        VStack(spacing: 12) {
            // 타이머 — 항상 고정 높이 확보
            Text(recorder.isRecording ? formatTime(recorder.currentTime) : " ")
                .font(.system(.title, design: .monospaced))
                .foregroundStyle(recorder.isRecording ? .red : .clear)
                .frame(height: 36)

            HStack(spacing: 32) {
                if recorder.isRecording {
                    // 일시정지/재개
                    Button {
                        if recorder.isPaused {
                            recorder.resumeRecording()
                        } else {
                            recorder.pauseRecording()
                        }
                    } label: {
                        Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                            .font(.title2)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Color(.secondarySystemFill)))
                    }
                    .accessibilityLabel(recorder.isPaused ? "재개" : "일시정지")

                    // 정지
                    Button {
                        recorder.stopRecording()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(.red))
                    }
                    .accessibilityLabel("녹음 중지")
                } else {
                    // 녹음 시작
                    Button {
                        recorder.startRecording()
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(.red))
                    }
                    .accessibilityLabel("녹음 시작")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let tenths = Int((time - Double(Int(time))) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}
