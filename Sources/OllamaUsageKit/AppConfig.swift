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
    /// 구독을 시작한 날 — API가 알려 주지 않아 사용자가 설정한다.
    public static let defaultBillingDayOfMonth = 1
    public static let defaultColorStages: [ColorStage] = [
        ColorStage(minimumRemaining: 0.5, rgb: RGB(hex: "#34C759")!),
        ColorStage(minimumRemaining: 0.2, rgb: RGB(hex: "#FF9F0A")!),
        ColorStage(minimumRemaining: 0.0, rgb: RGB(hex: "#FF453A")!),
    ]

    /// 제공 크레딧 (Pool) — 항상 내림차순 정렬을 유지한다(stage 선택의 전제).
    public let monthlyPoolUSD: Double
    /// 폴링 간격(초) — 10...300으로 고정한다.
    public let pollingIntervalSeconds: Double
    /// 갱신 기준일(1...31) — 구독 시작일. 갱신 예정일 계산의 근거(BillingCycle).
    public let billingDayOfMonth: Int
    public let colorStages: [ColorStage]

    public init(
        monthlyPoolUSD: Double = AppConfig.defaultPoolUSD,
        pollingIntervalSeconds: Double = AppConfig.defaultPollingIntervalSeconds,
        billingDayOfMonth: Int = AppConfig.defaultBillingDayOfMonth,
        colorStages: [ColorStage] = AppConfig.defaultColorStages
    ) {
        self.monthlyPoolUSD = monthlyPoolUSD
        self.pollingIntervalSeconds = pollingIntervalSeconds
        self.billingDayOfMonth = min(max(billingDayOfMonth, 1), 31)
        self.colorStages = colorStages.sorted { $0.minimumRemaining > $1.minimumRemaining }
    }

    /// 잔여 비율에 맞는 색상 단계 — 목록 위에서부터 처음으로 minimumRemaining 이하인 단계.
    /// colorStages는 항상 내림차순 정렬을 유지한다(init에서 정렬).
    public func stage(forRemaining ratio: Double) -> ColorStage? {
        colorStages.first { ratio >= $0.minimumRemaining } ?? colorStages.last
    }

    /// 설정 파일 표준 위치
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OllamaUsage")
            .appendingPathComponent("config.json")
    }

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

    /// 깨진 속성은 기본값으로 대체해 읽는다 — 전체가 실패하지 않게(무문서 API와 같은 원칙).
    /// 값 표기는 래퍼(`{"description", "value"}`)와 bare 값 둘 다 받는다 — 사용자가 설명을
    /// 지우고 값만 남기는 가장 흔한 수정을 막지 않는다.
    public static func decode(from data: Data) -> AppConfig? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return AppConfig(
            monthlyPoolUSD: max(numberValue(root["monthly_pool_usd"]) ?? defaultPoolUSD, 0),
            pollingIntervalSeconds: clampedPolling(numberValue(root["polling_interval_seconds"]) ?? defaultPollingIntervalSeconds),
            billingDayOfMonth: Int(numberValue(root["billing_day_of_month"]) ?? Double(defaultBillingDayOfMonth)),
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
            "billing_day_of_month": [
                "description": "갱신 기준일 — 구독을 시작한 날(1~31). 매월 이 날에 크레딧이 리셋된다. 그 달에 그 날이 없으면 그 달 마지막 날이 기준이고, 기준일 자체는 바뀌지 않는다(예: 31일 구독 → 9월 30일, 10월 31일).",
                "value": billingDayOfMonth,
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
        // 래퍼 형식: {"description": "...", "value": 숫자}
        if let description = property as? [String: Any],
           let value = description["value"] as? NSNumber {
            return value.doubleValue
        }
        // bare 형식: 사용자가 설명 키를 지우고 값만 남긴 경우 — 경고 없이 받아들인다.
        if let bare = property as? NSNumber {
            return bare.doubleValue
        }
        return nil
    }

    static func clampedPolling(_ raw: Double) -> Double {
        min(max(raw, 10), 300)
    }

    static func stages(from any: Any?) -> [ColorStage] {
        // 래퍼 형식과 bare 배열 둘 다 받는다. 정렬은 init이 책임진다.
        let raw = ((any as? [String: Any])?["value"] ?? any) as? [[String: Any]]
        let parsed = (raw ?? []).compactMap { entry -> ColorStage? in
            guard let minimum = entry["remaining_at_least"] as? Double,
                  let hex = entry["hex"] as? String,
                  let rgb = RGB(hex: hex) else { return nil }
            return ColorStage(minimumRemaining: min(max(minimum, 0), 1), rgb: rgb)
        }
        return parsed.isEmpty ? AppConfig.defaultColorStages : parsed
    }
}