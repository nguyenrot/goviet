import XCTest
@testable import GoVietShellCore

final class TextInjectionPlannerTests: XCTestCase {
    func testChunksNeverSplitEmojiOrCombiningGraphemes() {
        let text = "a😀e\u{301}b"
        let elements = TextInjectionPlanner.elements(
            for: Array(text.utf16),
            perCharacter: false,
            maxChunkSize: 2
        )

        XCTAssertEqual(
            elements,
            [
                .text(Array("a".utf16)),
                .text(Array("😀".utf16)),
                .text(Array("e\u{301}".utf16)),
                .text(Array("b".utf16)),
            ]
        )
    }

    func testControlCharactersBecomeRealKeySteps() {
        let elements = TextInjectionPlanner.elements(
            for: Array("a\r\nb\tc\rd\ne".utf16),
            perCharacter: false,
            maxChunkSize: 20
        )

        XCTAssertEqual(
            elements,
            [
                .text(Array("a".utf16)), .returnKey,
                .text(Array("b".utf16)), .tabKey,
                .text(Array("c".utf16)), .returnKey,
                .text(Array("d".utf16)), .returnKey,
                .text(Array("e".utf16)),
            ]
        )
    }

    func testPerCharacterModeUsesOneEventPerGrapheme() {
        let elements = TextInjectionPlanner.elements(
            for: Array("a😀ế".utf16),
            perCharacter: true,
            maxChunkSize: 20
        )
        XCTAssertEqual(elements.count, 3)
    }

    func testLongSlowInjectionIsBoundedByTotalBudget() {
        XCTAssertEqual(
            TextInjectionPlanner.boundedDelay(
                configuredUS: 8_000,
                stepCount: 1_000,
                totalBudgetUS: 2_000_000
            ),
            2_000
        )
        XCTAssertEqual(
            TextInjectionPlanner.boundedDelay(
                configuredUS: 8_000,
                stepCount: 10,
                totalBudgetUS: 2_000_000
            ),
            8_000
        )
    }
}
