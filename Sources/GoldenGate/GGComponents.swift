//
//  GGComponents.swift
//  KisMAC — Golden Gate UI (Stage 1)
//
//  Shared visual atoms ported from components.jsx: traffic-light dots,
//  signal bars, encryption pills, the scan capsule, and the segmented
//  view switcher. The full Networks/Details/Graph views land in Stage 2/3.
//

import SwiftUI

// MARK: - Traffic lights

@available(macOS 12.0, *)
struct GGTrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            dot(Color(hex: 0xEC6A5E))
            dot(Color(hex: 0xF5BF4F))
            dot(Color(hex: 0x61C554))
        }
    }
    private func dot(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
    }
}

// MARK: - Signal bars (mirrors components.jsx Bars)

@available(macOS 12.0, *)
struct GGSignalBars: View {
    var value: Int
    private let heights: [CGFloat] = [6, 9, 12, 15, 18]

    var body: some View {
        let lit = value <= 0 ? 0 : min(5, Int(ceil(Double(value) / 20.0)))
        let col = GGTheme.signalColor(value)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < lit ? col : GGTheme.sigNone)
                    .frame(width: 3.5, height: heights[i])
            }
        }
        .frame(height: 18, alignment: .bottom)
    }
}

// MARK: - Encryption pill (mirrors components.jsx EncPill)

@available(macOS 12.0, *)
struct GGEncPill: View {
    var enc: String
    var body: some View {
        let c = GGEncDisplay.color(enc)
        HStack(spacing: 4) {
            Image(systemName: GGEncDisplay.isOpen(enc) ? "lock.open" : "lock.fill")
                .font(.system(size: 9))
            Text(GGEncDisplay.label(enc))
                .font(GGTheme.sans(11, weight: .semibold))
        }
        .foregroundColor(c)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(
            Capsule().fill(c.opacity(0.15))
                .overlay(Capsule().stroke(c.opacity(0.38), lineWidth: 1))
        )
    }
}

// MARK: - Segmented view switcher (leading; does NOT shift)

@available(macOS 12.0, *)
struct GGSegmentedSwitcher: View {
    @Binding var selection: GGView
    var body: some View {
        HStack(spacing: 2) {
            ForEach(GGView.allCases) { v in
                Button {
                    selection = v
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: v.symbol).font(.system(size: 13))
                        Text(v.label).font(GGTheme.sans(12.5, weight: .medium))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .foregroundColor(selection == v ? .white : GGTheme.ink2)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selection == v ? Color.white.opacity(0.13) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(Color.black.opacity(0.24))
                .overlay(RoundedRectangle(cornerRadius: 11)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
        // Fixed width so it never shifts as the trailing contextual controls change.
        .fixedSize()
    }
}

// MARK: - Scan / Stop capsule (green → red, pulsing dot)

@available(macOS 12.0, *)
struct GGScanCapsule: View {
    @Binding var scanning: Bool
    @State private var pulse = false

    var body: some View {
        Button {
            scanning.toggle()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(scanning ? GGTheme.sigPoor : GGTheme.sigStrong)
                    .frame(width: 7, height: 7)
                    .shadow(color: scanning ? GGTheme.sigPoor : GGTheme.sigStrong, radius: 4)
                    .opacity(scanning && pulse ? 0.25 : 1.0)
                    .animation(scanning ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                                        : .default, value: pulse)
                Image(systemName: scanning ? "stop.fill" : "play.fill")
                    .font(.system(size: 11))
                Text(scanning ? "Stop" : "Scan")
                    .font(GGTheme.sans(12.5, weight: .semibold))
            }
            .foregroundColor(scanning ? GGTheme.scanRedFG : GGTheme.scanGreenFG)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(scanning ? GGTheme.scanRedBG : GGTheme.scanGreenBG)
            )
        }
        .buttonStyle(.plain)
        .onAppear { pulse = true }
    }
}

// MARK: - Toolbar icon button (e.g. Preferences gear)

@available(macOS 12.0, *)
struct GGIconButton: View {
    var systemName: String
    var active: Bool = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15))
                .foregroundColor(active ? Color(hex: 0x7CBCFF) : GGTheme.ink2)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(active ? GGTheme.accentSoft : Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 9)
                            .stroke(active ? GGTheme.accentLine : Color.white.opacity(0.07),
                                    lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stub view scaffold

@available(macOS 12.0, *)
struct GGStubView: View {
    var title: String
    var stage: String
    var symbol: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 46, weight: .regular))
                .foregroundColor(GGTheme.accent.opacity(0.8))
            Text(title)
                .font(GGTheme.sans(22, weight: .bold))
                .foregroundColor(GGTheme.ink)
            Text(stage)
                .font(GGTheme.sans(13))
                .foregroundColor(GGTheme.ink2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GGTheme.panel)
    }
}
