import Foundation

/// Typed Swift face of the Rust engine's C ABI (goviet.h).
enum EngineBridge {
    struct Result {
        enum Kind {
            case passThrough
            /// Delete `backspaces` characters, insert `text`; if `forward`
            /// the original key event is re-posted after the text.
            case replace(backspaces: Int, text: [UInt16], forward: Bool)
        }
        let kind: Kind
    }

    static func initialize() {
        vk_init()
    }

    static func setConfigJSON(_ json: String) {
        json.withCString { vk_set_config_json($0) }
    }

    static func setMacrosJSON(_ json: String) {
        json.withCString { vk_set_macros_json($0) }
    }

    static func processKey(keycode: UInt16, char: UInt32, commandLike: Bool) -> Result {
        var r = vk_process_key(keycode, char, commandLike ? 1 : 0)
        switch r.action {
        case UInt8(VK_ACTION_REPLACE):
            let text = withUnsafeBytes(of: &r.text) { buf -> [UInt16] in
                let p = buf.bindMemory(to: UInt16.self)
                return Array(p.prefix(Int(r.text_len)))
            }
            return Result(kind: .replace(backspaces: Int(r.backspaces), text: text, forward: r.forward != 0))
        case UInt8(VK_ACTION_REPLACE_LARGE):
            var buf = [UInt16](repeating: 0, count: Int(r.text_len))
            let copied = buf.withUnsafeMutableBufferPointer { p in
                vk_copy_pending_text(p.baseAddress, p.count)
            }
            return Result(kind: .replace(backspaces: Int(r.backspaces), text: Array(buf.prefix(copied)), forward: r.forward != 0))
        default:
            return Result(kind: .passThrough)
        }
    }

    static func resetWord() {
        vk_reset_word()
    }

    static func clearAll() {
        vk_clear_all()
    }
}
