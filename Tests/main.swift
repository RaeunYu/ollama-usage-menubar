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

@MainActor private func test(_ name: String, _ body: () async throws -> Void) async {
    do {
        try await body()
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

await test("실측 /api/usage 응답이 UsageSnapshot으로 디코드된다") {
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

await test("깨진·빠진 필드가 있어도 스냅샷 전체는 실패하지 않는다 (무문서 API 대응)") {
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

await test("잔여 비율은 1 − 사용 비율이고, 잔여 크레딧은 제공 크레딧과의 곱이다") {
    let snapshot = try UsageSnapshot.decode(from: Data(observedUsageJSON.utf8))

    // 사용 비율 0.002 → 잔여 비율 0.998 (독립 계산: 1 − 0.002)
    try checkNear(snapshot.remainingRatio, 0.998, "잔여 비율")
    try checkNear(snapshot.remainingCredits(pool: 60), 59.88, "잔여 크레딧 ($60 풀 기준)")
}

await test("사용 비율이 범위를 벗어나면 잔여 비율은 0..1로 고정된다") {
    // extra usage 로 풀을 넘어 쓴 경우 (소진 이상)
    let over = try UsageSnapshot.decode(from: Data(#"{"limits":{"monthly":{"usage":1.2,"models":[]}}}"#.utf8))
    try check(over.remainingRatio, 0.0, "풀 초과 사용 → 잔여 0")
    let garbage = try UsageSnapshot.decode(from: Data(#"{"limits":{"monthly":{"usage":-0.5,"models":[]}}}"#.utf8))
    try check(garbage.remainingRatio, 1.0, "비정상 음수 비율 → 잔여 1")
}

// MARK: - 갱신 예정일 (구독 시작일 기준 청구 주기)

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
    utcCalendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12))!
}

await test("갱신 예정일은 구독 시작일과 같은 날이고, 그 달에 없으면 그 달 마지막 날이다") {
    // 5월 1일 결제 → 5월이 31일까지 있어도 다음 회차는 6월 1일
    try check(BillingCycle.nextResetDate(anchorDay: 1, today: day(2026, 5, 1), calendar: utcCalendar), "2026-06-01", "결제일 당일 → 다음 달")
    try check(BillingCycle.nextResetDate(anchorDay: 1, today: day(2026, 5, 15), calendar: utcCalendar), "2026-06-01", "월 중순 → 다음 달 같은 날")

    // 8월 31일 결제 → 9월은 30일까지이므로 9월 30일
    try check(BillingCycle.nextResetDate(anchorDay: 31, today: day(2026, 8, 31), calendar: utcCalendar), "2026-09-30", "31일 구독 + 30일까지인 다음 달")
    // 기준일(31일)은 유지된다: 9월 30일 → 10월 31일
    try check(BillingCycle.nextResetDate(anchorDay: 31, today: day(2026, 9, 30), calendar: utcCalendar), "2026-10-31", "보정 후에도 기준일 유지")

    // 이번 달 기준일이 아직 안 왔으면 이번 달, 지났으면 다음 달
    try check(BillingCycle.nextResetDate(anchorDay: 15, today: day(2026, 9, 10), calendar: utcCalendar), "2026-09-15", "이번 달 기준일")
    try check(BillingCycle.nextResetDate(anchorDay: 15, today: day(2026, 9, 16), calendar: utcCalendar), "2026-10-15", "지난 기준일 → 다음 달")

    // 2월 보정(평년/윤년)과 연 경계
    try check(BillingCycle.nextResetDate(anchorDay: 31, today: day(2026, 1, 31), calendar: utcCalendar), "2026-02-28", "평년 2월 말일")
    try check(BillingCycle.nextResetDate(anchorDay: 31, today: day(2028, 1, 31), calendar: utcCalendar), "2028-02-29", "윤년 2월 말일")
    try check(BillingCycle.nextResetDate(anchorDay: 15, today: day(2026, 12, 20), calendar: utcCalendar), "2027-01-15", "연 경계")

    // 범위 밖 기준일은 계산하지 않는다
    try check(BillingCycle.nextResetDate(anchorDay: 0, today: day(2026, 9, 1), calendar: utcCalendar), Optional<String>.none, "0일 → nil")
    try check(BillingCycle.nextResetDate(anchorDay: 32, today: day(2026, 9, 1), calendar: utcCalendar), Optional<String>.none, "32일 → nil")
}

await test("설정 파일의 갱신 기준일(구독 시작일)을 읽는다") {
    let bare = uniqueConfigURL()
    try #"{"billing_day_of_month": 25}"#.write(to: bare, atomically: true, encoding: .utf8)
    try check(AppConfig.loadOrCreate(at: bare).billingDayOfMonth, 25, "bare 기준일")

    let wrapped = uniqueConfigURL()
    try #"{"billing_day_of_month": {"description": "구독 시작일", "value": 31}}"#.write(to: wrapped, atomically: true, encoding: .utf8)
    try check(AppConfig.loadOrCreate(at: wrapped).billingDayOfMonth, 31, "래퍼 기준일")

    let missing = uniqueConfigURL()
    try #"{"monthly_pool_usd": 60}"#.write(to: missing, atomically: true, encoding: .utf8)
    try check(AppConfig.loadOrCreate(at: missing).billingDayOfMonth, 1, "누락 → 기본 1일")

    let outOfRange = uniqueConfigURL()
    try #"{"billing_day_of_month": 45}"#.write(to: outOfRange, atomically: true, encoding: .utf8)
    try check(AppConfig.loadOrCreate(at: outOfRange).billingDayOfMonth, 31, "범위 밖 → 31로 고정")
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

await test("설정 파일이 없으면 기본값으로 만들어 돌려준다") {
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

await test("사용자가 고친 값과 색상 단계가 그대로 읽힌다") {
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

await test("폴링 간격은 10..300으로 고정된다") {
    let wide = uniqueConfigURL()
    try #"{"polling_interval_seconds": {"value": 9999}}"#.write(to: wide, atomically: true, encoding: .utf8)
    try check(AppConfig.loadOrCreate(at: wide).pollingIntervalSeconds, 300.0, "너무 큰 폴링 → 300")

    let narrow = uniqueConfigURL()
    try #"{"polling_interval_seconds": {"value": 3}}"#.write(to: narrow, atomically: true, encoding: .utf8)
    try check(AppConfig.loadOrCreate(at: narrow).pollingIntervalSeconds, 10.0, "너무 짧은 폴링 → 10")
}

await test("잘못된 색상 단계는 기본 팔레트로 돌아간다") {
    let url = uniqueConfigURL()
    try #"{"color_stages": {"value": [{"remaining_at_least": 0.4, "hex": "zzz"}]}}"#.write(to: url, atomically: true, encoding: .utf8)
    let config = AppConfig.loadOrCreate(at: url)
    try check(config.colorStages, AppConfig.defaultColorStages, "hex가 깨진 단계 → 기본 팔레트")
}

await test("전체가 깨진 JSON이면 기본값을 돌려주되 사용자 파일은 그대로 둔다") {
    let url = uniqueConfigURL()
    try "{broken".write(to: url, atomically: true, encoding: .utf8)
    let config = AppConfig.loadOrCreate(at: url)
    try check(config, AppConfig(), "깨진 JSON → 기본값")
    let stillBroken = try String(contentsOf: url, encoding: .utf8)
    try check(stillBroken == "{broken", true, "파일을 건드리지 않음")
}

// MARK: - API 클라이언트 seam (시스템 경계 — perform 클로저로 URLSession을 대역한다)

private final class Recording: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        _requests.append(request)
    }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }
}

@MainActor private func makeClient(
    apiKey: String,
    statusCode: Int,
    body: Data,
    recording: Recording
) -> UsageClient {
    UsageClient(
        apiKeyProvider: { apiKey },
        perform: { request in
            recording.record(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (body, response)
        }
    )
}

await test("사용량 조회는 Bearer 키로 /api/usage를 호출해 스냅샷을 돌려준다") {
    let recording = Recording()
    let client = makeClient(apiKey: "k-test", statusCode: 200, body: Data(observedUsageJSON.utf8), recording: recording)
    let outcome = await client.fetchUsage()

    guard case let .snapshot(snapshot, _) = await client.fetchUsage() else {
        throw CheckError(message: "정상 응답 → .snapshot 이어야 함: \(outcome)")
    }
    try check(snapshot.usageRatio, 0.002, "실측 응답의 사용 비율")
    try check(recording.requests.first?.url?.absoluteString, "https://ollama.com/api/usage", "엔드포인트")
    try check(recording.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer k-test", "Bearer 인증 헤더")
}

await test("상태 코드와 키 상태를 구분해 보고한다") {
    let recording = Recording()

    // 401 — 키 문제
    let unauthorized = makeClient(apiKey: "wrong", statusCode: 401, body: Data("{}".utf8), recording: recording)
    try check(await unauthorized.fetchUsage(), UsageClient.Outcome.invalidKey, "401 → 키 문제")

    // 402 — 소진 (정상 상태, 오류 아님)
    let exhausted = makeClient(apiKey: "k", statusCode: 402, body: Data(#"{"error":"balance empty"}"#.utf8), recording: recording)
    try check(await exhausted.fetchUsage(), UsageClient.Outcome.exhausted, "402 → 소진")

    // 429 — 백오프 대상
    let limited = makeClient(apiKey: "k", statusCode: 429, body: Data(), recording: recording)
    try check(await limited.fetchUsage(), UsageClient.Outcome.rateLimited, "429 → 백오프")

    // 키가 비어 있으면 네트워크를 치지 않는다
    let before = recording.requests.count
    let empty = makeClient(apiKey: "", statusCode: 200, body: Data(observedUsageJSON.utf8), recording: recording)
    try check(await empty.fetchUsage(), UsageClient.Outcome.invalidKey, "빈 키 → 키 문제")
    try check(recording.requests.count, before, "빈 키면 새 요청 없음")
}

await test("설정 파일은 래퍼 없는 bare 값도 읽는다") {
    let url = uniqueConfigURL()
    try #"{"monthly_pool_usd": 300, "polling_interval_seconds": 120}"#.write(to: url, atomically: true, encoding: .utf8)
    let config = AppConfig.loadOrCreate(at: url)
    try check(config.monthlyPoolUSD, 300.0, "bare 풀 값")
    try check(config.pollingIntervalSeconds, 120.0, "bare 폴링 값")
}

await test("사용량 조회 결과는 원문 JSON을 함께 돌려준다 (무문서 API 관측 창구)") {
    let recording = Recording()
    let client = makeClient(apiKey: "k", statusCode: 200, body: Data(observedUsageJSON.utf8), recording: recording)
    guard case let .snapshot(snapshot, rawJSON) = await client.fetchUsage() else {
        throw CheckError(message: "정상 응답 → .snapshot 이어야 함")
    }
    try check(String(decoding: rawJSON, as: UTF8.self), observedUsageJSON, "원문 JSON 그대로 전달")
    try check(snapshot.usageRatio, 0.002, "스냅샷도 정상 파싱")
}

if failedCount > 0 {
    print("\n실패 \(failedCount)건")
    exit(1)
}
print("\n모든 테스트 통과")