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

@MainActor private func checkNear(_ actual: Double?, _ expected: Double, _ label: String) throws {
    guard let actual else { throw CheckError(message: "\(label): nil (기대 \(expected))") }
    guard abs(actual - expected) < 1e-9 else {
        throw CheckError(message: "\(label): 기대 \(expected), 실제 \(actual)")
    }
}

private let utcGregorian: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func utcParts(_ date: Date?) -> DateComponents? {
    guard let date else { return nil }
    return utcGregorian.dateComponents([.year, .month, .day, .hour, .minute], from: date)
}

// MARK: - Balance 스키마 (seam 1) — GET /api/balance, 공식 문서 docs.ollama.com/api/balance.md

/// 사용자가 2026-10-10에 자기 계정에서 취득한 실측 응답 원문.
/// 독립된 관측 리터럴 — 기대값은 코드가 아니라 이 관측에서 온다.
private let observedBalanceJSON = """
{
    "included": {
        "balance_usd": 58.84709,
        "allowance_usd": 60,
        "period": {
            "from": "2026-10-01T05:45:52Z",
            "until": "2026-11-01T05:45:52Z"
        }
    },
    "purchased": {
        "balance_usd": 0
    }
}
"""

await test("실측 /api/balance 응답이 BalanceSnapshot으로 디코드된다") {
    let snapshot = try BalanceSnapshot.decode(from: Data(observedBalanceJSON.utf8))

    try checkNear(snapshot.remainingUSD, 58.84709, "잔여 크레딧 (included.balance_usd)")
    try checkNear(snapshot.allowanceUSD, 60, "제공 크레딧 (allowance_usd)")
    try checkNear(snapshot.purchasedUSD, 0, "추가 결제 잔액 (purchased.balance_usd)")
}

await test("플랜 시작일과 초기화 시각을 읽는다") {
    let snapshot = try BalanceSnapshot.decode(from: Data(observedBalanceJSON.utf8))

    try check(
        utcParts(snapshot.planStart),
        DateComponents(year: 2026, month: 10, day: 1, hour: 5, minute: 45),
        "플랜 시작일 (period.from)"
    )
    try check(
        utcParts(snapshot.planReset),
        DateComponents(year: 2026, month: 11, day: 1, hour: 5, minute: 45),
        "플랜 초기화 (period.until)"
    )
}

