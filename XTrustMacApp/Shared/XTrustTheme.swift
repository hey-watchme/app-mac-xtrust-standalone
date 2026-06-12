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

        // --- Mockup palette (nav rail / sidebar) ---
        static let navRail          = Color(hex: "#0C1226")
        static let navBg            = Color(hex: "#131A2E")
        static let navBg2           = Color(hex: "#1A2238")
        static let navText          = Color(red: 0.91, green: 0.93, blue: 0.98).opacity(0.92)
        static let navTextDim       = Color(red: 0.81, green: 0.84, blue: 0.92).opacity(0.58)
        static let navTextMute      = Color(red: 0.81, green: 0.84, blue: 0.92).opacity(0.38)
        static let navHover         = Color.white.opacity(0.045)
        static let navActive        = Color(hex: "#6366F1").opacity(0.22)
        static let navActiveLine    = Color(hex: "#A5B4FC").opacity(0.35)
        static let navDivider       = Color.white.opacity(0.06)

        // Accent (indigo)
        static let accentIndigo     = Color(hex: "#4F46E5")
        static let accentIndigo2    = Color(hex: "#6366F1")
        static let accentSoft       = Color(hex: "#EEF2FF")
        static let accentInk        = Color(hex: "#3730A3")
        static let accentLine       = Color(hex: "#C7D2FE")

        // Live/red
        static let live             = Color(hex: "#EF4444")
        static let liveSoft         = Color(hex: "#FEE2E2")
        static let liveLine         = Color(hex: "#FECACA")
        static let liveInk          = Color(hex: "#991B1B")

        // Green
        static let ok               = Color(hex: "#10B981")
        static let okSoft           = Color(hex: "#D1FAE5")
        static let okInk            = Color(hex: "#065F46")

        // Amber
        static let warn2            = Color(hex: "#F59E0B")
        static let warnSoft         = Color(hex: "#FEF3C7")
        static let warnInk          = Color(hex: "#92400E")

        // Main content (light)
        static let ink              = Color(hex: "#14181F")
        static let ink2             = Color(hex: "#3C4148")
        static let ink3             = Color(hex: "#6B6F76")
        static let ink4             = Color(hex: "#8E939B")
        static let line             = Color(hex: "#E6E7EA")
        static let line2            = Color(hex: "#EFF0F2")
        static let panel            = Color(hex: "#F7F7F8")
        static let panel2           = Color(hex: "#FAFAFB")
        static let winBg            = Color.white
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

        // Extended for mockup
        static let meetingTitle = Font.system(size: 22, weight: .bold)
        static let speakerName  = Font.system(size: 14, weight: .bold)
        static let transcriptBody = Font.system(size: 14.5)
        static let timestamp    = Font.system(size: 11, design: .monospaced)
        static let sectionHeader = Font.system(size: 11, weight: .semibold)
        static let inspectorBody = Font.system(size: 12.5)
        static let navRow       = Font.system(size: 13.5)
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

        // New Slack-style layout
        static let railWidth:       CGFloat = 60
        static let slackSidebarWidth: CGFloat = 264
        static let inspectorWidth:  CGFloat = 384
    }
}

// MARK: - Color hex initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
