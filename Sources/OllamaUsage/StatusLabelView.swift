import SwiftUI
import OllamaUsageKit

/// 메뉴바 라벨 — 잔여 %(텍스트) + progress bar(그래픽). 확정 스펙: 둘을 함께 표시.
struct StatusLabelView: View {
    let phase: UsagePoller.Phase
    let config: AppConfig

    var body: some View {
        HStack(spacing: 5) {
            Text(percentText)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .monospacedDigit()
            UsageBar(ratio: ratio, color: color)
        }
        .fixedSize()
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

/// 제공 크레딧 대비 잔여를 채운 가로 막대 — 메뉴바 소재 위에서도 확실히 보이게
/// 트랙은 명시적 대비 색을 쓰고(이전의 .quaternary는 사실상 보이지 않았다), 크기를 고정한다.
struct UsageBar: View {
    let ratio: Double?
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.22))
            if let ratio {
                Capsule()
                    .fill(color)
                    .frame(width: max(4, 58 * ratio))
            }
        }
        .frame(width: 58, height: 10)
    }
}

extension AppConfig.RGB {
    var swiftColor: Color {
        Color(red: red, green: green, blue: blue)
    }
}