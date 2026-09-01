import SwiftUI
import OllamaUsageKit

@main
struct OllamaUsageApp: App {
    @StateObject private var poller: UsagePoller

    init() {
        if LabelPreview.renderAndExitIfRequested() {
            exit(0)
        }
        let poller = UsagePoller(configURL: AppConfig.defaultURL)
        poller.start()
        _poller = StateObject(wrappedValue: poller)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(poller: poller)
        } label: {
            Image(nsImage: StatusLabelRenderer.image(phase: poller.phase, config: poller.config))
                .renderingMode(.original) // 템플릿 변환 방지 — 단계 색상을 그대로
                .accessibilityLabel("Ollama Usage")
        }
        .menuBarExtraStyle(.window)

        Window("Ollama Usage 설정", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}

/// 첫 실행 온보딩과 재설정: API 키를 Keychain에 저장한다(ADR-0003 — 파일에 절대 저장하지 않음).
struct SettingsView: View {
    @State private var apiKey = ""
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ollama API 키")
                .font(.headline)

            Text("키는 macOS 키체인에만 저장되며 이 앱 외부로 나가지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("OLLAMA_API_KEY", text: $apiKey)

            HStack {
                Button("저장") {
                    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    APIKeyStore.save(trimmed)
                    apiKey = ""
                    status = "키체인에 저장했습니다."
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("삭제", role: .destructive) {
                    APIKeyStore.delete()
                    status = "키체인에서 키를 삭제했습니다."
                }

                Spacer()

                Button("키 발급 페이지") {
                    if let url = URL(string: "https://ollama.com/settings/keys") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("설정 파일 열기 (제공 크레딧 · 폴링 · 색상)") {
                NSWorkspace.shared.open(AppConfig.defaultURL)
            }

            Text("설정 파일 위치: ~/Library/Application Support/OllamaUsage/config.json")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 360)
    }
}