import SwiftUI
import AppKit

/// Warp-inspired dark theme colors for markdown panels
enum PanelTheme {
    // MARK: - Background Colors
    /// Primary panel background: #0D1117
    static let background = NSColor(red: 0.051, green: 0.067, blue: 0.090, alpha: 1.0)

    /// Elevated surface (headers, toolbars): #161B22
    static let surfaceElevated = NSColor(red: 0.086, green: 0.106, blue: 0.133, alpha: 1.0)

    /// Subtle surface for hover states: #21262D
    static let surfaceHover = NSColor(red: 0.129, green: 0.149, blue: 0.176, alpha: 1.0)

    /// Selection background: #1F6FEB with 20% opacity
    static let selection = NSColor(red: 0.122, green: 0.435, blue: 0.922, alpha: 0.2)

    /// Active selection: #1F6FEB with 35% opacity
    static let selectionActive = NSColor(red: 0.122, green: 0.435, blue: 0.922, alpha: 0.35)

    // MARK: - Border Colors
    /// Divider/separator: #30363D
    static let border = NSColor(red: 0.188, green: 0.212, blue: 0.239, alpha: 1.0)

    /// Subtle border: #21262D
    static let borderSubtle = NSColor(red: 0.129, green: 0.149, blue: 0.176, alpha: 1.0)

    // MARK: - Text Colors
    /// Primary text: #E6EDF3
    static let textPrimary = NSColor(red: 0.902, green: 0.929, blue: 0.953, alpha: 1.0)

    /// Secondary text: #8B949E
    static let textSecondary = NSColor(red: 0.545, green: 0.580, blue: 0.620, alpha: 1.0)

    /// Muted text: #6E7681
    static let textMuted = NSColor(red: 0.431, green: 0.463, blue: 0.506, alpha: 1.0)

    // MARK: - Accent Colors
    /// Primary accent (blue): #58A6FF
    static let accent = NSColor(red: 0.345, green: 0.651, blue: 1.0, alpha: 1.0)

    /// Folder icon: #54AEFF
    static let folderIcon = NSColor(red: 0.329, green: 0.682, blue: 1.0, alpha: 1.0)

    /// Markdown file icon: #F78166
    static let markdownIcon = NSColor(red: 0.969, green: 0.506, blue: 0.400, alpha: 1.0)

    /// Success/green: #3FB950
    static let success = NSColor(red: 0.247, green: 0.725, blue: 0.314, alpha: 1.0)

    // MARK: - Icon button colors
    /// Icon default: #8B949E
    static let iconDefault = textSecondary

    /// Icon hover: #E6EDF3
    static let iconHover = textPrimary

    // MARK: - Spacing
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

    // MARK: - Animation
    static let animationFast: Double = 0.15
    static let animationNormal: Double = 0.25
    static let animationSlow: Double = 0.35

    static let springResponse: Double = 0.35
    static let springDamping: Double = 0.8
}
