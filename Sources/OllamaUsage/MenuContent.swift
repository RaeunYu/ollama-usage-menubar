import SwiftUI
import OllamaUsageKit

/// 드롭다운 내용 — 전부 Balance API가 주는 값으로 구성한다:
/// ① 잔여 크레딧(+퍼센트) ② 제공 크레딧 ③ 플랜 시작일 ④ 플랜 초기화
///
/// 모델별 사용량 내역은 API 변경으로 사라졌다(/api/usage에서 제거, 어디에서도 확인 불가).
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
                    Text(Self.timeText(updated))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Divider()
            Button("API 키 설정…") { openWindow(id: "settings") }
            Button("설정 파일 열기") {
                NSWorkspace.shared.open(poller.configURL)
            }
            Button("원문 JSON 복사") {
                if let raw = poller.lastRawJSON {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(String(decoding: raw, as: UTF8.self), forType: .string)
                }
            }
            .disabled(poller.lastRawJSON == nil)
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

        case .balance(let snapshot):
            remainingRow(snapshot)
            if let allowance = snapshot.allowanceUSD {
                row("제공 크레딧", String(format: "$%.2f", allowance))
            }
            if let start = snapshot.planStart {
                row("플랜 시작일", Self.dateText(start))
            }
            if let reset = snapshot.planReset {
                row("플랜 초기화", Self.dateText(reset))
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

    /// 잔여 크레딧(API) — 달러와 퍼센트를 함께, 색은 설정 파일의 단계 색
    private func remainingRow(_ snapshot: BalanceSnapshot) -> some View {
        HStack {
            Text("잔여 크레딧")
            Spacer()
            if let remaining = snapshot.remainingUSD {
                let ratio = snapshot.remainingRatio
                let percent = ratio.map { " · \(Int(($0 * 100).rounded()))%" } ?? ""
                Text("\(String(format: "$%.2f", remaining))\(percent)")
                    .foregroundStyle(ratio.flatMap { poller.config.stage(forRemaining: $0)?.rgb.swiftColor } ?? .primary)
                    .monospacedDigit()
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    /// 시각은 사용자 로컬 기준 시:분:초로 보여준다 (마지막 갱신)
    private static func timeText(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// 플랜 시작·초기화는 사용자 로컬 기준 날짜로 보여준다
    private static func dateText(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
