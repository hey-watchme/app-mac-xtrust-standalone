import SwiftUI

// MARK: - XTrust Design System Tokens

enum XT {

    // MARK: Colors
    enum C {
        // macOS system adaptive colors — correct in both light and dark mode
        static let windowBG         = Color(nsColor: .windowBackgroundColor)
        static let cardBG           = Color(nsColor: .controlBackgroundColor)
        static let divider          = Color(nsColor: .separatorColor)
        static let textPrimary      = Color(nsColor: .labelColor)
        static let textSecondary    = Color(nsColor: .secondaryLabelColor)
        static let textTertiary     = Color(nsColor: .tertiaryLabelColor)

        // Hover / selection surfaces
        static let selectedBG       = Color.accentColor.opacity(0.10)
        static let hoveredBG        = Color(nsColor: .labelColor).opacity(0.04)
        static let pressedBG        = Color(nsColor: .labelColor).opacity(0.08)

        // Semantic status
        static let recording        = Color(red: 0.94, green: 0.27, blue: 0.27)
        static let recordingBG      = Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.07)
        static let recordingBorder  = Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.18)

        static let success          = Color(red: 0.13, green: 0.76, blue: 0.35)
        static let successBG        = Color(red: 0.13, green: 0.76, blue: 0.35).opacity(0.09)

        static let warning          = Color(red: 0.95, green: 0.62, blue: 0.04)
        static let warningBG        = Color(red: 0.95, green: 0.62, blue: 0.04).opacity(0.09)

        static let destructive      = Color(red: 0.94, green: 0.27, blue: 0.27)
        static let accent           = Color.accentColor
    }

    // MARK: Fonts
    enum F {
        static let displayTitle = Font.system(size: 20, weight: .semibold)
        static let sectionLabel = Font.system(size: 11, weight: .semibold)
        static let sidebarItem  = Font.system(size: 13, weight: .medium)
        static let sidebarSub   = Font.system(size: 11, weight: .regular)
        static let body         = Font.system(size: 13, weight: .regular)
        static let caption      = Font.system(size: 11, weight: .regular)
        static let mono         = Font.system(size: 11, design: .monospaced)
    }

    // MARK: Spacing
    enum S {
        static let xxs: CGFloat  =  2
        static let xs:  CGFloat  =  4
        static let sm:  CGFloat  =  8
        static let md:  CGFloat  = 12
        static let lg:  CGFloat  = 16
        static let xl:  CGFloat  = 20
        static let xxl: CGFloat  = 28
        static let xxxl: CGFloat = 40
    }

    // MARK: Corner Radii
    enum R {
        static let sm: CGFloat  =  6
        static let md: CGFloat  =  8
        static let lg: CGFloat  = 12
        static let xl: CGFloat  = 16
    }

    // MARK: Layout
    enum Layout {
        static let sidebarWidth:    CGFloat = 240
        static let contentPadding:  CGFloat = 28
        static let contentMaxWidth: CGFloat = 840
        static let cardRadius:      CGFloat = 10
    }
}
