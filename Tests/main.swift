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

test("잔여 비율은 1 − 사용 비율이고, 잔여 크레딧은 제공 크레딧과의 곱이다") {
    let snapshot = try UsageSnapshot.decode(from: Data(observedUsageJSON.utf8))

    // 사용 비율 0.002 → 잔여 비율 0.998 (독립 계산: 1 − 0.002)
    try checkNear(snapshot.remainingRatio, 0.998, "잔여 비율")
    try checkNear(snapshot.remainingCredits(pool: 60), 59.88, "잔여 크레딧 ($60 풀 기준)")
}

test("사용 비율이 범위를 벗어나면 잔여 비율은 0..1로 고정된다") {
    // extra usage 로 풀을 넘어 쓴 경우 (소진 이상)
    let over = try UsageSnapshot.decode(from: Data(#"{"limits":{"monthly":{"usage":1.2,"models":[]}}}"#.utf8))
    try check(over.remainingRatio, 0.0, "풀 초과 사용 → 잔여 0")
    let garbage = try UsageSnapshot.decode(from: Data(#"{"limits":{"monthly":{"usage":-0.5,"models":[]}}}"#.utf8))
    try check(garbage.remainingRatio, 1.0, "비정상 음수 비율 → 잔여 1")
}

test("갱신 예정일은 기간 종료의 날짜(YYYY-MM-DD)뿐이다") {
    let snapshot = try UsageSnapshot.decode(from: Data(observedUsageJSON.utf8))
    try check(snapshot.resetDate, "2026-09-01", "실측 응답의 갱신 예정일")

    // 자정 직전 종료도 UTC 날짜 기준으로 읽는다 (로컬 타임존으로 넘어가지 않게)
    let lateNight = try UsageSnapshot.decode(from: Data(#"{"activity":{"period":{"ending_at":"2026-09-30T23:59:59.123Z"}}}"#.utf8))
    try check(lateNight.resetDate, "2026-09-30", "UTC 날짜 기준")

    // 기간이 아예 없거나 깨져 있으면 nil
    let missing = try UsageSnapshot.decode(from: Data(#"{"limits":{"monthly":{}}}"#.utf8))
    try check(missing.resetDate, Optional<String>.none, "기간 누락 → nil")
}

private func checkNear(_ actual: Double?, _ expected: Double, _ label: String) throws {
    guard let actual else { throw CheckError(message: "\(label): nil (기대 \(expected))") }
    guard abs(actual - expected) < 1e-9 else {
        throw CheckError(message: "\(label): 기대 \(expected), 실제 \(actual)")
    }
}

// MARK: - 설정 파일 seam

@MainActor private func uniqueConfigURL() -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ollama-usage-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("config.json")
}

test("설정 파일이 없으면 기본값으로 만들어 돌려준다") {
    let url = uniqueConfigURL()
    let config = AppConfig.loadOrCreate(at: url)

    try check(FileManager.default.fileExists(atPath: url.path), true, "기본 파일 생성")
    try check(config.monthlyPoolUSD, 60.0, "기본 제공 크레딧 ($60 — 사용자 플랜)")
    try check(config.pollingIntervalSeconds, 60.0, "기본 폴링 간격")

    // 생성된 파일은 스스로를 설명한다 (한국어 description)
    let written = try String(contentsOf: url, encoding: .utf8)
    try check(written.contains("description"), true, "description 키 존재")
    try check(written.contains("제공 크레딧"), true, "한국어 설명 존재")

    // 다시 읽어도 같은 값
    let reloaded = AppConfig.loadOrCreate(at: url)
    try check(reloaded, config, "재로드 일관성")
}

test("사용자가 고친 값과 색상 단계가 그대로 읽힌다") {
    let url = uniqueConfigURL()
    let custom = """
    {
        "monthly_pool_usd": {"description": "제공 크레딧", "value": 300},
        "polling_interval_seconds": {"description": "폴링 간격", "value": 120},
        "color_stages": {
            "description": "구간별 색상",
            "value": [
                {"remaining_at_least": 0.8, "hex": "#028384"},
                {"remaining_at_least": 0.0, "hex": "#000000"}
            ]
        }
    }
    """
    try custom.write(to: url, atomically: true, encoding: .utf8)

    let config = AppConfig.loadOrCreate(at: url)
    try check(config.monthlyPoolUSD, 300.0, "제공 크레딧 300")
    try check(config.pollingIntervalSeconds, 120.0, "폴링 120초")
    try check(config.colorStages.count, 2, "단계 수")
    try check(config.stage(forRemaining: 0.9)?.rgb, AppConfig.RGB(hex: "#028384"), "0.9 → 첫 단계 색")
    try check(config.stage(forRemaining: 0.5)?.rgb, AppConfig.RGB(hex: "#000000")!, "0.8 미만 → 둘째 단계")
}

test("폴링 간격은 10..300으로 고정된다") {
    let wide = uniqueConfigURL()
    try #"{"polling_interval_seconds": {"value": 9999}}"#.write(to: wide, atomically: true, encoding: .utf8)
    try check(AppConfig.loadOrCreate(at: wide).pollingIntervalSeconds, 300.0, "너무 큰 폴링 → 300")

    let narrow = uniqueConfigURL()
    try #"{"polling_interval_seconds": {"value": 3}}"#.write(to: narrow, atomically: true, encoding: .utf8)
    try check(AppConfig.loadOrCreate(at: narrow).pollingIntervalSeconds, 10.0, "너무 짧은 폴링 → 10")
}

test("잘못된 색상 단계는 기본 팔레트로 돌아간다") {
    let url = uniqueConfigURL()
    try #"{"color_stages": {"value": [{"remaining_at_least": 0.4, "hex": "zzz"}]}}"#.write(to: url, atomically: true, encoding: .utf8)
    let config = AppConfig.loadOrCreate(at: url)
    try check(config.colorStages, AppConfig.defaultColorStages, "hex가 깨진 단계 → 기본 팔레트")
}

test("전체가 깨진 JSON이면 기본값을 돌려주되 사용자 파일은 그대로 둔다") {
    let url = uniqueConfigURL()
    try "{broken".write(to: url, atomically: true, encoding: .utf8)
    let config = AppConfig.loadOrCreate(at: url)
    try check(config, AppConfig(), "깨진 JSON → 기본값")
    let stillBroken = try String(contentsOf: url, encoding: .utf8)
    try check(stillBroken == "{broken", true, "파일을 건드리지 않음")
}

if failedCount > 0 {
    print("\n실패 \(failedCount)건")
    exit(1)
}
print("\n모든 테스트 통과")