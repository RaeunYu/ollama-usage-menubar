import Foundation
import OllamaUsageKit

/// 잔액 폴링 루프 — 설정 파일을 매 주기 다시 읽고, 결과를 화면 상태로 옮긴다.
///
/// 폴링 규칙(확정 스펙): 기본 60초, 설정 파일에서 간격 조절, 429면 간격을 2배씩 늘려
/// 최대 10분까지 백오프하고 성공하면 되돌린다. 메뉴를 열면 즉시 1회 다시 조회.
@MainActor
final class UsagePoller: ObservableObject {

    enum Phase: Equatable {
        case loading
        case balance(BalanceSnapshot)
        case exhausted
        case invalidKey
        case rateLimited
        case failed(reason: String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var config = AppConfig()
    /// 마지막 /api/balance 응답 원문 — 스키마가 또 바뀌었을 때 확인할 관측 창구.
    @Published private(set) var lastRawJSON: Data?

    let configURL: URL

    private var loopTask: Task<Void, Never>?
    private var rateLimitedStreak = 0

    init(configURL: URL = AppConfig.defaultURL) {
        self.configURL = configURL
    }

    func start() {
        guard loopTask == nil else { return }
        startLoop()
    }

    /// 즉시 갱신 — 메뉴를 열 때 호출. 백오프도 되돌린다.
    func refreshNow() {
        loopTask?.cancel()
        startLoop()
    }

    private func startLoop() {
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
            }
        }
    }

    private func pollOnce() async {
        let loaded = AppConfig.loadOrCreate(at: configURL)
        config = loaded

        let client = BalanceClient(
            apiKeyProvider: { APIKeyStore.load() },
            perform: BalanceClient.urlSessionTransport()
        )
        let outcome = await client.fetchBalance()

        switch outcome {
        case .balance(let snapshot, let rawJSON):
            phase = .balance(snapshot)
            lastRawJSON = rawJSON
            lastUpdated = Date()
            rateLimitedStreak = 0
        case .exhausted:
            phase = .exhausted
            lastUpdated = Date()
            rateLimitedStreak = 0
        case .invalidKey:
            phase = .invalidKey
            rateLimitedStreak = 0
        case .rateLimited:
            phase = .rateLimited
            rateLimitedStreak += 1
        case .failed(let reason):
            phase = .failed(reason: reason)
        }

        // 429가 이어지면 간격을 두 배씩 늘려 최대 10분까지 백오프한다.
        let factor = pow(2.0, Double(rateLimitedStreak))
        let delay = min(loaded.pollingIntervalSeconds * factor, 600)
        do {
            try await Task.sleep(for: .seconds(delay))
        } catch {
            // 취소됨 — 루프 종료
        }
    }
}
