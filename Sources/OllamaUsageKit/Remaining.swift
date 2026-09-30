import Foundation

// 잔여 계산 (ADR-0002: 계산 주체를 서버 값 한 곳으로 고정).
//
// 잔여 비율 = 1 − 사용 비율 (서버 제공 비율 1순위 — CONTEXT.md)
// 잔여 크레딧 = 제공 크레딧(Pool) × 잔여 비율
//
// 갱신 예정일은 여기가 아니라 BillingCycle이 계산한다 — API의 period 필드는
// 롤링 윈도우(끝 = 관측 시각)라 갱신일로 쓸 수 없다 (ADR-0007).

extension UsageSnapshot {

    /// 잔여 비율 — 사용 비율이 없으면 nil, 범위 밖이면 0...1로 고정한다.
    public var remainingRatio: Double? {
        guard let usage = usageRatio else { return nil }
        return min(max(1 - usage, 0), 1)
    }

    /// 잔여 크레딧 — 제공 크레딧(Pool)과 잔여 비율의 곱. 사용 비율을 모르면 nil.
    public func remainingCredits(pool: Double) -> Double? {
        remainingRatio.map { $0 * pool }
    }
}