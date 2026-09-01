// 마이크로 테스트 러너 (ADR-0005)
//
// 이 CLT 툴체인에는 XCTest와 swift-testing이 모두 없어서, 테스트를 실행 파일로 돌린다.
// 관례: 각 테스트는 `test(...)` 한 호출이고, 실패하면 이름과 사유를 모아 마지막에 exit(1).
// 실행: `swift run usage-tests`

import Foundation
import OllamaUsageKit

private struct CheckError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private var failedCount = 0

@MainActor private func test(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        print("✔ \(name)")
    } catch {
        failedCount += 1
        print("✘ \(name)\n   \(error)")
    }
}

@MainActor private func check<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
    guard actual == expected else {
        throw CheckError(message: "\(label): 기대 \(expected), 실제 \(actual)")
    }
}

// 사용자가 2026-09-01에 직접 취득한 실측 응답 원문.
// 독립된 관측 리터럴 — 기대값은 코드가 아니라 이 관측에서 온다.
private let observedUsageJSON = """
{
    "activity": {
        "cost": "0.00000",
        "period": {
            "type": "last_4_weeks",
            "starting_at": "2026-08-10T00:00:00Z",
            "ending_at": "2026-09-01T08:45:10.076049294Z"
        },
        "models": []
    },
    "limits": {
        "monthly": {
            "usage": 0.002,
            "models": [
                {
                    "name": "glm-5.3-flash",
                    "request_count": 29
                },
                {
                    "name": "web search",
                    "request_count": 4
                },
                {
                    "name": "gpt-oss:120b",
                    "request_count": 1
                }
            ]
        }
    }
}
"""

test("실측 /api/usage 응답이 UsageSnapshot으로 디코드된다") {
    let snapshot = try UsageSnapshot.decode(from: Data(observedUsageJSON.utf8))

    try check(snapshot.usageRatio, 0.002, "사용 비율")
    try check(snapshot.activityCost, "0.00000", "activity.cost (디버그 관찰용)")
    try check(snapshot.periodType, "last_4_weeks", "기간 타입")
    try check(snapshot.periodStartRaw, "2026-08-10T00:00:00Z", "기간 시작")
    try check(snapshot.periodEndRaw, "2026-09-01T08:45:10.076049294Z", "기간 종료")
    try check(
        snapshot.models,
        [
            UsageSnapshot.ModelUsage(name: "glm-5.3-flash", requestCount: 29),
            UsageSnapshot.ModelUsage(name: "web search", requestCount: 4),
            UsageSnapshot.ModelUsage(name: "gpt-oss:120b", requestCount: 1),
        ],
        "모델별 요청 수 내역"
    )
}

test("깨진·빠진 필드가 있어도 스냅샷 전체는 실패하지 않는다 (무문서 API 대응)") {
    // limits가 통째로 없어도 디코드된다 (ADR-0001)
    let noLimits = try UsageSnapshot.decode(from: Data(#"{"activity": {"cost": "0.5"}}"#.utf8))
    try check(noLimits.usageRatio, Optional<Double>.none, "usage 누락 → nil")
    try check(noLimits.models, [], "models 누락 → 빈 배열")

    // usage가 숫자가 아니게 변해도(스키마 변화 가정) 나머지는 산다
    let stringUsage = #"{"limits":{"monthly":{"usage":"0.5","models":[]}}}"#
    let tolerant = try UsageSnapshot.decode(from: Data(stringUsage.utf8))
    try check(tolerant.usageRatio, Optional<Double>.none, "usage 타입 변화 → nil")
    try check(tolerant.models, [], "usage 타입이 변해도 models는 유지")

    // 모르는 필드·모델의 추가 필드는 무시된다
    let withUnknowns = #"{"activity":{"cost":"0.1","brand_new_field":42},"limits":{"monthly":{"usage":0.25,"models":[{"name":"glm-5.3-flash","request_count":7,"future_field":[1,2]}]}}}"#
    let unknown = try UsageSnapshot.decode(from: Data(withUnknowns.utf8))
    try check(unknown.usageRatio, 0.25, "미지 필드와 무관하게 파싱")
    try check(unknown.models.first?.name, "glm-5.3-flash", "모델의 미지 필드 무시")
    try check(unknown.models.first?.requestCount, 7, "request_count 파싱")
}

if failedCount > 0 {
    print("\n실패 \(failedCount)건")
    exit(1)
}
print("\n모든 테스트 통과")