import Foundation

/// 한 시점의 계정 사용량 스냅샷 — `GET https://ollama.com/api/usage` 응답의 표현.
///
/// 무문서 API다(ADR-0001): 개별 필드의 누락·타입 변화는 그 필드만 nil로 만들고
/// 스냅샷 전체를 실패시키지 않는다. 응답이 JSON 구조 자체가 아니면 throw한다.
/// 도메인 용어는 CONTEXT.md를 따른다.
public struct UsageSnapshot: Equatable, Sendable {

    public struct ModelUsage: Equatable, Sendable {
        public let name: String
        public let requestCount: Int

        public init(name: String, requestCount: Int) {
            self.name = name
            self.requestCount = requestCount
        }
    }

    /// 사용 비율 — 서버가 계산한 [사용 크레딧 ÷ 제공 크레딧] (ADR-0002).
    public let usageRatio: Double?
    /// 표시에 쓰지 않는다 — 디버그 관찰용(ADR-0002).
    public let activityCost: String?
    public let periodType: String?
    /// ISO-8601 원문 — 갱신 예정일 파싱은 별도 계층이 맡는다.
    public let periodStartRaw: String?
    public let periodEndRaw: String?
    /// 모델별 요청 수 내역 (`limits.monthly.models`).
    public let models: [ModelUsage]

    public init(
        usageRatio: Double? = nil,
        activityCost: String? = nil,
        periodType: String? = nil,
        periodStartRaw: String? = nil,
        periodEndRaw: String? = nil,
        models: [ModelUsage] = []
    ) {
        self.usageRatio = usageRatio
        self.activityCost = activityCost
        self.periodType = periodType
        self.periodStartRaw = periodStartRaw
        self.periodEndRaw = periodEndRaw
        self.models = models
    }

    public static func decode(from data: Data) throws -> UsageSnapshot {
        try JSONDecoder().decode(_Root.self, from: data).snapshot
    }
}

// MARK: - 디코딩 내부 표현 (무문서 스키마 — 관대한 파싱)

private struct _Root: Decodable {
    let activity: _Activity?
    let limits: _Limits?

    var snapshot: UsageSnapshot {
        UsageSnapshot(
            usageRatio: limits?.monthly?.usage,
            activityCost: activity?.cost,
            periodType: activity?.period?.type,
            periodStartRaw: activity?.period?.startingAt,
            periodEndRaw: activity?.period?.endingAt,
            models: limits?.monthly?.models ?? []
        )
    }
}

private struct _Activity: Decodable {
    let cost: String?
    let period: _Period?
    // `activity.models`는 관측상 빈 배열이었고 내역의 1차 위치가 아니다(실측 3.7) — 파싱하지 않는다.
}

private struct _Period: Decodable {
    let type: String?
    let startingAt: String?
    let endingAt: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case startingAt = "starting_at"
        case endingAt = "ending_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        startingAt = try? container.decodeIfPresent(String.self, forKey: .startingAt)
        endingAt = try? container.decodeIfPresent(String.self, forKey: .endingAt)
    }
}

private struct _Limits: Decodable {
    let monthly: _Monthly?
}

private struct _Monthly: Decodable {
    let usage: Double?
    let models: [UsageSnapshot.ModelUsage]

    private enum CodingKeys: String, CodingKey { case usage, models }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usage = try? container.decodeIfPresent(Double.self, forKey: .usage)
        let rawModels = (try? container.decodeIfPresent([_ModelUsage].self, forKey: .models)) ?? []
        models = rawModels.map { $0.value }
    }

    private struct _ModelUsage: Decodable {
        let value: UsageSnapshot.ModelUsage

        private enum CodingKeys: String, CodingKey {
            case name
            case requestCount = "request_count"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
            let count = (try? container.decodeIfPresent(Int.self, forKey: .requestCount)) ?? 0
            value = UsageSnapshot.ModelUsage(name: name, requestCount: count)
        }
    }
}