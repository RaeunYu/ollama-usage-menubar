import Foundation

/// `GET https://ollama.com/api/balance` 호출기 — 공식 문서: https://docs.ollama.com/api/balance.md
///
/// 상태 매핑: 200 → 잔액 스냅샷(+원문), 401 → 키 문제, 402 → 소진, 429 → 백오프 대상,
/// 그 외(네트워크 오류·깨진 응답·기타 상태) → 실패. 전송 계층은 주입받는다(테스트 대역).
public struct BalanceClient: Sendable {

    public enum Outcome: Equatable, Sendable {
        /// rawJSON — 공식 문서가 있어도 스키마는 변한다. 원문을 보관해 관측 창구로 남긴다.
        case balance(BalanceSnapshot, rawJSON: Data)
        /// 402 — 크레딧 소진. 오류가 아니라 보고할 정상 상태다.
        case exhausted
        case invalidKey
        case rateLimited
        case failed(reason: String)
    }

    public static let endpoint = URL(string: "https://ollama.com/api/balance")!

    private let perform: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let apiKeyProvider: @Sendable () -> String?

    /// - Parameters:
    ///   - apiKeyProvider: 매 호출마다 키를 제공한다(키체인은 앱 계층이 주입). nil이면 미설정으로 본다.
    ///   - perform: 전송 경계 — 기본은 URLSession.
    public init(
        apiKeyProvider: @escaping @Sendable () -> String?,
        perform: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.perform = perform
    }

    public static func urlSessionTransport() -> @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse) {
        { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return (data, http)
        }
    }

    public func fetchBalance() async -> Outcome {
        guard let key = apiKeyProvider(), !key.isEmpty else { return .invalidKey }

        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await perform(request)
            switch response.statusCode {
            case 200...299:
                guard let snapshot = try? BalanceSnapshot.decode(from: data) else {
                    return .failed(reason: "응답을 읽을 수 없음")
                }
                return .balance(snapshot, rawJSON: data)
            case 401:
                return .invalidKey
            case 402:
                // 문서에 없는 상태지만, 온다면 의미는 소진이다.
                return .exhausted
            case 403:
                // 공식 문서: "Account suspended" (계정 정지)
                return .failed(reason: "계정이 정지되었습니다")
            case 429:
                return .rateLimited
            case 503:
                // 공식 문서: "Balance reporting is temporarily unavailable." (서버 측 일시 불가)
                return .failed(reason: "잔액 조회가 일시적으로 불가합니다")
            default:
                return .failed(reason: "HTTP \(response.statusCode)")
            }
        } catch {
            return .failed(reason: "\(error.localizedDescription)")
        }
    }
}
