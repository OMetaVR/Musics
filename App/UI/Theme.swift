import SwiftUI
import UIKit

/// "The sleeve": a personal record collection. Graphite night, warm paper type, condensed headlines,
/// and colour that comes from each album's artwork rather than a fixed accent.
enum Theme {
    // Core palette.
    /// Blue-graphite base: dark, but never black, so album tints read as colour rather than glow.
    static let night = Color(hex: "#16181D")!
    /// Raised surfaces: rows when pressed, panels, the tab bar.
    static let deck = Color(hex: "#1F2229")!
    static let deckHi = Color(hex: "#272A32")!
    /// Rules and outlines.
    static let groove = Color(hex: "#30343D")!
    /// Primary text: warm off-white, like a printed sleeve.
    static let paper = Color(hex: "#EEEAE2")!
    static let dust = Color(hex: "#A29E95")!
    static let ash = Color(hex: "#6E6B66")!
    /// music.lan's green, used only for state: playing, liked, online, downloaded.
    static let lan = Color(hex: "#6FD39A")!
    static let lanDeep = Color(hex: "#1E3A2A")!
    static let danger = Color(hex: "#E5695F")!
    /// Sleeve colour when an album has none.
    static let sleeveFallback = Color(hex: "#2B2E36")!

    // Older names used across the app, mapped onto the palette.
    static let bg = night
    static let panel = deck
    static let cell = deck
    static let cellHi = deckHi
    static let line = groove
    static let edge = groove
    static let ink = paper
    static let inkHi = paper
    static let ink2 = dust
    static let ink3 = ash
    static let accent = lan
    static let accentBg = lanDeep
    static let accentEdge = Color(hex: "#2F6B48")!
    static let nowPlayingFallback = sleeveFallback

    // Radii by role, not one radius for everything.
    /// Artwork is a record sleeve: nearly square.
    static let artRadius: CGFloat = 3
    static let panelRadius: CGFloat = 14
    static let radius: CGFloat = 10
    static let gutter: CGFloat = 18
}

/// Barlow Semi Condensed (music.lan's face) for headlines; SF for everything read at length.
enum Typeface {
    enum Weight: String { case medium = "Medium", semibold = "SemiBold", bold = "Bold", extraBold = "ExtraBold" }

    static func condensed(_ size: CGFloat, _ weight: Weight = .bold, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("BarlowSemiCondensed-\(weight.rawValue)", size: size, relativeTo: style)
    }

    static func uiCondensed(_ size: CGFloat, _ weight: Weight) -> UIFont {
        UIFont(name: "BarlowSemiCondensed-\(weight.rawValue)", size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }

    // Scale (≈1.25): 13 · 15 · 17 · 21 · 26 · 34 · 44
    static let screenTitle = condensed(34, .extraBold, relativeTo: .largeTitle)
    static let sectionTitle = condensed(24, .bold, relativeTo: .title2)
    static let cardTitle = condensed(17, .semibold, relativeTo: .headline)
    static let label = condensed(15, .semibold, relativeTo: .subheadline)

    /// Navigation bars in the house style, set once at launch.
    static func applyAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.night)
        nav.shadowColor = .clear
        nav.largeTitleTextAttributes = [.font: uiCondensed(34, .extraBold), .foregroundColor: UIColor(Theme.paper)]
        nav.titleTextAttributes = [.font: uiCondensed(18, .bold), .foregroundColor: UIColor(Theme.paper)]
        let plain = UIBarButtonItemAppearance()
        plain.normal.titleTextAttributes = [.font: uiCondensed(17, .semibold), .foregroundColor: UIColor(Theme.paper)]
        nav.buttonAppearance = plain
        nav.backButtonAppearance = plain
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(Theme.paper)
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Theme.deckHi)
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255, opacity: 1)
    }
}

extension View {
    func sectionTitle() -> some View {
        font(Typeface.sectionTitle).foregroundStyle(Theme.paper)
    }

    func cardBackground() -> some View {
        background(Theme.deck, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

enum Format {
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func duration(_ seconds: Double) -> String {
        let m = Int(seconds / 60)
        if m < 60 { return "\(m) min" }
        return "\(m / 60) h \(m % 60) min"
    }

    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    static func songs(_ n: Int) -> String { n == 1 ? "1 song" : "\(n.formatted()) songs" }

    /// "2020, 12 songs, 43 min": plain commas rather than dot-separated meta strings.
    static func list(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
