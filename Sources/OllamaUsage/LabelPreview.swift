import AppKit
import SwiftUI
import OllamaUsageKit

/// `OllamaUsage --label-preview` — 메뉴바 라벨을 다크/라이트 배경 위에 렌더링해
/// /tmp/label-preview.png 로 저장한다. 화면 캡처 권한 없이 UI를 검증하는 개발 도구.
/// 색상 단계 검증을 위해 잔여 82%(녹)/35%(노랑)/10%(빨강) 세 구간을 함께 렌더링한다.
enum LabelPreview {
    @MainActor
    static func renderAndExitIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--label-preview") else { return false }

        let config = AppConfig()

        func label(remaining: Double) -> some View {
            StatusLabelView(
                phase: .snapshot(UsageSnapshot(
                    usageRatio: 1 - remaining,
                    activityCost: "10.80",
                    periodType: "last_4_weeks",
                    periodStartRaw: "2026-08-10T00:00:00Z",
                    periodEndRaw: "2026-09-01T00:00:00Z",
                    models: []
                )),
                config: config
            )
        }

        let view = VStack(spacing: 8) {
            label(remaining: 0.82)
            label(remaining: 0.35)
            label(remaining: 0.10)
        }
        .padding(8)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12)) // 다크 메뉴바
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3

        if let nsImage = renderer.nsImage,
           let tiff = nsImage.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "/tmp/label-preview.png"))
            print("label preview written: /tmp/label-preview.png")
        } else {
            print("render failed")
            exit(1)
        }
        return true
    }
}