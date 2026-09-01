import AppKit
import SwiftUI
import OllamaUsageKit

/// MenuBarExtra 라벨의 환경 제약: 커스텀 뷰(Shape/Capsule)는 그려지지 않고 텍스트만 표시된다.
/// 그래서 라벨 전체를 오프스크린 렌더링(NSImage)해 `Image(nsImage:)`로 넣는다.
/// 렌더링 모드는 original — 메뉴바 템플릿 변환으로 색이 지워지지 않게 한다.
@MainActor
enum StatusLabelRenderer {
    static func image(phase: UsagePoller.Phase, config: AppConfig) -> NSImage {
        let view = StatusLabelView(phase: phase, config: config, labelColor: isDarkMenuBar ? .white : .black)
            .padding(.horizontal, 3)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2 // Retina 선명도
        if let rendered = renderer.nsImage {
            return rendered
        }
        return NSImage(systemSymbolName: "chart.pie", accessibilityDescription: "Ollama Usage")!
    }

    private static var isDarkMenuBar: Bool {
        let best = NSApp.effectiveAppearance.bestMatch(
            from: [NSAppearance.Name.aqua, .darkAqua, .vibrantLight, .vibrantDark]
        ) ?? NSAppearance.Name.aqua
        return best == .darkAqua || best == .vibrantDark
    }
}