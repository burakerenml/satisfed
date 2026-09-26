//
//  DesignSystem.swift
//  Shiphaton App
//
//  Brand palette, typography and spacing tokens.
//  Warm blush base + deep navy ink, with a signature color per compound:
//  protein = rose, fibre = sage, healthy fats = honey.
//

import SwiftUI
import UIKit

// MARK: - Adaptive color helper

extension Color {
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Palette

enum Palette {
    /// Warm, blush-tinted app background.
    static let canvas = Color(light: "FBF4F1", dark: "191C24")
    /// Elevated card surface.
    static let card = Color(light: "FFFFFF", dark: "232836")
    /// Soft blush tint used for secondary surfaces.
    static let blush = Color(light: "F7E7E2", dark: "2C2A33")
    /// Pale steel-blue tint for secondary surfaces.
    static let mist = Color(light: "E9EFF3", dark: "252B38")

    /// Deep navy ink — primary text.
    static let ink = Color(light: "2E3A54", dark: "EFEAE6")
    /// Secondary text. Kept warm-grey but dark enough to stay readable
    /// on the cream canvas.
    static let inkSoft = Color(light: "797685", dark: "A3A7B3")
    /// Faint strokes / separators.
    static let hairline = Color(light: "EFE4DF", dark: "313747")

    /// Primary action rose.
    static let rose = Color(light: "DE8379", dark: "E8938A")
    static let roseDeep = Color(light: "CF6E63", dark: "D97F74")
    static let roseTint = Color(light: "FAE3DF", dark: "3A2E31")

    /// Compound: protein.
    static let protein = Color(light: "D98079", dark: "E8938A")
    static let proteinTint = Color(light: "F9E2DF", dark: "3A2E31")
    /// Compound: fibre.
    static let fibre = Color(light: "7FA377", dark: "94B98C")
    static let fibreTint = Color(light: "E7EFE3", dark: "2A3330")
    /// Compound: healthy fats.
    static let honey = Color(light: "DFAE55", dark: "E9BE6C")
    static let honeyTint = Color(light: "F9EDD7", dark: "38322A")

    /// Doorway tints. Deliberately outside the trio's three hues: rose,
    /// sage and gold mean protein, fibre and fats everywhere else in the
    /// app, so the feature tiles borrow none of them.
    static let slate = Color(light: "6B87A4", dark: "8FA9C2")
    static let slateTint = Color(light: "E4ECF3", dark: "232A36")
    static let lilac = Color(light: "8B80B0", dark: "A99CD1")
    static let lilacTint = Color(light: "EDE8F5", dark: "2A2735")
    /// Warm berry for the craving doorway. The tile is about appetite, so
    /// it stays on the warm side of the canvas and leaves the cool half to
    /// the recipe maker next to it. Pink-purple rather than coral, so it
    /// never gets mistaken for the protein rose.
    static let berry = Color(light: "A34467", dark: "D0819C")
    static let berryTint = Color(light: "F8DFE7", dark: "36222B")

    /// Ring track / empty state.
    static let track = Color(light: "F0E7E3", dark: "2D3342")

    /// Bottom edge of the hero card's near-white vertical gradient.
    static let heroBottom = Color(light: "FFF6F2", dark: "202531")

    static var roseGradient: LinearGradient {
        LinearGradient(colors: [rose, roseDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Typography

extension Font {
    /// Big friendly headline (SF Rounded).
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Editorial serif, used for the daily hype note.
    static func editorial(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Spacing & shape

enum Metrics {
    static let screenMargin: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let chipRadius: CGFloat = 14
    /// Room for the floating tab bar at the bottom of scroll content.
    /// Compact glass bar (~65pt) + breathing room.
    static let tabBarClearance: CGFloat = 116

    /// Spacing scale — use these instead of ad-hoc padding values.
    static let spaceS: CGFloat = 8
    static let spaceM: CGFloat = 12
    static let spaceL: CGFloat = 16
    /// Vertical rhythm between Home sections.
    static let sectionGap: CGFloat = 28
}

// MARK: - Responsive layout

/// Per-device layout, measured once at the root and read down the tree.
///
/// The fixed numbers in `Metrics` are the floor; this is what actually
/// spaces the three tab screens, so a mini and a Pro Max each get a rhythm
/// that fits their glass rather than one tuned for a 6.3" phone. Measured
/// from the root `GeometryReader` — never from `UIApplication` inside a
/// `body`, which freezes SwiftUI updates.
struct Layout: Equatable {
    var size: CGSize
    var safeBottom: CGFloat

    /// Used until the root measures the real window (previews, sheets).
    static let standard = Layout(size: CGSize(width: 393, height: 852), safeBottom: 34)

    /// SE and mini class: short enough that the vertical rhythm has to tighten.
    var isShort: Bool { size.height < 740 }
    /// Plus / Pro Max class: wide enough to earn a deeper margin.
    var isWide: Bool { size.width >= 420 }

    var screenMargin: CGFloat { isWide ? 24 : 20 }
    /// Air between Home's sections. The screen has five of them, so this is
    /// the single number that decides whether the page breathes or crams.
    var sectionGap: CGFloat { isShort ? 24 : 32 }
    /// The hero ring scales with the glass instead of pinning one size.
    var heroRing: CGFloat { isShort ? 138 : (isWide ? 176 : 164) }
    var heroLineWidth: CGFloat { isShort ? 12 : 14 }

    // MARK: Floating tab bar

    /// Capsule height: icon (22) + gap (3) + label (~12) + inner padding.
    var tabBarHeight: CGFloat { 61 }
    /// Home-indicator devices float the bar on their safe area; home-button
    /// devices (zero inset) need their own air.
    var tabBarEdgePadding: CGFloat { safeBottom > 0 ? 2 : 14 }
    /// Distance from the bottom of the screen to the top of the bar.
    var tabBarTop: CGFloat { safeBottom + tabBarEdgePadding + tabBarHeight }

    /// Bottom padding every scroll screen owes the floating bar. Scroll
    /// views draw all the way to the bottom of the glass, so this is
    /// measured from there: at the end of a scroll the last card sits fully
    /// above the tabs with air to spare.
    var tabBarClearance: CGFloat { tabBarTop + 30 }
}

private struct LayoutKey: EnvironmentKey {
    static let defaultValue = Layout.standard
}

extension EnvironmentValues {
    var layout: Layout {
        get { self[LayoutKey.self] }
        set { self[LayoutKey.self] = newValue }
    }
}

// MARK: - Haptics

enum Haptics {
    /// Every buzz in the app goes through here, so the You tab's switch is
    /// the single place that turns feedback off. Defaults to on.
    private static var isOn: Bool {
        UserDefaults.standard.object(forKey: ProfileKey.haptics) as? Bool ?? true
    }

    static func tap() {
        guard isOn else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func soft() {
        guard isOn else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func success() {
        guard isOn else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Card style

struct SoftCard: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(Palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                            .strokeBorder(Palette.hairline.opacity(0.65), lineWidth: 1)
                    )
                    .shadow(color: Color(hex: "2E3A54").opacity(0.04), radius: 3, y: 2)
                    .shadow(color: Color(hex: "2E3A54").opacity(0.07), radius: 22, y: 10)
            )
    }
}

extension View {
    func softCard(padding: CGFloat = 18) -> some View {
        modifier(SoftCard(padding: padding))
    }
}
