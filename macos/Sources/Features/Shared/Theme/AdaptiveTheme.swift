import SwiftUI
import AppKit

/// Warp-inspired adaptive theme system that derives colors from terminal background
/// or system appearance. Uses alpha-based opacity layering for surface hierarchy.
///
/// Color derivation strategy:
/// 1. Determine if base is light or dark via luminance
/// 2. Layer surfaces using white overlay (dark mode) or black overlay (light mode)
/// 3. Keep accent color consistent across modes
struct AdaptiveTheme: Equatable {
    let colorScheme: ColorScheme
    let terminalBackground: NSColor?

    // MARK: - Initialization

    /// Create theme from system appearance (no terminal context)
    static var system: AdaptiveTheme {
        AdaptiveTheme(colorScheme: .dark, terminalBackground: nil)
    }

    /// Create theme from terminal background color
    init(colorScheme: ColorScheme, terminalBackground: NSColor? = nil) {
        self.colorScheme = colorScheme
        self.terminalBackground = terminalBackground
    }

    /// Convenience: detect color scheme from terminal background
    init(terminalBackground: NSColor) {
        let luminance = terminalBackground.luminance
        self.colorScheme = luminance > 0.5 ? .light : .dark
        self.terminalBackground = terminalBackground
    }

    // MARK: - Semantic Equality

    static func == (lhs: AdaptiveTheme, rhs: AdaptiveTheme) -> Bool {
        lhs.colorScheme == rhs.colorScheme &&
        lhs.terminalBackground?.hexString == rhs.terminalBackground?.hexString
    }

    // MARK: - Computed State

    private var isDark: Bool { colorScheme == .dark }

    /// Base color: terminal background or default
    private var base: NSColor {
        terminalBackground ?? (isDark ? Self.darkBase : Self.lightBase)
    }

    // MARK: - Default Palettes

    // Dark palette (Warp/GitHub dark inspired)
    private static let darkBase = NSColor(red: 0.051, green: 0.067, blue: 0.090, alpha: 1.0) // #0D1117

