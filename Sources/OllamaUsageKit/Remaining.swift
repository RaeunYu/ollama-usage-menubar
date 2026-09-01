import Foundation

// 잔여 계산과 갱신 예정일 (ADR-0002: 계산 주체를 서버 값 한 곳으로 고정).
//
// 잔여 비율 = 1 − 사용 비율 (서버 제공 비율 1순위 — CONTEXT.md)
// 잔여 크레딧 = 제공 크레딧(Pool) × 잔여 비율
// 갱신 예정일 = 사용량 조회 응답의 기간 종료에서 날짜(YYYY-MM-DD)만 취함

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

    /// 갱신 예정일 — 기간 종료 시각의 날짜 부분(YYYY-MM-DD).
    /// 로컬 타임존으로 넘기지 않게 UTC 문자열의 날짜 부분만 취한다.
    public var resetDate: String? {
        guard let end = periodEndRaw else { return nil }
        let datePart = String(end.prefix(10))
        guard isCalendarDate(datePart) else { return nil }
        return datePart
    }
}

private func isCalendarDate(_ text: String) -> Bool {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return false }
    let shape = [4, 2, 2]
    return zip(parts, shape).allSatisfy { part, length in
        part.count == length && part.allSatisfy { $0.isNumber }
    }
}