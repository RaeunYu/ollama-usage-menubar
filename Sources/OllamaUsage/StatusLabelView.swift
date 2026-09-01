import SwiftUI
import OllamaUsageKit

/// 메뉴바 라벨 — 잔여 %(텍스트) + progress bar(그래픽). 확정 스펙: 둘을 함께 표시.
struct StatusLabelView: View {
    let phase: UsagePoller.Phase
    let config: AppConfig

    var body: some View {
        HStack(spacing: 4) {
            Text(percentText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            UsageBar(ratio: ratio, color: color)
        }
    }

    private var snapshot: UsageSnapshot? {
        if case .snapshot(let snapshot) = phase { return snapshot }
        return nil
    }

    private var percentText: String {
        if let ratio = snapshot?.remainingRatio {
            return "\(Int((ratio * 100).rounded()))%"
        }
        switch phase {
        case .loading, .rateLimited: return "…"
        case .exhausted: return "0%"
        case .invalidKey: return "키"
        case .failed: return "!"
        case .snapshot: return "—" // 스냅샷인데 비율이 없는(무문서 API 스키마 변화) 경우
        }
    }

    private var ratio: Double? { snapshot?.remainingRatio }

    private var color: Color {
        if let ratio = snapshot?.remainingRatio {
            return config.stage(forRemaining: ratio)?.rgb.swiftColor ?? .accentColor
        }
        switch phase {
        case .invalidKey: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }
}

/// 제공 크레딧 대비 잔여를 채운 가로 막대
struct UsageBar: View {
    let ratio: Double?
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.quaternary)
            if let ratio {
                Capsule().fill(color).frame(width: max(3, 44 * ratio))
            }
        }
        .frame(width: 44, height: 8)
    }
}

extension AppConfig.RGB {
    var swiftColor: Color {
        Color(red: red, green: green, blue: blue)
    }
}