    // Light palette (Warp light inspired)
    private static let lightBase = NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0) // #FFFFFF

    // MARK: - Background Colors

    /// Primary sidebar background
    var background: NSColor {
        if let bg = terminalBackground {
            return bg
        }
        return isDark
            ? Self.darkBase
            : NSColor(red: 0.984, green: 0.988, blue: 0.992, alpha: 1.0) // #FBFCFD
    }

    /// Elevated surface (headers, toolbars, cards)
    var surfaceElevated: NSColor {
        isDark
            ? base.blendedOverlay(white: 0.05)
            : NSColor(red: 0.965, green: 0.973, blue: 0.980, alpha: 1.0) // #F6F8FA
    }

    /// Hover state surface
    var surfaceHover: NSColor {
        isDark
            ? base.blendedOverlay(white: 0.08)
            : NSColor(red: 0.918, green: 0.933, blue: 0.949, alpha: 1.0) // #EAEEF2
    }

    /// Selection background (subtle)
    var selection: NSColor {
        NSColor(red: 0.122, green: 0.435, blue: 0.922, alpha: isDark ? 0.2 : 0.12) // #1F6FEB
    }

    /// Active selection background (stronger)
    var selectionActive: NSColor {
        NSColor(red: 0.122, green: 0.435, blue: 0.922, alpha: isDark ? 0.35 : 0.2) // #1F6FEB
    }

    /// Focus ring for keyboard navigation
    var focusRing: NSColor {
        NSColor(red: 0.122, green: 0.435, blue: 0.922, alpha: 1.0) // #1F6FEB
    }

    // MARK: - Border Colors

    /// Primary border/divider
    var border: NSColor {
        isDark
            ? NSColor(red: 0.188, green: 0.212, blue: 0.239, alpha: 1.0) // #30363D
            : NSColor(red: 0.820, green: 0.835, blue: 0.855, alpha: 1.0) // #D1D5DA
    }

    /// Subtle border (lighter)
    var borderSubtle: NSColor {
        isDark
            ? NSColor(red: 0.129, green: 0.149, blue: 0.176, alpha: 1.0) // #21262D
            : NSColor(red: 0.910, green: 0.920, blue: 0.933, alpha: 1.0) // #E8EBED
    }

    /// Disabled border
    var borderDisabled: NSColor {
        borderSubtle.withAlphaComponent(0.5)
    }

    // MARK: - Text Colors

    /// Primary text (highest contrast)
    var textPrimary: NSColor {
        isDark
            ? NSColor(red: 0.902, green: 0.929, blue: 0.953, alpha: 1.0) // #E6EDF3
            : NSColor(red: 0.141, green: 0.161, blue: 0.180, alpha: 1.0) // #24292E
    }

    /// Secondary text
    var textSecondary: NSColor {
        isDark
            ? NSColor(red: 0.545, green: 0.580, blue: 0.620, alpha: 1.0) // #8B949E
            : NSColor(red: 0.345, green: 0.376, blue: 0.412, alpha: 1.0) // #586069
    }

    /// Muted text (lowest contrast)
    var textMuted: NSColor {
        isDark
            ? NSColor(red: 0.431, green: 0.463, blue: 0.506, alpha: 1.0) // #6E7681
            : NSColor(red: 0.416, green: 0.451, blue: 0.490, alpha: 1.0) // #6A737D
    }

    /// Disabled text
    var textDisabled: NSColor {
        textMuted.withAlphaComponent(0.5)
    }

    // MARK: - Accent Colors

    /// Primary accent (blue)
    var accent: NSColor {
        isDark
            ? NSColor(red: 0.345, green: 0.651, blue: 1.0, alpha: 1.0) // #58A6FF
            : NSColor(red: 0.122, green: 0.435, blue: 0.922, alpha: 1.0) // #1F6FEB
    }

    /// Folder icon color
    var folderIcon: NSColor {
        isDark
            ? NSColor(red: 0.329, green: 0.682, blue: 1.0, alpha: 1.0) // #54AEFF
            : NSColor(red: 0.200, green: 0.494, blue: 0.863, alpha: 1.0) // #337EDB
    }

    /// Markdown/file icon color
    var markdownIcon: NSColor {
        isDark
            ? NSColor(red: 0.969, green: 0.506, blue: 0.400, alpha: 1.0) // #F78166
            : NSColor(red: 0.820, green: 0.341, blue: 0.224, alpha: 1.0) // #D15739
    }

    /// Success color
    var success: NSColor {
        isDark
            ? NSColor(red: 0.247, green: 0.725, blue: 0.314, alpha: 1.0) // #3FB950
            : NSColor(red: 0.161, green: 0.624, blue: 0.224, alpha: 1.0) // #289F39
    }

    /// Danger color
    var danger: NSColor {
        isDark
            ? NSColor(red: 1.0, green: 0.420, blue: 0.420, alpha: 1.0) // #FF6B6B
            : NSColor(red: 0.871, green: 0.243, blue: 0.243, alpha: 1.0) // #DE3E3E
    }

    /// Warning color
    var warning: NSColor {
        isDark
            ? NSColor(red: 1.0, green: 0.651, blue: 0.341, alpha: 1.0) // #FFA657
            : NSColor(red: 0.863, green: 0.502, blue: 0.161, alpha: 1.0) // #DC8029
    }

    // MARK: - Icon Colors

    /// Default icon color
    var iconDefault: NSColor { textSecondary }

    /// Hovered icon color
    var iconHover: NSColor { textPrimary }

    /// Disabled icon color
    var iconDisabled: NSColor { textSecondary.withAlphaComponent(0.5) }

    // MARK: - SwiftUI Color Accessors

    var backgroundC: Color { Color(background) }
    var surfaceElevatedC: Color { Color(surfaceElevated) }
    var surfaceHoverC: Color { Color(surfaceHover) }
    var selectionC: Color { Color(selection) }
    var selectionActiveC: Color { Color(selectionActive) }
    var borderC: Color { Color(border) }
    var borderSubtleC: Color { Color(borderSubtle) }
    var textPrimaryC: Color { Color(textPrimary) }
    var textSecondaryC: Color { Color(textSecondary) }
    var textMutedC: Color { Color(textMuted) }
    var accentC: Color { Color(accent) }
    var folderIconC: Color { Color(folderIcon) }
    var markdownIconC: Color { Color(markdownIcon) }
    var focusRingC: Color { Color(focusRing) }
    var borderDisabledC: Color { Color(borderDisabled) }
    var textDisabledC: Color { Color(textDisabled) }
    var iconDefaultC: Color { Color(iconDefault) }
    var iconHoverC: Color { Color(iconHover) }
    var iconDisabledC: Color { Color(iconDisabled) }
    var successC: Color { Color(success) }
    var dangerC: Color { Color(danger) }
    var warningC: Color { Color(warning) }

    // MARK: - Gradients (Warp-inspired)

    /// Subtle header gradient for sidebar headers
    var headerGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: surfaceElevatedC, location: 0.0),
                .init(color: backgroundC, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Glass-like gradient for elevated surfaces
    var glassGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: surfaceElevatedC.opacity(0.8), location: 0.0),
                .init(color: surfaceElevatedC.opacity(0.4), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Spacing (Theme-Independent)

    static let spacing4: CGFloat = 4
    static let spacing6: CGFloat = 6
    static let spacing8: CGFloat = 8
    static let spacing10: CGFloat = 10
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16

    // MARK: - Corner Radius

    static let radiusSmall: CGFloat = 4
    static let radiusMedium: CGFloat = 6
    static let radiusLarge: CGFloat = 8

    // MARK: - Animation Timing

    static let animationFast: Double = 0.10   // Warp uses 100ms for hover
    static let animationNormal: Double = 0.20
    static let animationSlow: Double = 0.30

    static let springResponse: Double = 0.30
    static let springDamping: Double = 0.75
}

// MARK: - NSColor Extensions for Theme Derivation
// Note: `luminance` and `hexString` are already defined in OSColor+Extension.swift

extension NSColor {
    /// Blend with white overlay at given opacity (Warp-style surface layering)
    func blendedOverlay(white opacity: CGFloat) -> NSColor {
        guard let base = usingColorSpace(.sRGB) else { return self }
        let r = base.redComponent + (1.0 - base.redComponent) * opacity
        let g = base.greenComponent + (1.0 - base.greenComponent) * opacity
        let b = base.blueComponent + (1.0 - base.blueComponent) * opacity
        return NSColor(red: min(r, 1.0), green: min(g, 1.0), blue: min(b, 1.0), alpha: base.alphaComponent)
    }

    /// Blend with black overlay at given opacity
    func blendedOverlay(black opacity: CGFloat) -> NSColor {
        guard let base = usingColorSpace(.sRGB) else { return self }
        let r = base.redComponent * (1.0 - opacity)
        let g = base.greenComponent * (1.0 - opacity)
        let b = base.blueComponent * (1.0 - opacity)
        return NSColor(red: max(r, 0.0), green: max(g, 0.0), blue: max(b, 0.0), alpha: base.alphaComponent)
    }
}
