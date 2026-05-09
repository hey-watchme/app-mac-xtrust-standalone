# UI Design System

Date: 2026-05-09

## Concept

**Ambient Memo** — an ambient recording companion that fades into the background.
The app captures, transcribes, and summarizes meetings without demanding attention.

Design goals:
- Minimal chrome. Content is always primary.
- Native macOS feel with premium polish (think Craft, Linear, Bear).
- Correct behavior in both light and dark mode without any custom overrides.
- Smooth micro-interactions: hover states, pulsing indicators, animated meters.

---

## File Map

```
XTrustMacApp/
  Shared/
    XTrustTheme.swift       ← design tokens (enum XT)
    XTrustComponents.swift  ← shared components
  Features/Sessions/
    SessionListView.swift   ← NavigationSplitView root + sidebar
    SessionDetailView.swift ← session content area
  Resources/
    logo_xtrust_black.svg   ← original SVG wordmark
```

---

## Design Tokens (`XTrustTheme.swift`)

All tokens live under the `XT` namespace. Namespaces are single-letter sub-enums to keep call sites compact (`XT.C.recording`, `XT.S.lg`, etc.).

### Colors — `XT.C`

```swift
XT.C.windowBG          // NSColor.windowBackgroundColor  (adaptive)
XT.C.cardBG            // NSColor.controlBackgroundColor (adaptive)
XT.C.divider           // NSColor.separatorColor         (adaptive)
XT.C.textPrimary       // NSColor.labelColor             (adaptive)
XT.C.textSecondary     // NSColor.secondaryLabelColor    (adaptive)
XT.C.textTertiary      // NSColor.tertiaryLabelColor     (adaptive)
XT.C.selectedBG        // accentColor × 0.10
XT.C.hoveredBG         // labelColor  × 0.04
XT.C.pressedBG         // labelColor  × 0.08
XT.C.recording         // #EF4444  (red-500 equivalent)
XT.C.recordingBG       // recording  × 0.07
XT.C.recordingBorder   // recording  × 0.18
XT.C.success           // #22C55E  (green-500 equivalent)
XT.C.successBG         // success   × 0.09
XT.C.warning           // #F59E0B  (amber-500 equivalent)
XT.C.warningBG         // warning   × 0.09
XT.C.accent            // Color.accentColor (user-configurable)
```

macOS adaptive colors (`NSColor.*`) handle dark mode automatically — no manual `colorScheme` switching required.

### Fonts — `XT.F`

| Token | Size | Weight | Use |
|---|---|---|---|
| `XT.F.displayTitle` | 20 | semibold | Session title in detail header |
| `XT.F.sectionLabel` | 11 | semibold | Section headers (uppercased) |
| `XT.F.sidebarItem`  | 13 | medium   | Session row primary text |
| `XT.F.sidebarSub`   | 11 | regular  | Session row secondary text |
| `XT.F.body`         | 13 | regular  | Transcript text, button labels |
| `XT.F.caption`      | 11 | regular  | Metadata, timestamps (non-mono) |
| `XT.F.mono`         | 11 | —        | Timestamps, file paths |

### Spacing — `XT.S`

```
xxs =  2   xs =  4   sm =  8   md = 12
lg  = 16   xl = 20   xxl = 28  xxxl = 40
```

### Corner Radii — `XT.R`

```
sm = 6   md = 8   lg = 12   xl = 16
```

### Layout — `XT.Layout`

```
sidebarWidth    = 240
contentPadding  = 28
contentMaxWidth = 840
cardRadius      = 10
```

---

## Shared Components (`XTrustComponents.swift`)

### `XTrustLogoView`

Renders the XTRUST wordmark using system typography.

```swift
XTrustLogoView()                    // primary color
XTrustLogoView(color: .white)       // white variant (for dark backgrounds)
```

**Upgrading to SVG:** Once `logo_xtrust_black.svg` is added to the Xcode
asset catalog as `XTrustLogo`, replace the `Text` rendering in
`XTrustComponents.swift:13–20` with:

