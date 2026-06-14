//
//  GGTheme.swift
//  KisMAC — Golden Gate UI (Stage 1)
//
//  Design system ported from the macOS Golden Gate (Tahoe / Liquid Glass)
//  redesign. Mirrors the styles.css :root tokens: accent, inks, hairlines,
//  signal colors, encryption colors, panel colors, window radius, and fonts.
//
//  Dark appearance only. Tasteful glass on chrome, calm content.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

@available(macOS 12.0, *)
enum GGTheme {

    // MARK: - Accent
    static let accent      = Color(hex: 0x0A84FF)                 // --accent
    static let accentSoft  = Color(hex: 0x0A84FF, alpha: 0.20)    // --accent-soft
    static let accentLine  = Color(hex: 0x0A84FF, alpha: 0.55)    // --accent-line
    static let accentGlow  = Color(hex: 0x0A84FF, alpha: 0.45)    // --accent-glow

    // MARK: - Inks (text on dark)
    static let ink  = Color.white.opacity(0.94)   // --ink
    static let ink2 = Color.white.opacity(0.60)   // --ink-2
    static let ink3 = Color.white.opacity(0.38)   // --ink-3
    static let ink4 = Color.white.opacity(0.22)   // --ink-4

    // MARK: - Hairlines
    static let hair  = Color.white.opacity(0.085)  // --hair
    static let hair2 = Color.white.opacity(0.14)   // --hair-2

    // MARK: - Window / panels
    static let windowRadius: CGFloat = 20          // --win-radius
    static let panel    = Color(hex: 0x0d0e12)     // --panel
    static let panel2   = Color(hex: 0x101116)     // --panel-2
    static let panelRow = Color.white.opacity(0.022) // --panel-row

    // MARK: - Signal colors
    static let sigStrong = Color(hex: 0x32D74B)        // --sig-strong
    static let sigGood   = Color(hex: 0x9EE34F)        // --sig-good
    static let sigMid    = Color(hex: 0xFFD60A)        // --sig-mid
    static let sigWeak   = Color(hex: 0xFF9F0A)        // --sig-weak
    static let sigPoor   = Color(hex: 0xFF453A)        // --sig-poor
    static let sigNone   = Color.white.opacity(0.18)   // --sig-none

    // MARK: - Encryption colors
    static let encOpen = Color(hex: 0x8E8E93)   // --enc-open
    static let encWep  = Color(hex: 0xFF9F0A)   // --enc-wep
    static let encWpa  = Color(hex: 0x0A84FF)   // --enc-wpa
    static let encWpa3 = Color(hex: 0x5E5CE6)   // --enc-wpa3

    // MARK: - Scan capsule
    static let scanGreenBG = Color(hex: 0x32D74B, alpha: 0.24)
    static let scanRedBG   = Color(hex: 0xFF453A, alpha: 0.26)
    static let scanGreenFG = Color(hex: 0xD8FFE0)
    static let scanRedFG   = Color(hex: 0xFFD9D6)

    // MARK: - Fonts (--sans / --mono)
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Signal → color (mirrors components.jsx sigColor)
    /// `value` is a 0–100 signal percentage.
    static func signalColor(_ value: Int) -> Color {
        if value >= 70 { return sigStrong }
        if value >= 50 { return sigGood }
        if value >= 35 { return sigMid }
        if value >= 18 { return sigWeak }
        if value > 0   { return sigPoor }
        return sigNone
    }

    /// dBm estimate, mirrors components.jsx dbm(): -95 + (v/100)*70
    static func dbm(_ value: Int) -> Int {
        Int((-95.0 + (Double(value) / 100.0) * 70.0).rounded())
    }
}

// MARK: - Encryption display

enum GGEncDisplay {
    static func label(_ enc: String) -> String {
        switch enc.lowercased() {
        case "open": return "Open"
        case "wep":  return "WEP"
        case "wpa":  return "WPA"
        case "wpa2": return "WPA2"
        case "wpa3": return "WPA3"
        default:     return enc.uppercased()
        }
    }

    /// CSS .pill class mapping: open / wep / wpa3 / (everything else) wpa
    static func color(_ enc: String) -> Color {
        switch enc.lowercased() {
        case "open": return GGTheme.encOpen
        case "wep":  return GGTheme.encWep
        case "wpa3": return GGTheme.encWpa3
        default:     return GGTheme.encWpa
        }
    }

    static func isOpen(_ enc: String) -> Bool { enc.lowercased() == "open" }
}

// MARK: - Color hex helper

extension Color {
    /// Build a Color from a 24-bit RGB hex literal, e.g. `Color(hex: 0x0A84FF)`.
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Glass material helper (Tahoe glass)

@available(macOS 12.0, *)
struct GGGlass: ViewModifier {
    var tint: Color
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(tint)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(GGTheme.hair),
                alignment: .top
            )
    }
}

@available(macOS 12.0, *)
extension View {
    /// Apply the toolbar/status-bar glass look.
    func ggGlass(tint: Color = Color.white.opacity(0.04)) -> some View {
        modifier(GGGlass(tint: tint))
    }
}

#if canImport(AppKit)
/// NSVisualEffectView wrapper for a richer "Tahoe glass" when `.ultraThinMaterial`
/// is not enough (used behind the toolbar / status bar).
@available(macOS 12.0, *)
struct GGVisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .headerView
    var blending: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}
#endif
