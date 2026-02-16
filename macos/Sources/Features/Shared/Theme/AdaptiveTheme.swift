import SwiftUI
import AppKit

/// JetBrains-inspired adaptive theme system that derives colors from terminal background
/// or system appearance. Uses warm neutral grays with compact density.
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

    // Dark palette (JetBrains New UI Dark / Darcula)
    private static let darkBase = NSColor(red: 0.169, green: 0.176, blue: 0.188, alpha: 1.0) // #2B2D30

    // Light palette (JetBrains New UI Light)
    private static let lightBase = NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0) // #FFFFFF

    // MARK: - Background Colors

    /// Primary sidebar background
    var background: NSColor {
        if let bg = terminalBackground {
            return bg
        }
        return isDark
            ? Self.darkBase
            : NSColor(red: 0.969, green: 0.973, blue: 0.980, alpha: 1.0) // #F7F8FA
    }

    /// Elevated surface (headers, toolbars, cards)
    var surfaceElevated: NSColor {
        isDark
            ? base.blendedOverlay(white: 0.04)
            : NSColor(red: 0.922, green: 0.929, blue: 0.941, alpha: 1.0) // #EBEDF0
    }

    /// Hover state surface
    var surfaceHover: NSColor {
        isDark
            ? base.blendedOverlay(white: 0.08)
            : NSColor(red: 0.875, green: 0.882, blue: 0.898, alpha: 1.0) // #DFE1E5
    }

    /// Selection background (subtle)
    var selection: NSColor {
        isDark
            ? NSColor(red: 0.184, green: 0.396, blue: 0.792, alpha: 0.25) // #2F65CA
            : NSColor(red: 0.208, green: 0.455, blue: 0.941, alpha: 0.12) // #3574F0
    }

    /// Active selection background (stronger)
    var selectionActive: NSColor {
        isDark
            ? NSColor(red: 0.184, green: 0.396, blue: 0.792, alpha: 0.45) // #2F65CA
            : NSColor(red: 0.208, green: 0.455, blue: 0.941, alpha: 0.22) // #3574F0
    }

    /// Focus ring for keyboard navigation
    var focusRing: NSColor {
        NSColor(red: 0.208, green: 0.455, blue: 0.941, alpha: 1.0) // #3574F0
    }

    // MARK: - Border Colors

    /// Primary border/divider
    var border: NSColor {
        isDark
            ? NSColor(red: 0.263, green: 0.271, blue: 0.290, alpha: 1.0) // #43454A
            : NSColor(red: 0.831, green: 0.831, blue: 0.831, alpha: 1.0) // #D4D4D4
    }

    /// Subtle border (lighter)
    var borderSubtle: NSColor {
        isDark
            ? NSColor(red: 0.224, green: 0.231, blue: 0.251, alpha: 1.0) // #393B40
            : NSColor(red: 0.922, green: 0.925, blue: 0.941, alpha: 1.0) // #EBECF0
    }

    /// Disabled border
    var borderDisabled: NSColor {
        borderSubtle.withAlphaComponent(0.5)
    }

    // MARK: - Text Colors

    /// Primary text (highest contrast)
    var textPrimary: NSColor {
        isDark
            ? NSColor(red: 0.737, green: 0.745, blue: 0.769, alpha: 1.0) // #BCBEC4
            : NSColor(red: 0.118, green: 0.122, blue: 0.133, alpha: 1.0) // #1E1F22
    }

    /// Secondary text
    var textSecondary: NSColor {
        isDark
            ? NSColor(red: 0.435, green: 0.451, blue: 0.478, alpha: 1.0) // #6F737A
            : NSColor(red: 0.435, green: 0.451, blue: 0.478, alpha: 1.0) // #6F737A
    }

    /// Muted text (lowest contrast)
    var textMuted: NSColor {
        isDark
            ? NSColor(red: 0.353, green: 0.365, blue: 0.388, alpha: 1.0) // #5A5D63
            : NSColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 1.0) // #8C8C8C
    }

    /// Disabled text
    var textDisabled: NSColor {
        textMuted.withAlphaComponent(0.5)
    }

    // MARK: - Accent Colors

    /// Primary accent (JetBrains blue)
    var accent: NSColor {
        isDark
            ? NSColor(red: 0.310, green: 0.533, blue: 0.933, alpha: 1.0) // #4F88EE
            : NSColor(red: 0.208, green: 0.455, blue: 0.941, alpha: 1.0) // #3574F0
    }

    /// Folder icon color
    var folderIcon: NSColor {
        isDark
            ? NSColor(red: 0.424, green: 0.604, blue: 0.937, alpha: 1.0) // #6C9AEF
            : NSColor(red: 0.290, green: 0.525, blue: 0.784, alpha: 1.0) // #4A86C8
    }

    /// Markdown/file icon color
    var markdownIcon: NSColor {
        isDark
            ? NSColor(red: 0.780, green: 0.490, blue: 0.733, alpha: 1.0) // #C77DBB
            : NSColor(red: 0.596, green: 0.463, blue: 0.667, alpha: 1.0) // #9876AA
    }

    /// Success color
    var success: NSColor {
        isDark
            ? NSColor(red: 0.286, green: 0.612, blue: 0.329, alpha: 1.0) // #499C54
            : NSColor(red: 0.349, green: 0.659, blue: 0.412, alpha: 1.0) // #59A869
    }

    /// Danger color
    var danger: NSColor {
        isDark
            ? NSColor(red: 0.969, green: 0.329, blue: 0.392, alpha: 1.0) // #F75464
            : NSColor(red: 0.859, green: 0.345, blue: 0.376, alpha: 1.0) // #DB5860
    }

    /// Warning color
    var warning: NSColor {
        isDark
            ? NSColor(red: 0.910, green: 0.639, blue: 0.239, alpha: 1.0) // #E8A33D
            : NSColor(red: 0.745, green: 0.569, blue: 0.090, alpha: 1.0) // #BE9117
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

    // MARK: - Gradients

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

    /// Flat toolbar gradient (JetBrains uses minimal depth)
    var glassGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: surfaceElevatedC, location: 0.0),
                .init(color: surfaceElevatedC.opacity(0.9), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Spacing

    static let spacing4: CGFloat = 4
    static let spacing6: CGFloat = 6
    static let spacing8: CGFloat = 8
    static let spacing10: CGFloat = 10
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16

    // MARK: - Corner Radius

    static let radiusSmall: CGFloat = 6
    static let radiusMedium: CGFloat = 8
    static let radiusLarge: CGFloat = 12

    // MARK: - Animation Timing

    static let animationFast: Double = 0.10
    static let animationNormal: Double = 0.20
    static let animationSlow: Double = 0.30

    static let springResponse: Double = 0.30
    static let springDamping: Double = 0.75
}

// MARK: - NSColor Extensions for Theme Derivation
// Note: `luminance` and `hexString` are already defined in OSColor+Extension.swift

extension NSColor {
    /// Blend with white overlay at given opacity (surface layering)
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
