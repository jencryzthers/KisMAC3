//
//  GGMapView.swift
//  KisMAC — Golden Gate UI (Stage 3)
//
//  The radar map, mirroring MapView in prefs.jsx (.map / .map-grid / .landmass /
//  .map-marker / .mk-dot / .mk-ring / .gps-dot / .radar / .radar-rings /
//  .map-hud / .map-zoom / .zbtn / .map-legend from styles.css). A ZStack with a
//  dark radial background, a faint grid overlay, blurred landmass blobs, AP
//  markers projected from lat/lng (signal-colored, pulsing ring while scanning),
//  a glowing GPS dot, a rotating conic radar sweep + concentric rings (gated on
//  scanning), a glass HUD bottom-left (mono position/elevation/time), a glass
//  zoom/pan cluster bottom-right, and a top-left legend. Tapping a marker selects
//  that network and routes to Details (same mechanism as GGNetworksView).
//  Reuses GGTheme tokens + signalColor + GGAppState.
//

import SwiftUI

@available(macOS 12.0, *)
struct GGMapView: View {
    @ObservedObject var state: GGAppState

    // px per degree — tight cluster around the GPS center (mirrors jsx SCALE).
    private static let scale: Double = 16000
    private static let panStep: CGFloat = 60

    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var clock: Date = GGSeed.now
    @State private var sweepAngle: Double = 0
    @State private var clockTimer: Timer?

    private func project(lat: Double, lng: Double) -> CGPoint {
        CGPoint(x: (lng - state.gps.lng) * Self.scale,
                y: -(lat - state.gps.lat) * Self.scale)
    }

    var body: some View {
        ZStack {
            background
            GeometryReader { geo in
                ZStack {
                    grid
                    landmasses(in: geo.size)

                    // radar + markers cluster, centered at 50%/47% then panned/zoomed
                    clusterLayer
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.47)
                        .offset(pan)
                        .scaleEffect(zoom, anchor: .center)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: zoom)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: pan)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            legend
            hud
            zoomCluster
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear { startSweep(); restartClock() }
        .onDisappear { clockTimer?.invalidate(); clockTimer = nil }
        .onChange(of: state.isScanning) { scanning in
            restartClock()
            if scanning { startSweep() }
        }
    }

    // MARK: background (.map radial gradient)

    private var background: some View {
        RadialGradient(
            colors: [Color(hex: 0x0A1622), Color(hex: 0x05080D), Color(hex: 0x03050A)],
            center: UnitPoint(x: 0.5, y: 0.3),
            startRadius: 0, endRadius: 900
        )
        .ignoresSafeArea()
    }

    // MARK: grid overlay (.map-grid — 60px lines, blue-ish, opacity 0.5)

