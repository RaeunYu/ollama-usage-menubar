import Foundation

/// 설정 파일 (CONTEXT.md) — API가 알려 주지 않는 값(제공 크레딧, 폴링 간격, 색상 단계)을
/// 사용자가 직접 고친다. 모든 속성은 `{"description": 한국어 설명, "value": 값}` 형태로
/// 스스로를 설명한다. API 키는 여기에 절대 넣지 않는다(ADR-0003).
public struct AppConfig: Equatable, Sendable {

    public struct ColorStage: Equatable, Sendable {
        /// 이 색이 적용되는 최소 잔여 비율 (0...1). 위에서부터 처음 맞는 단계를 쓴다.
        public let minimumRemaining: Double
        public let rgb: RGB

        public init(minimumRemaining: Double, rgb: RGB) {
            self.minimumRemaining = minimumRemaining
            self.rgb = rgb
        }
    }

    public struct RGB: Equatable, Sendable {
        /// 0...1
        public let red: Double
        public let green: Double
        public let blue: Double

        public init?(hex: String) {
            var text = hex
            if text.hasPrefix("#") { text.removeFirst() }
            if text.hasPrefix("0x") || text.hasPrefix("0X") { text.removeFirst(2) }
            guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
        }

        /// "#RRGGBB" 형태의 hex 표기
        public var hex: String {
            String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
        }
    }

    public static let defaultPoolUSD: Double = 60
    public static let defaultPollingIntervalSeconds: Double = 60
    public static let defaultColorStages: [ColorStage] = [
        ColorStage(minimumRemaining: 0.5, rgb: RGB(hex: "#34C759")!),
        ColorStage(minimumRemaining: 0.2, rgb: RGB(hex: "#FF9F0A")!),
        ColorStage(minimumRemaining: 0.0, rgb: RGB(hex: "#FF453A")!),
    ]

    /// 제공 크레딧 (Pool)
    public let monthlyPoolUSD: Double
    /// 폴링 간격(초) — 10...300으로 고정한다.
    public let pollingIntervalSeconds: Double
    public let colorStages: [ColorStage]

    public init(
        monthlyPoolUSD: Double = AppConfig.defaultPoolUSD,
        pollingIntervalSeconds: Double = AppConfig.defaultPollingIntervalSeconds,
        colorStages: [ColorStage] = AppConfig.defaultColorStages
    ) {
        self.monthlyPoolUSD = monthlyPoolUSD
        self.pollingIntervalSeconds = pollingIntervalSeconds
        self.colorStages = colorStages
    }

    /// 잔여 비율에 맞는 색상 단계 — 목록 위에서부터 처음으로 minimumRemaining 이하인 단계.
    /// 맞는 단계가 없으면(모든 단계보다 낮은 잔여) 마지막 단계를 돌려준다.
    public func stage(forRemaining ratio: Double) -> ColorStage? {
        let sorted = colorStages.sorted { $0.minimumRemaining > $1.minimumRemaining }
        return sorted.first { ratio >= $0.minimumRemaining } ?? sorted.last
    }

    /// 설정 파일 표준 위치
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OllamaUsage")
            .appendingPathComponent("config.json")
    }

    /// 설정 파일이 없으면 기본값으로 만들고 기본값을 돌려준다. 있으면 읽어서 돌려준다.
    /// 설정 파일이 없으면 기본값으로 만들고 기본값을 돌려준다. 있으면 읽어서 돌려준다.
    /// 파일이 깨져 있으면 기본값을 돌려주되 파일은 절대 건드리지 않는다(사용자 파일 파괴 금지).
    public static func loadOrCreate(at url: URL) -> AppConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let defaults = AppConfig()
            if let document = defaults.documentData() {
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? document.write(to: url, options: .atomic)
            }
            return defaults
        }
        guard let data = try? Data(contentsOf: url) else { return AppConfig() }
        return decode(from: data) ?? AppConfig()
    }

    public func write(to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }

    /// 깨진 속성은 기본값으로 대체해 읽는다 — 전체가 실패하지 않게(무문서 API와 같은 원칙).
    public static func decode(from data: Data) -> AppConfig? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return AppConfig(
            monthlyPoolUSD: max(numberValue(root["monthly_pool_usd"]) ?? defaultPoolUSD, 0),
            pollingIntervalSeconds: clampedPolling(numberValue(root["polling_interval_seconds"]) ?? defaultPollingIntervalSeconds),
            colorStages: stages(from: root["color_stages"])
        )
    }

    // MARK: - 문서 직렬화 (한국어 description 병기)

    private func documentData() -> Data? {
        try? JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    private var document: [String: Any] {
        [
            "monthly_pool_usd": [
                "description": "제공 크레딧 — 플랜이 매월 부여하는 크레딧 총액(달러). 예: Pro 60, Max 300, Team 1000",
                "value": monthlyPoolUSD,
            ],
            "polling_interval_seconds": [
                "description": "사용량을 다시 조회하는 간격(초). 10~300 사이로 맞춰진다.",
                "value": pollingIntervalSeconds,
            ],
            "color_stages": [
                "description": "잔여 비율 구간별 메뉴바 색상. remaining_at_least 이상일 때 해당 hex 색을 쓰고, 목록 위에서부터 처음 맞는 것을 택한다.",
                "value": colorStages.map { stage in
                    [
                        "remaining_at_least": stage.minimumRemaining,
                        "hex": stage.rgb.hex,
                    ]
                },
            ],
        ]
    }
}

// MARK: - 관대한 디코딩 헬퍼

private extension AppConfig {
    static func numberValue(_ property: Any?) -> Double? {
        guard let description = property as? [String: Any],
              let value = description["value"] as? NSNumber
        else { return nil }
        return value.doubleValue
    }

    static func clampedPolling(_ raw: Double) -> Double {
        min(max(raw, 10), 300)
    }

    static func stages(from any: Any?) -> [ColorStage] {
        guard let stages = (any as? [String: Any])?["value"] as? [[String: Any]] else {
            return AppConfig.defaultColorStages
        }
        let parsed = stages.compactMap { entry -> ColorStage? in
            guard let minimum = entry["remaining_at_least"] as? Double,
                  let hex = entry["hex"] as? String,
                  let rgb = RGB(hex: hex) else { return nil }
            return ColorStage(minimumRemaining: min(max(minimum, 0), 1), rgb: rgb)
        }
        return parsed.isEmpty ? AppConfig.defaultColorStages : parsed.sorted { $0.minimumRemaining > $1.minimumRemaining }
    }
}