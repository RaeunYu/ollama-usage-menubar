import SwiftUI
import OllamaUsageKit

/// 드롭다운 내용 — 확정 스펙:
/// ① 총(제공) 크레딧(설정 파일) ② 잔여 크레딧 ③ 갱신 예정일 ④ 모델별 요청 수 (API)
struct MenuContent: View {
    @ObservedObject var poller: UsagePoller
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusSection
            Divider()
            Button("지금 새로고침") { poller.refreshNow() }
                .keyboardShortcut("r")
            if let updated = poller.lastUpdated {
                HStack {
                    Text("마지막 갱신")
                    Spacer()
                    Text(Self.timeFormatter.string(from: updated))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Divider()
            Button("API 키 설정…") { openWindow(id: "settings") }
            Button("설정 파일 열기") {
                NSWorkspace.shared.open(poller.configURL)
            }
            Divider()
            Button("Ollama 설정 페이지") {
                if let url = URL(string: "https://ollama.com/settings") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("종료") { NSApp.terminate(nil) }
        }
        .padding(10)
        .frame(width: 280)
        .onAppear { poller.refreshNow() }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch poller.phase {
        case .loading:
            HStack {
                ProgressView().controlSize(.small)
                Text("조회 중…").foregroundStyle(.secondary)
            }

        case .snapshot(let snapshot):
            let pool = poller.config.monthlyPoolUSD
            remainingRow(snapshot, pool: pool)
            row("제공 크레딧", String(format: "$%.2f", pool))
            if let reset = snapshot.resetDate {
                row("갱신 예정일", reset)
            }
            if !snapshot.models.isEmpty {
                Divider()
                ForEach(Array(snapshot.models.enumerated()), id: \.offset) { _, model in
                    HStack {
                        Text(model.name).lineLimit(1)
                        Spacer()
                        Text("\(model.requestCount)회").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }

        case .exhausted:
            Label("제공 크레딧 소진 — ollama.com/settings 에서 충전", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

        case .invalidKey:
            VStack(alignment: .leading, spacing: 4) {
                Label("API 키를 확인하세요", systemImage: "key.fill").foregroundStyle(.orange)
                Button("API 키 설정…") { openWindow(id: "settings") }
            }

        case .rateLimited:
            row("요청 과다로 대기 중", "잠시 후 자동 재시도")

        case .failed(let reason):
            row("조회 실패", reason)
        }
    }

    /// 1번 항목: 제공 크레딧(설정 파일) — 2번 항목: 잔여 크레딧(API) + 퍼센트
    private func remainingRow(_ snapshot: UsageSnapshot, pool: Double) -> some View {
        HStack {
            Text("잔여 크레딧")
            Spacer()
            if let ratio = snapshot.remainingRatio,
               let credits = snapshot.remainingCredits(pool: pool) {
                Text("\(String(format: "$%.2f", credits)) · \(Int((ratio * 100).rounded()))%")
                    .foregroundStyle(poller.config.stage(forRemaining: ratio)?.rgb.swiftColor ?? .primary)
                    .monospacedDigit()
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}