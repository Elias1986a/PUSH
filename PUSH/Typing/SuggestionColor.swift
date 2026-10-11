import AppKit

/// The color suggestions are drawn in. Blue by default (the user's call,
/// 2026-10-10): it cannot pass for text already typed. Gray is the classic
/// ghost-text look. Saved as a preset name or, for a custom color, "#RRGGBB".
enum SuggestionColor: Equatable, Hashable {
    case preset(Preset)
    case custom(hex: String)

    enum Preset: String, CaseIterable, Identifiable {
        case blue, gray, purple, green, orange, pink, teal

        var id: String { rawValue }
        var name: String { rawValue.capitalized }

        /// System colors, so each adapts to light and dark mode.
        var color: NSColor {
            switch self {
            case .blue: return .systemBlue
            case .gray: return .secondaryLabelColor
            case .purple: return .systemPurple
            case .green: return .systemGreen
            case .orange: return .systemOrange
            case .pink: return .systemPink
            case .teal: return .systemTeal
            }
        }
    }

    static let `default` = SuggestionColor.preset(.blue)

    init(saved: String?) {
        if let saved, let preset = Preset(rawValue: saved) {
            self = .preset(preset)
        } else if let saved, Self.components(ofHex: saved) != nil {
            self = .custom(hex: saved.uppercased())
        } else {
            self = .default
        }
    }

    var saved: String {
        switch self {
        case .preset(let preset): return preset.rawValue
        case .custom(let hex): return hex
        }
    }

    var color: NSColor {
        switch self {
        case .preset(let preset): return preset.color
        case .custom(let hex):
            guard let (r, g, b) = Self.components(ofHex: hex) else { return Preset.blue.color }
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }
    }

    init(custom color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .systemBlue
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        self = .custom(hex: String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent),
                                   byte(c.blueComponent)))
    }

    /// "#RRGGBB" → 0…1 components; nil for anything else.
    static func components(ofHex hex: String) -> (CGFloat, CGFloat, CGFloat)? {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return (CGFloat(value >> 16 & 0xFF) / 255, CGFloat(value >> 8 & 0xFF) / 255, CGFloat(value & 0xFF) / 255)
    }
}
