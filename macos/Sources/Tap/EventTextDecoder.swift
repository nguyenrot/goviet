import Foundation

/// Converts the UTF-16 payload attached to a CGEvent into the single Unicode
/// scalar accepted by the Rust ABI.
enum EventTextDecoder {
    /// A non-control, non-alphanumeric scalar that makes the engine commit and
    /// clear its current word while the original multi-scalar event is replayed.
    private static let textBreak: UInt32 = 0xFFFC

    static func scalarForEngine(units: [UInt16], length: Int) -> UInt32 {
        guard length > 0 else { return 0 }
        guard length <= units.count else { return textBreak }

        let text = String(decoding: units.prefix(length), as: UTF16.self)
        guard text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first else {
            return textBreak
        }
        return scalar.value == 0 ? textBreak : scalar.value
    }
}
