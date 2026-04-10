import SwiftUI

/// C-3 Skill Picker — 스킬 선택 + 인자 입력 + 실행
///
/// 서버의 /api/skills에서 스킬 목록을 로드하고,
/// 사용자가 고르면 required args 폼을 표시, 입력 후 /api/skills/{name}/run 호출.
struct SkillPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var skills: [Skill] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedSkill: Skill?
    @State private var argValues: [String: String] = [:]
    @State private var isRunning = false
    @State private var lastResponse: CommandResponse?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("스킬 불러오는 중...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage, skills.isEmpty {
                    ContentUnavailableView(
                        "스킬 로드 실패",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if let skill = selectedSkill {
                    skillDetailForm(skill)
                } else {
                    skillList
                }
            }
            .navigationTitle(selectedSkill?.name ?? "스킬")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if selectedSkill != nil {
                        Button("목록") {
                            selectedSkill = nil
                            argValues = [:]
                            lastResponse = nil
                        }
                    } else {
                        Button("닫기") { dismiss() }
                    }
                }
            }
            .task { await loadSkills() }
        }
    }

    // MARK: - List

    private var skillList: some View {
        List(skills) { skill in
            Button {
                selectSkill(skill)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(skill.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(skill.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Detail form

    private func skillDetailForm(_ skill: Skill) -> some View {
        Form {
            Section {
                Text(skill.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("설명")
            }

            if !skill.args.isEmpty {
                Section {
                    ForEach(skill.args) { arg in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(arg.name)
                                    .font(.subheadline.weight(.medium))
                                if arg.required {
                                    Text("필수")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }
                                Spacer()
                            }
                            if !arg.description.isEmpty {
                                Text(arg.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            TextField(
                                arg.defaultValue ?? "입력",
                                text: bindingForArg(arg.name),
                                axis: .vertical
                            )
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...3)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("인자")
                }
            }

            if let response = lastResponse {
                Section {
                    HStack {
                        Image(systemName: statusIcon(response.status))
                            .foregroundStyle(statusColor(response.status))
                        Text(response.status.rawValue)
                            .font(.caption)
                    }
                    Text("Session: \(response.commandId.prefix(16))...")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } header: {
                    Text("결과")
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await runSkill(skill) }
            } label: {
                Group {
                    if isRunning {
                        ProgressView()
                    } else {
                        Label("실행", systemImage: "play.fill")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
            .disabled(isRunning || !isFormValid(skill))
        }
    }

    // MARK: - Actions

    private func selectSkill(_ skill: Skill) {
        selectedSkill = skill
        argValues = [:]
        for arg in skill.args {
            if let def = arg.defaultValue {
                argValues[arg.name] = def
            }
        }
        errorMessage = nil
        lastResponse = nil
    }

    private func bindingForArg(_ name: String) -> Binding<String> {
        Binding(
            get: { argValues[name, default: ""] },
            set: { argValues[name] = $0 }
        )
    }

    private func isFormValid(_ skill: Skill) -> Bool {
        for arg in skill.args where arg.required {
            if argValues[arg.name]?.trimmingCharacters(in: .whitespaces).isEmpty ?? true {
                return false
            }
        }
        return true
    }

    @MainActor
    private func loadSkills() async {
        isLoading = true
        errorMessage = nil
        do {
            skills = try await OrchestratorAPI.fetchSkills()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func runSkill(_ skill: Skill) async {
        isRunning = true
        errorMessage = nil
        do {
            let response = try await OrchestratorAPI.runSkill(name: skill.name, args: argValues)
            lastResponse = response
            // 명령 전송 직후 인박스로 자동 복귀
            try? await Task.sleep(for: .milliseconds(800))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isRunning = false
    }

    // MARK: - Helpers

    private func statusIcon(_ s: PhaseASessionStatus) -> String {
        switch s {
        case .running: return "circle.dotted"
        case .pendingHITL: return "hourglass"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .rejected: return "minus.circle.fill"
        }
    }

    private func statusColor(_ s: PhaseASessionStatus) -> Color {
        switch s {
        case .running: return .blue
        case .pendingHITL: return .orange
        case .completed: return .green
        case .failed, .rejected: return .red
        }
    }
}
