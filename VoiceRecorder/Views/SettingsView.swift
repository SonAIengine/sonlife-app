import SwiftUI

enum AppTheme: String, CaseIterable {
    case system = "시스템"
    case light = "라이트"
    case dark = "다크"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SettingsView: View {
    @State private var serverURL: String = ChunkUploader.shared.currentServerURL
    @State private var testStatus: TestStatus = .idle
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue
    @AppStorage("stt_vocabulary") private var vocabulary: String = ""
    @AppStorage("llm_provider") private var llmProvider: String = "off"
    @AppStorage("ollama_model") private var ollamaModel: String = ""
    @State private var availableModels: [OllamaModel] = []
    @State private var isLoadingModels = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("화면 모드") {
                Picker("테마", selection: $selectedTheme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.rawValue).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                TextField("자주 사용하는 용어를 입력하세요", text: $vocabulary, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("커스텀 용어")
            } footer: {
                Text("STT 인식률을 높이기 위한 힌트 (예: 데이터 마이닝, 레벤슈타인, RNN)")
            }

            Section {
                Picker("AI 요약", selection: $llmProvider) {
                    Text("사용 안 함").tag("off")
                    Text("Claude (Haiku)").tag("claude")
                    Text("Ollama (로컬)").tag("ollama")
                }
                .onChange(of: llmProvider) { _, newValue in
                    if newValue == "ollama" {
                        loadOllamaModels()
                    }
                }

                if llmProvider == "ollama" {
                    if isLoadingModels {
                        HStack {
                            Text("모델 로딩 중...")
                            Spacer()
                            ProgressView()
                        }
                    } else if !availableModels.isEmpty {
                        Picker("Ollama 모델", selection: $ollamaModel) {
                            ForEach(availableModels, id: \.name) { model in
                                Text("\(model.name) (\(model.sizeText))").tag(model.name)
                            }
                        }
                    } else {
                        Button("모델 목록 새로고침") {
                            loadOllamaModels()
                        }
                    }
                }
            } header: {
                Text("AI 요약")
            } footer: {
                switch llmProvider {
                case "claude": Text("Anthropic API 키 필요 (서버 .env에 설정)")
                case "ollama": Text("Home 서버의 Ollama 모델로 요약")
                default: Text("세션 종료 시 Obsidian에 AI 요약이 추가됩니다")
                }
            }

            Section("STT 서버") {
                TextField("서버 URL", text: $serverURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button {
                    testConnection()
                } label: {
                    HStack {
                        Text("연결 테스트")
                        Spacer()
                        switch testStatus {
                        case .idle:
                            EmptyView()
                        case .testing:
                            ProgressView()
                        case .success(let info):
                            Text(info)
                                .font(.caption)
                                .foregroundStyle(.green)
                        case .failure(let msg):
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .disabled(testStatus == .testing)
            }

            Section {
                Button("저장") {
                    ChunkUploader.shared.currentServerURL = serverURL
                    dismiss()
                }
                .disabled(serverURL.isEmpty)
            }
        }
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func testConnection() {
        testStatus = .testing
        guard let url = URL(string: serverURL)?.appendingPathComponent("api/health") else {
            testStatus = .failure("잘못된 URL")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error {
                    testStatus = .failure(error.localizedDescription)
                    return
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    testStatus = .failure("서버 응답 오류")
                    return
                }
                if let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String, status == "ok" {
                    let whisper = (json["whisper"] as? [String: Any])?["model"] as? String ?? "?"
                    testStatus = .success(whisper)
                } else {
                    testStatus = .failure("응답 파싱 실패")
                }
            }
        }.resume()
    }

    private func loadOllamaModels() {
        isLoadingModels = true
        guard let url = URL(string: serverURL)?.appendingPathComponent("api/llm/models") else {
            isLoadingModels = false
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                isLoadingModels = false
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = json["models"] as? [[String: Any]] else {
                    return
                }
                availableModels = models.compactMap { dict in
                    guard let name = dict["name"] as? String else { return nil }
                    let size = dict["size"] as? Int64 ?? 0
                    return OllamaModel(name: name, size: size)
                }
                if ollamaModel.isEmpty, let first = availableModels.first {
                    ollamaModel = first.name
                }
            }
        }.resume()
    }

    private enum TestStatus: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }
}

struct OllamaModel {
    let name: String
    let size: Int64

    var sizeText: String {
        let gb = Double(size) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1fGB", gb)
        }
        return String(format: "%.0fMB", Double(size) / 1_048_576)
    }
}