await test("깨진·빠진 필드가 있어도 스냅샷 전체는 실패하지 않는다") {
    // 빈 응답 — 모든 값이 없음
    let empty = try BalanceSnapshot.decode(from: Data("{}".utf8))
    try check(empty.remainingUSD, Optional<Double>.none, "잔여 없음")
    try check(empty.allowanceUSD, Optional<Double>.none, "제공량 없음")
    try check(empty.planReset, Optional<Date>.none, "초기화 시각 없음")

    // 제공량만 있고 잔여가 없어도 읽힌다
    let partial = try BalanceSnapshot.decode(from: Data(#"{"included":{"allowance_usd":60}}"#.utf8))
    try checkNear(partial.allowanceUSD, 60, "부분 응답의 제공량")
    try check(partial.remainingUSD, Optional<Double>.none, "잔여는 여전히 nil")

    // 시각이 깨져 있으면 그 필드만 nil
    let brokenPeriod = #"{"included":{"balance_usd":1,"period":{"until":"어제"}}}"#
    let broken = try BalanceSnapshot.decode(from: Data(brokenPeriod.utf8))
    try check(broken.planReset, Optional<Date>.none, "깨진 시각 → nil")
    try checkNear(broken.remainingUSD, 1, "시각이 깨져도 잔여는 유지")

    // 잔여 크레딧이 문자열로 바뀌어도 전체는 살아남는다 (무문서 → 문서화됐어도 스키마는 변한다)
    let stringBalance = #"{"included":{"balance_usd":"58.8","allowance_usd":60},"new_field":42}"#
    let tolerant = try BalanceSnapshot.decode(from: Data(stringBalance.utf8))
    try check(tolerant.remainingUSD, Optional<Double>.none, "타입 변화 → nil")
    try checkNear(tolerant.allowanceUSD, 60, "다른 필드는 유지")

    // JSON 자체가 아니면 실패한다
    do {
        _ = try BalanceSnapshot.decode(from: Data("not json".utf8))
        throw CheckError(message: "JSON이 아닌 입력은 throw해야 함")
    } catch is CheckError {
        throw CheckError(message: "JSON이 아닌 입력은 throw해야 함")
    } catch {
        // 기대한 실패
    }
}

await test("잔여 비율은 잔여 크레딧 ÷ 제공 크레딧이다") {
    let snapshot = try BalanceSnapshot.decode(from: Data(observedBalanceJSON.utf8))
    // 독립 계산: 58.84709 / 60 = 0.9807848333…
    try checkNear(snapshot.remainingRatio, 0.9807848333333333, "잔여 비율")

    // 제공량이 0이거나 없으면 비율을 만들 수 없다
    let noAllowance = try BalanceSnapshot.decode(from: Data(#"{"included":{"balance_usd":10,"allowance_usd":0}}"#.utf8))
    try check(noAllowance.remainingRatio, Optional<Double>.none, "제공량 0 → nil")

    // 제공량을 넘겨 쓴 경우에도 비율은 0...1로 고정
    let over = try BalanceSnapshot.decode(from: Data(#"{"included":{"balance_usd":70,"allowance_usd":60}}"#.utf8))
    try checkNear(over.remainingRatio, 1.0, "제공량 초과 → 1로 고정")
}

await test("레거시 플랜 응답(session/weekly)은 값 없이 우아하게 물러난다") {
    // 공식 스펙의 included 는 oneOf — 레거시 플랜은 balance_usd/allowance_usd/period 가 없다.
    let legacy = """
    {
        "included": {
            "session": {"remaining_percent": 42, "resets_at": "2026-10-10T12:00:00Z"},
            "weekly": {"remaining_percent": 88, "resets_at": "2026-10-13T00:00:00Z"}
        },
        "purchased": {"balance_usd": 0}
    }
    """
    let snapshot = try BalanceSnapshot.decode(from: Data(legacy.utf8))
    try check(snapshot.remainingUSD, Optional<Double>.none, "레거시 → 잔여 없음")
    try check(snapshot.allowanceUSD, Optional<Double>.none, "레거시 → 제공량 없음")
    try check(snapshot.remainingRatio, Optional<Double>.none, "레거시 → 비율 없음(앱은 — 표시)")
    try checkNear(snapshot.purchasedUSD, 0, "구매 잔액은 읽는다")
}

// MARK: - 설정 파일 (seam 4)

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
    try check(config.pollingIntervalSeconds, 60.0, "기본 폴링 간격")

    // 생성된 파일은 스스로를 설명한다 (한국어 description)
    let written = try String(contentsOf: url, encoding: .utf8)
    try check(written.contains("description"), true, "description 키 존재")
    try check(written.contains("폴링"), true, "한국어 설명 존재")

    // 다시 읽어도 같은 값
    try check(AppConfig.loadOrCreate(at: url), config, "재로드 일관성")
}

await test("사용자가 고친 폴링 간격과 색상 단계가 그대로 읽힌다") {
    let url = uniqueConfigURL()
    let custom = """
    {
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

await test("설정 파일은 래퍼 없는 bare 값도 읽는다") {
    let url = uniqueConfigURL()
    try #"{"polling_interval_seconds": 120}"#.write(to: url, atomically: true, encoding: .utf8)
    try check(AppConfig.loadOrCreate(at: url).pollingIntervalSeconds, 120.0, "bare 폴링 값")
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
) -> BalanceClient {
    BalanceClient(
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

await test("잔액 조회는 Bearer 키로 /api/balance를 호출해 스냅샷과 원문을 돌려준다") {
    let recording = Recording()
    let client = makeClient(apiKey: "k-test", statusCode: 200, body: Data(observedBalanceJSON.utf8), recording: recording)
    let outcome = await client.fetchBalance()

    guard case let .balance(snapshot, rawJSON) = outcome else {
        throw CheckError(message: "정상 응답 → .balance 이어야 함: \(outcome)")
    }
    try checkNear(snapshot.remainingUSD, 58.84709, "실측 응답의 잔여 크레딧")
    try check(recording.requests.first?.url?.absoluteString, "https://ollama.com/api/balance", "엔드포인트 (쿼리 없음)")
    try check(recording.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer k-test", "Bearer 인증 헤더")
    try check(String(decoding: rawJSON, as: UTF8.self), observedBalanceJSON, "원문 JSON 그대로 전달")
}

await test("상태 코드와 키 상태를 구분해 보고한다") {
    let recording = Recording()

    let unauthorized = makeClient(apiKey: "wrong", statusCode: 401, body: Data("{}".utf8), recording: recording)
    try check(await unauthorized.fetchBalance(), BalanceClient.Outcome.invalidKey, "401 → 키 문제")

    let exhausted = makeClient(apiKey: "k", statusCode: 402, body: Data(#"{"error":"balance empty"}"#.utf8), recording: recording)
    try check(await exhausted.fetchBalance(), BalanceClient.Outcome.exhausted, "402 → 소진")

    let limited = makeClient(apiKey: "k", statusCode: 429, body: Data(), recording: recording)
    try check(await limited.fetchBalance(), BalanceClient.Outcome.rateLimited, "429 → 백오프")

    // 키가 비어 있으면 네트워크를 치지 않는다
    let before = recording.requests.count
    let empty = makeClient(apiKey: "", statusCode: 200, body: Data(observedBalanceJSON.utf8), recording: recording)
    try check(await empty.fetchBalance(), BalanceClient.Outcome.invalidKey, "빈 키 → 키 문제")
    try check(recording.requests.count, before, "빈 키면 새 요청 없음")
}

await test("문서화된 오류 상태를 사용자가 이해할 메시지로 옮긴다") {
    let recording = Recording()

    // 공식 문서: 403 — "Account suspended"
    let suspended = makeClient(apiKey: "k", statusCode: 403, body: Data(#"{"error":"Account suspended"}"#.utf8), recording: recording)
    try check(await suspended.fetchBalance(), BalanceClient.Outcome.failed(reason: "계정이 정지되었습니다"), "403 → 계정 정지")

    // 공식 문서: 503 — "Balance reporting is temporarily unavailable."
    let unavailable = makeClient(apiKey: "k", statusCode: 503, body: Data(#"{"error":"Balance reporting is temporarily unavailable."}"#.utf8), recording: recording)
    try check(await unavailable.fetchBalance(), BalanceClient.Outcome.failed(reason: "잔액 조회가 일시적으로 불가합니다"), "503 → 일시 불가")
}

if failedCount > 0 {
    print("\n실패 \(failedCount)건")
    exit(1)
}
print("\n모든 테스트 통과")