```swift
Image("XTrustLogo")
    .resizable()
    .scaledToFit()
    .frame(height: 14)
```

### Status Badges

```swift
XTSessionStatusBadge(status: session.status)    // Session.Status
XTTopicSummaryBadge(status: topic.summaryStatus) // Topic.SummaryStatus
```

Pill-shaped labels with color-coded foreground and background per state.
States: draft · recording · completed · failed · closed / idle · running · completed · failed.

### `RecordingDot`

Pulsing red circle using a `repeatForever` scale + opacity animation.
Appears in the sidebar row (when session is recording) and inside each active topic header.

### `AudioLevelMeter`

```swift
AudioLevelMeter(level: appState.audioLevel)  // Float 0.0–1.0
```

11-bar capsule visualizer. Each bar has a fixed sensitivity offset so bars
reach different heights at the same audio level, creating a natural-looking
spectrum shape. Animated with `.linear(duration: 0.07)` per level update.

### `XTCard`

Generic card container with `controlBackgroundColor` fill, 0.5pt border, and subtle drop shadow.

```swift
XTCard {
    VStack { ... }
}
```

### Button Styles

| Style | Use |
|---|---|
| `XTPrimaryButtonStyle` | Primary CTA (Start recording) |
| `XTSecondaryButtonStyle` | Secondary action (Summarize, Copy wrap-up) |
| `XTDestructiveButtonStyle` | Destructive action (Stop recording) |
| `XTIconButtonStyle` | Icon-only toolbar buttons (Info, settings) |
| `XTSidebarRowStyle` | Internal — sidebar row hover/selected state |

All styles include a `0.97` scale-down on press with `easeInOut(0.1)` animation.

---

## Layout Structure

```
NavigationSplitView (balanced style)
├── Sidebar  [min 200, ideal 240, max 320]
│   ├── Header: XTrustLogoView
│   ├── ScrollView → LazyVStack → SidebarSessionRow (×N)
│   └── Footer: 新規セッション button
└── Detail
    ├── Session header bar  [h=64]
    │   ├── Title + status badge + duration
    │   └── [まとめをコピー]  [ⓘ info]
    ├── Divider
    └── ScrollView → VStack (maxWidth 840, padding 28)
        ├── Recording bar  (when isListening)
        │     RecordingDot · status text · AudioLevelMeter · [停止]
        │   OR
        │   Control bar  (when idle)
        │     [録音開始]  [会議を要約]  · · · Status picker
        ├── Error banner  (warningBG + amber border)
        ├── Meeting summary card  (XTCard)
        └── TopicCardView (×N)
            ├── Header row  [h=46]
            │   Topic N · timestamp · RecordingDot? · badge · [要約]
            ├── Summary area  (Gemma 4 output)
            └── Utterance rows
                timestamp(72pt) · transcript · [···] on hover
```

### Sidebar Session Row

```
● ─  5月9日（金）         ✓
     14:00  ·  3件
```

- 6pt status dot (red when recording, transparent otherwise)
- Line 1: `M月d日（E）`  medium weight
- Line 2: `H:mm` + utterance count  secondary color
- Right: status icon (system SF Symbol)
- Selected: `accentColor × 0.10` background
- Hovered:  `labelColor × 0.04` background

---

## Logo Integration (TODO)

The SVG wordmark `logo_xtrust_black.svg` is saved in `Resources/`.
To use it as a proper vector asset in the app:

1. In Xcode → `XTrustMacApp` target → open or create `Assets.xcassets`
2. Drag `logo_xtrust_black.svg` into the catalog
3. Name the imageset `XTrustLogo`
4. In Attributes Inspector → set **Render As: Template Image** and **Preserve Vector Data: ON**
5. Edit `XTrustComponents.swift` `XTrustLogoView`:

```swift
// Replace the HStack Text blocks with:
Image("XTrustLogo")
    .resizable()
    .renderingMode(.template)
    .scaledToFit()
    .frame(height: 14)
    .foregroundStyle(color)
```

For a white variant (dark sidebar), the template rendering mode allows tinting via `.foregroundStyle`.
