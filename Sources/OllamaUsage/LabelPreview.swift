import AppKit
import SwiftUI
import OllamaUsageKit

/// `OllamaUsage --label-preview` — 메뉴바 라벨을 다크/라이트 배경 위에 렌더링해
/// /tmp/label-preview.png 로 저장한다. 화면 캡처 권한 없이 UI를 검증하는 개발 도구.
enum LabelPreview {
    @MainActor
    static func renderAndExitIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--label-preview") else { return false }

        // 82% 남은 상태를 가정한 라벨
        let snapshot = UsageSnapshot(
            usageRatio: 0.18,
            activityCost: "10.80",
            periodType: "last_4_weeks",
            periodStartRaw: "2026-08-10T00:00:00Z",
            periodEndRaw: "2026-09-01T00:00:00Z",
            models: []
        )

        let view = VStack(spacing: 8) {
            StatusLabelView(phase: .snapshot(snapshot), config: AppConfig())
                .padding(6)
                .background(Color(red: 0.11, green: 0.11, blue: 0.12)) // 다크 메뉴바
            StatusLabelView(phase: .snapshot(snapshot), config: AppConfig())
                .padding(6)
                .background(Color(red: 0.96, green: 0.96, blue: 0.96)) // 라이트 메뉴바
        }
        .padding(6)

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