    private var grid: some View {
        Canvas { ctx, size in
            let step: CGFloat = 60
            let stroke = GraphicsContext.Shading.color(Color(hex: 0x50B4FF, alpha: 0.07))
            var x: CGFloat = 0
            while x <= size.width {
                var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: stroke, lineWidth: 1)
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: stroke, lineWidth: 1)
                y += step
            }
        }
        .opacity(0.5)
        .allowsHitTesting(false)
    }

    // MARK: landmass blobs (.landmass — blurred green-tinted organic shapes)

    @ViewBuilder
    private func landmasses(in size: CGSize) -> some View {
        let blob = RoundedRectangle(cornerRadius: 90, style: .continuous)
        ZStack(alignment: .topLeading) {
            blob.fill(Color(hex: 0x32785A, alpha: 0.16))
                .overlay(blob.stroke(Color(hex: 0x50C896, alpha: 0.16), lineWidth: 1))
                .frame(width: 260, height: 200).rotationEffect(.degrees(-8))
                .position(x: size.width * 0.08 + 130, y: size.height * 0.18 + 100)
            blob.fill(Color(hex: 0x32785A, alpha: 0.16))
                .overlay(blob.stroke(Color(hex: 0x50C896, alpha: 0.16), lineWidth: 1))
                .frame(width: 340, height: 240).rotationEffect(.degrees(6))
                .position(x: size.width * 0.88 - 170, y: size.height * 0.30 + 120)
            blob.fill(Color(hex: 0x32785A, alpha: 0.16))
                .overlay(blob.stroke(Color(hex: 0x50C896, alpha: 0.16), lineWidth: 1))
                .frame(width: 420, height: 180).rotationEffect(.degrees(-3))
                .position(x: size.width * 0.30 + 210, y: size.height * 0.94 - 90)
        }
        .blur(radius: 0.5)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    // MARK: radar + markers cluster

    private var clusterLayer: some View {
        ZStack {
            radarRings
            radarSweep
            ForEach(state.networks) { net in
                marker(net)
            }
            gpsDot
        }
    }

    // concentric faint rings (.radar-rings span — 120/240/360)
    private var radarRings: some View {
        ZStack {
            ForEach([120.0, 240.0, 360.0], id: \.self) { d in
                Circle()
                    .stroke(Color(hex: 0x0A84FF, alpha: 0.18), lineWidth: 1)
                    .frame(width: d, height: d)
            }
        }
    }

    // rotating conic sweep (.radar::before — 520px conic gradient, 4s linear)
    private var radarSweep: some View {
        Circle()
            .fill(AngularGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(hex: 0x0A84FF, alpha: 0.34), location: 0.0),
                    .init(color: Color(hex: 0x0A84FF, alpha: 0.0), location: 0.38),
                    .init(color: Color(hex: 0x0A84FF, alpha: 0.0), location: 1.0),
                ]),
                center: .center, angle: .degrees(sweepAngle)))
            .frame(width: 520, height: 520)
            .opacity(state.isScanning ? 1 : 0.0)
            .allowsHitTesting(false)
    }

    // signal-colored AP marker + pulsing ring while scanning (.mk-dot / .mk-ring)
    @ViewBuilder
    private func marker(_ net: GGNetwork) -> some View {
        let p = project(lat: net.lat, lng: net.lng)
        let sig = state.isScanning ? net.liveSignal : net.signal
        let col = GGTheme.signalColor(sig)
        let r = 6 + CGFloat(Double(sig) / 100.0) * 6
        let selected = net.id == state.selectedID

        ZStack {
            if state.isScanning {
                GGMarkerRing(color: col)
            }
            Circle()
                .fill(col)
                .frame(width: r, height: r)
                .shadow(color: col, radius: selected ? 8 : 4)
                .overlay(
                    Circle().stroke(Color.white, lineWidth: selected ? 2 : 0)
                        .padding(-2)
                )
        }
        .frame(width: 26, height: 26)            // hit area roughly matches expanded ring
        .contentShape(Rectangle())
        .position(x: p.x, y: p.y)
        .onTapGesture {
            state.selectedID = net.id
            state.view = .details
        }
        .help(net.displaySSID)
    }

    // glowing GPS dot at center (.gps-dot)
    private var gpsDot: some View {
        Circle()
            .fill(GGTheme.accent)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 2).padding(2))
            .shadow(color: GGTheme.accentGlow, radius: 9)
            .position(x: 0, y: 0)
            .allowsHitTesting(false)
    }

    // MARK: top-left legend (.map-legend)

    private var legend: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 13)).foregroundColor(GGTheme.ink2)
            Text("\(state.networks.count) access points · GPS lock")
                .font(GGTheme.sans(12)).foregroundColor(GGTheme.ink2)
        }
        .padding(.horizontal, 13).padding(.vertical, 8)
        .background(glassPanel(corner: 10, tint: Color(hex: 0x12141A, alpha: 0.5)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
    }

    // MARK: bottom-left HUD (.map-hud — mono, glass)

    private var hud: some View {
        VStack(alignment: .leading, spacing: 3) {
            hudRow("Position:", state.gps.label, color: Color(hex: 0x6CF0C4))
            hudRow("Elevation:", "No Elevation Data", color: Color(hex: 0x6CB6FF))
            hudRow("Time:", clockString, color: Color(hex: 0x6CF0C4))
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
        .background(glassPanel(corner: 12, tint: Color(hex: 0x12141A, alpha: 0.55)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(18)
    }

    private func hudRow(_ k: String, _ v: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(k).font(GGTheme.mono(12)).foregroundColor(GGTheme.ink3)
            Text(v).font(GGTheme.mono(12)).foregroundColor(color)
        }
    }

    private var clockString: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: clock)
        func p(_ x: Int?) -> String { String(format: "%02d", x ?? 0) }
        return "\(c.year ?? 0)-\(p(c.month))-\(p(c.day)) \(p(c.hour)):\(p(c.minute)):\(p(c.second)) +0000"
    }

    // MARK: bottom-right zoom/pan cluster (.map-zoom / .zbtn — 3-col glass grid)

    private var zoomCluster: some View {
        let cols = [GridItem(.fixed(38), spacing: 7),
                    GridItem(.fixed(38), spacing: 7),
                    GridItem(.fixed(38), spacing: 7)]
        return LazyVGrid(columns: cols, spacing: 7) {
            zbtn("plus.magnifyingglass") { zoom = min(3, zoom + 0.3) }
            zbtn("chevron.up")           { pan.height += Self.panStep }
            zbtn("minus.magnifyingglass"){ zoom = max(0.6, zoom - 0.3) }
            zbtn("chevron.left")         { pan.width += Self.panStep }
            zbtn("chevron.down")         { pan.height -= Self.panStep }
            zbtn("chevron.right")        { pan.width -= Self.panStep }
        }
        .frame(width: 38 * 3 + 7 * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(18)
    }

    private func zbtn(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(GGTheme.ink)
                .frame(width: 38, height: 38)
                .background(glassPanel(corner: 11, tint: Color(hex: 0x1C1E26, alpha: 0.6)))
        }
        .buttonStyle(.plain)
    }

    // MARK: shared glass panel

    private func glassPanel(corner: CGFloat, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(tint)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner))
            .overlay(RoundedRectangle(cornerRadius: corner).stroke(GGTheme.hair2, lineWidth: 1))
    }

    // MARK: animation drivers

    private func startSweep() {
        sweepAngle = 0
        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
            sweepAngle = 360
        }
    }

    private func restartClock() {
        clockTimer?.invalidate(); clockTimer = nil
        guard state.isScanning else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            clock = clock.addingTimeInterval(1)
        }
        RunLoop.main.add(t, forMode: .common)
        clockTimer = t
    }
}

// MARK: - Pulsing expanding ring (.mk-ring — box-shadow ring animation, 2.4s)

@available(macOS 12.0, *)
private struct GGMarkerRing: View {
    var color: Color
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .frame(width: 11, height: 11)
            .scaleEffect(animate ? 5.5 : 1.0)
            .opacity(animate ? 0.0 : 0.7)
            .onAppear {
                animate = false
                withAnimation(.easeOut(duration: 2.4).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}
