import Foundation

enum TextInjectionElement: Equatable, Sendable {
    case text([UInt16])
    case returnKey
    case tabKey
}

/// Deterministic, side-effect-free planning for synthesized text events.
/// Keeping this separate from CGEvent posting makes Unicode boundaries and
/// pacing budgets regression-testable without Accessibility permission.
enum TextInjectionPlanner {
    static func elements(
        for units: [UInt16],
        perCharacter: Bool,
        maxChunkSize: Int
    ) -> [TextInjectionElement] {
        guard !units.isEmpty else { return [] }
        precondition(maxChunkSize > 0)

        let text = String(decoding: units, as: UTF16.self)
        var elements: [TextInjectionElement] = []
        var chunk: [UInt16] = []

        func flush() {
            guard !chunk.isEmpty else { return }
            elements.append(.text(chunk))
            chunk.removeAll(keepingCapacity: true)
        }

        for character in text {
            if character == "\n" || character == "\r" || character == "\r\n" {
                flush()
                elements.append(.returnKey)
                continue
            }
            if character == "\t" {
                flush()
                elements.append(.tabKey)
                continue
            }

            let characterUnits = Array(String(character).utf16)
            if perCharacter {
                flush()
                elements.append(.text(characterUnits))
            } else {
                if !chunk.isEmpty, chunk.count + characterUnits.count > maxChunkSize {
                    flush()
                }
                chunk.append(contentsOf: characterUnits)
            }
        }
        flush()
        return elements
    }

    static func boundedDelay(
        configuredUS: UInt32,
        stepCount: Int,
        totalBudgetUS: UInt64
    ) -> UInt32 {
        guard configuredUS > 0, stepCount > 0 else { return 0 }
        let budgetPerStep = totalBudgetUS / UInt64(stepCount)
        return UInt32(min(UInt64(configuredUS), budgetPerStep))
    }
}
