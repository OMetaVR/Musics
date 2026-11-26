import SwiftUI

/// music.lan's palette: solid near-black surfaces, quiet edges, one green accent.
enum Theme {
    static let bg = Color(hex: "#0A0A0B")!
    static let panel = Color(hex: "#0F1012")!
    static let cell = Color(hex: "#121316")!
    static let cellHi = Color(hex: "#16171B")!
    static let line = Color(hex: "#1E2024")!
    static let edge = Color(hex: "#2A2D32")!
    static let ink = Color(hex: "#E8E9EB")!
    static let inkHi = Color(hex: "#F2F3F4")!
    static let ink2 = Color(hex: "#A6A9AF")!
    static let ink3 = Color(hex: "#80848C")!
    static let accent = Color(hex: "#5CCB8A")!
    static let accentBg = Color(hex: "#10291B")!
    static let accentEdge = Color(hex: "#2B6B45")!
    static let danger = Color(hex: "#E5695F")!
    static let nowPlayingFallback = Color(hex: "#28282C")!

    static let radius: CGFloat = 8
    static let gutter: CGFloat = 16
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
    /// Section title style used across Home and detail screens.
    func sectionTitle() -> some View {
        font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.inkHi)
    }

    func cardBackground() -> some View {
        background(Theme.cell, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
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
}
