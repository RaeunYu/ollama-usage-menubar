// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ollama-usage-menubar",
    platforms: [
        // 빌드 SDK가 15.1(CL트릭)이므로 플랫폼 선언은 15 — 실행 대상은 사용자 머신(macOS 26.3).
        // 26 전용 API는 쓰지 않는다. 툴체인이 올라가면 함께 올린다.
        .macOS(.v15)
    ],
    targets: [
        // 로직 전부: 스키마 디코딩, 잔여 계산, 설정 파일, API 클라이언트. 테스트 대상.
        .target(name: "OllamaUsageKit"),
        // 얇은 앱 껍데기: MenuBarExtra UI + 키체인. 로직은 Kit에 둔다.
        .executableTarget(
            name: "OllamaUsage",
            dependencies: ["OllamaUsageKit"]
        ),
    ]
)