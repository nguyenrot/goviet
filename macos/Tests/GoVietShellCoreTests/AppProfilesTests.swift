import XCTest
@testable import GoVietShellCore

final class AppProfilesTests: XCTestCase {
    func testHighRiskControlsUseCompatibilityStrategies() {
        XCTAssertEqual(
            AppProfiles.strategy(for: "com.apple.Terminal", overrides: [:]),
            .slow
        )
        XCTAssertEqual(
            AppProfiles.strategy(for: "com.google.Chrome", overrides: [:]),
            .selectAndRetype
        )
        XCTAssertEqual(
            AppProfiles.strategy(for: "com.apple.TextEdit", overrides: [:]),
            .fast
        )
    }

    func testUserOverrideWinsOverBuiltInProfile() {
        XCTAssertEqual(
            AppProfiles.strategy(
                for: "com.google.Chrome",
                overrides: ["com.google.Chrome": .passthrough]
            ),
            .passthrough
        )
    }
}
