import Foundation

/// `GET https://ollama.com/api/usage` 호출기 (무문서 API — ADR-0001).
///
/// 상태 매핑: 200 → 스냅샷, 401 → 키 문제, 402 → 소진(정상 상태), 429 → 백오프 대상,
/// 그 외(네트워크 오류·깨진 응답·기타 상태) → 실패. 전송 계층은 주입받는다(테스트 대역).
public struct UsageClient: Sendable {

    public enum Outcome: Equatable, Sendable {
        /// rawJSON — 무문서 API 관측을 지속하는 창구(ADR-0001). 표시에는 쓰지 않는다.
        case snapshot(UsageSnapshot, rawJSON: Data)
        /// 402 — 제공 크레딧 소진. 오류가 아니라 정상 상태다(CONTEXT.md: 소진).
        case exhausted
        case invalidKey
        case rateLimited
        case failed(reason: String)

        public static func == (lhs: UsageClient.Outcome, rhs: UsageClient.Outcome) -> Bool {
            switch (lhs, rhs) {
            case let (.snapshot(a), .snapshot(b)): return a == b
            case (.exhausted, .exhausted), (.invalidKey, .invalidKey), (.rateLimited, .rateLimited): return true
            case let (.failed(a), .failed(b)): return a == b
            default: return false
            }
        }
    }

    public static let endpoint = URL(string: "https://ollama.com/api/usage")!

    private let perform: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let apiKeyProvider: @Sendable () -> String?

    /// - Parameters:
    ///   - apiKeyProvider: 매 호출마다 키를 제공한다(키체인은 앱 계층이 주입).
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

    public func fetchUsage() async -> Outcome {
        guard let key = apiKeyProvider(), !key.isEmpty else { return .invalidKey }

        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await perform(request)
            switch response.statusCode {
            case 200...299:
                guard let snapshot = try? UsageSnapshot.decode(from: data) else {
                    return .failed(reason: "응답을 읽을 수 없음")
                }
                return .snapshot(snapshot, rawJSON: data)
            case 401:
                return .invalidKey
            case 402:
                // 소진은 오류가 아니라 보고할 정상 상태다(이슈 #17639 사례 — 리서치 문서).
                return .exhausted
            case 429:
                // 레이트 리밋 — 폴링 쪽에서 백오프한다.
                return .rateLimited
            default:
                return .failed(reason: "HTTP \(response.statusCode)")
            }
        } catch {
            return .failed(reason: "\(error.localizedDescription)")
        }
    }
}