import Foundation

/// `GET https://ollama.com/api/balance` 응답의 표현 — 공식 문서: https://docs.ollama.com/api/balance.md
///
/// 제공 크레딧(`allowance_usd`), 잔여 크레딧(`included.balance_usd`), 추가 결제 잔액
/// (`purchased.balance_usd`), 플랜 주기(`period.from` / `period.until`)를 담는다.
/// 기간별 사용 통계인 `/api/usage`는 이 앱의 목적(잔여 크레딧 표시)에 쓰지 않는다 (ADR-0008).
///
/// 잎 필드는 모두 관대하게 파싱한다 — 한 필드의 변형이 스냅샷 전체를 죽이지 않는다.
/// 응답이 JSON 구조 자체가 아니면 throw한다.
public struct BalanceSnapshot: Equatable, Sendable {

    /// 제공 크레딧 (USD) — 플랜이 이번 주기에 부여한 금액
    public let allowanceUSD: Double?
    /// 잔여 크레딧 (USD) — 포함 크레딧의 남은 금액. 서버 값 그대로 쓰고 계산하지 않는다.
    public let remainingUSD: Double?
    /// 추가 결제 크레딧 잔액 (USD) — 지금은 표시하지 않고 보관만 한다
    public let purchasedUSD: Double?
    /// 플랜 시작 시각 (`period.from`)
    public let planStart: Date?
    /// 플랜 초기화 시각 (`period.until`)
    public let planReset: Date?

    public init(
        allowanceUSD: Double? = nil,
        remainingUSD: Double? = nil,
        purchasedUSD: Double? = nil,
        planStart: Date? = nil,
        planReset: Date? = nil
    ) {
        self.allowanceUSD = allowanceUSD
        self.remainingUSD = remainingUSD
        self.purchasedUSD = purchasedUSD
        self.planStart = planStart
        self.planReset = planReset
    }

    /// 잔여 비율 — 잔여 크레딧 ÷ 제공 크레딧. 제공량이 없거나 0이면 nil, 범위 밖이면 0...1로 고정.
    public var remainingRatio: Double? {
        guard let remaining = remainingUSD, let allowance = allowanceUSD, allowance > 0 else { return nil }
        return min(max(remaining / allowance, 0), 1)
    }

    public static func decode(from data: Data) throws -> BalanceSnapshot {
        try JSONDecoder().decode(_Payload.self, from: data).snapshot
    }
}

// MARK: - 디코딩 내부 표현 (공식 스키마 — 그래도 잎은 관대하게)

private struct _Payload: Decodable {
    let included: _Included?
    let purchased: _Purchased?

    var snapshot: BalanceSnapshot {
        BalanceSnapshot(
            allowanceUSD: included?.allowanceUSD,
            remainingUSD: included?.balanceUSD,
            purchasedUSD: purchased?.balanceUSD,
            planStart: included?.period?.from,
            planReset: included?.period?.until
        )
    }
}

private struct _Included: Decodable {
    let balanceUSD: Double?
    let allowanceUSD: Double?
    let period: _Period?

    private enum CodingKeys: String, CodingKey {
        case balanceUSD = "balance_usd"
        case allowanceUSD = "allowance_usd"
        case period
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        balanceUSD = try? container.decodeIfPresent(Double.self, forKey: .balanceUSD)
        allowanceUSD = try? container.decodeIfPresent(Double.self, forKey: .allowanceUSD)
        period = try? container.decodeIfPresent(_Period.self, forKey: .period)
    }
}

private struct _Purchased: Decodable {
    let balanceUSD: Double?

    private enum CodingKeys: String, CodingKey { case balanceUSD = "balance_usd" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        balanceUSD = try? container.decodeIfPresent(Double.self, forKey: .balanceUSD)
    }
}

private struct _Period: Decodable {
    let from: Date?
    let until: Date?

    private enum CodingKeys: String, CodingKey { case from, until }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fromRaw: String? = (try? container.decodeIfPresent(String.self, forKey: .from)) ?? nil
        let untilRaw: String? = (try? container.decodeIfPresent(String.self, forKey: .until)) ?? nil
        from = fromRaw.flatMap(parseISO8601)
        until = untilRaw.flatMap(parseISO8601)
    }
}

/// ISO-8601 시각 — 소수점 초가 붙은 형식과 아닌 형식 모두 받는다.
/// Swift 6에서 ISO8601DateFormatter는 Sendable이 아니라 전역 상수로 둘 수 없어 매번 만든다(폴링당 1회).
private func parseISO8601(_ text: String) -> Date? {
    let withFractionalSeconds = ISO8601DateFormatter()
    withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractionalSeconds.date(from: text) { return date }

    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: text)
}
