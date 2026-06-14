//
//  GGGraphView.swift
//  KisMAC — Golden Gate UI (Stage 3)
//
//  The live rolling multi-series chart, mirroring GraphView in components.jsx
//  (.graph-wrap / .graph-legend / .leg-item / .leg-swatch / .graph-canvas /
//  .g-grid / .g-baseline / .g-axis-label from styles.css). Renders the top-5
//  networks (by signal) as one consistently-colored line each over a grid with
//  monospace axis labels, plus a wrapping legend above. Maintains a per-network
//  rolling sample buffer that advances on a scanning tick and trims to the
//  selected window's sample count; static when idle. Unit toggles Bytes/Packets.
//  Reuses GGTheme tokens + GGAppState (graphUnit / graphWindow / isScanning).
//

import SwiftUI

// MARK: - Graph palette (mirrors components.jsx GRAPH_COLORS)

@available(macOS 12.0, *)
enum GGGraphPalette {
    static let colors: [Color] = [
        Color(hex: 0x0A84FF),
        Color(hex: 0x32D74B),
        Color(hex: 0xFF9F0A),
        Color(hex: 0xBF5AF2),
        Color(hex: 0xFF375F),
        Color(hex: 0x5AC8FA),
    ]
    static func color(_ i: Int) -> Color { colors[i % colors.count] }
}

// MARK: - Graph view

@available(macOS 12.0, *)
struct GGGraphView: View {
    @ObservedObject var state: GGAppState

    // Tick cadence matches the scanning engine in GGModel (1.1s per advance).
    private static let tickInterval: TimeInterval = 1.1

    // Per-network rolling sample buffers, keyed by network id. Each value is a
    // 0–100 series (signal proxy for Bytes/Packets — the design scales visually
    // only, real per-second values are not tracked in the seed model).
    @State private var hist: [Int: [Double]] = [:]
    @State private var timer: Timer?

    /// Window label → number of samples retained.
    private func sampleCount(for window: String) -> Int {
        let seconds: Double
        switch window {
        case "15 sec": seconds = 15
        case "30 sec": seconds = 30
        case "60 sec": seconds = 60
        case "5 min":  seconds = 300
        default:       seconds = 15
        }
        return max(8, Int((seconds / Self.tickInterval).rounded()))
    }

    /// Top-5 networks by baseline signal (mirrors the jsx `series`).
    private var series: [GGNetwork] {
        state.networks.sorted { $0.signal > $1.signal }.prefix(5).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            legend
            canvas
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GGTheme.panel)
        .onAppear { seedIfNeeded(); restartTimer() }
        .onDisappear { timer?.invalidate(); timer = nil }
        .onChange(of: state.isScanning) { _ in restartTimer() }
        .onChange(of: state.graphWindow) { _ in trimAll() }
    }

    // MARK: legend (.graph-legend / .leg-item / .leg-swatch)

    private var legend: some View {
        GGFlowLayout(hSpacing: 18, vSpacing: 8) {
            ForEach(Array(series.enumerated()), id: \.element.id) { i, net in
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(GGGraphPalette.color(i))
                        .frame(width: 11, height: 11)
                    Text(net.displaySSID)
                        .font(GGTheme.sans(12))
                        .foregroundColor(GGTheme.ink2)
                        .lineLimit(1)
                }
            }
        }
        .padding(.bottom, 14)
    }

    // MARK: canvas (.graph-canvas svg)

    private var canvas: some View {
        let count = sampleCount(for: state.graphWindow)
        let unitMul = state.graphUnit == "Bytes" ? 1.4 : 1.0   // visual label scaling only
        let seriesSnapshot = series

        return Canvas { ctx, size in
            let padL: CGFloat = 46, padB: CGFloat = 26, padT: CGFloat = 12, padR: CGFloat = 12
            let iw = size.width - padL - padR
            let ih = size.height - padT - padB
            guard iw > 0, ih > 0 else { return }

            func yFor(_ v: Double) -> CGFloat { padT + ih - CGFloat(v / 100.0) * ih }
            func xFor(_ i: Int, _ n: Int) -> CGFloat {
                guard n > 1 else { return padL }
                return padL + CGFloat(i) / CGFloat(n - 1) * iw
            }

            // grid + axis labels (.g-grid / .g-axis-label)
            for f in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let yy = padT + ih - CGFloat(f) * ih
                var line = Path()
                line.move(to: CGPoint(x: padL, y: yy))
                line.addLine(to: CGPoint(x: size.width - padR, y: yy))
                ctx.stroke(line, with: .color(Color.white.opacity(0.06)), lineWidth: 1)

                let label = Text("\(Int((f * 100 * unitMul).rounded()))")
                    .font(GGTheme.mono(10)).foregroundColor(GGTheme.ink3)
                ctx.draw(label, at: CGPoint(x: padL - 8, y: yy), anchor: .trailing)
            }

            // baseline (.g-baseline)
            var base = Path()
            base.move(to: CGPoint(x: padL, y: padT + ih))
            base.addLine(to: CGPoint(x: size.width - padR, y: padT + ih))
            ctx.stroke(base, with: .color(Color.white.opacity(0.16)), lineWidth: 1)

            // x-axis time labels
            let span = Double(count) * Self.tickInterval
            ctx.draw(Text("-\(Int(span.rounded()))s").font(GGTheme.mono(10)).foregroundColor(GGTheme.ink3),
                     at: CGPoint(x: padL, y: size.height - 6), anchor: .bottomLeading)
            ctx.draw(Text("now").font(GGTheme.mono(10)).foregroundColor(GGTheme.ink3),
                     at: CGPoint(x: size.width - padR, y: size.height - 6), anchor: .bottomTrailing)

            // one filled area + line per network
            for (si, net) in seriesSnapshot.enumerated() {
                let samples = hist[net.id] ?? []
                guard samples.count >= 2 else { continue }
                let col = GGGraphPalette.color(si)
                let n = samples.count

                var line = Path()
                for (i, v) in samples.enumerated() {
                    let pt = CGPoint(x: xFor(i, n), y: yFor(v))
                    if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
                }

                // area fill under the line (opacity 0.08)
                var area = line
                area.addLine(to: CGPoint(x: xFor(n - 1, n), y: padT + ih))
                area.addLine(to: CGPoint(x: padL, y: padT + ih))
                area.closeSubpath()
                ctx.fill(area, with: .color(col.opacity(0.08)))

                // glow + stroke
                ctx.drawLayer { layer in
                    layer.addFilter(.shadow(color: col.opacity(0.4), radius: 5))
                    layer.stroke(line, with: .color(col),
                                 style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                }

                // leading-edge marker on the latest sample
                let lastPt = CGPoint(x: xFor(n - 1, n), y: yFor(samples[n - 1]))
                ctx.fill(Path(ellipseIn: CGRect(x: lastPt.x - 3.5, y: lastPt.y - 3.5, width: 7, height: 7)),
                         with: .color(col))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: rolling buffer

    /// Seed each series with a gently-varying initial curve (mirrors the jsx
    /// initial `hist`, derived from avgSignal) so the chart isn't empty at rest.
    private func seedIfNeeded() {
        let count = sampleCount(for: state.graphWindow)
        var next: [Int: [Double]] = [:]
        for net in series {
            if let existing = hist[net.id], !existing.isEmpty {
                next[net.id] = existing
            } else {
                next[net.id] = (0..<count).map { i in
                    let base = Double(net.avgSignal)
                    let wobble = sin(Double(i) / 4 + Double(net.id)) * 10
                    let jitter = (Double.random(in: 0...1) - 0.5) * 8
                    return max(0, min(100, base + wobble + jitter))
                }
            }
        }
        hist = next
        trimAll()
    }

    private func restartTimer() {
        timer?.invalidate(); timer = nil
        guard state.isScanning else { return }
        let t = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { _ in
            advance()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Append one new sample per network (random-walk blended toward the live
    /// signal), then trim to the window. Mirrors the jsx setInterval updater.
    private func advance() {
        let count = sampleCount(for: state.graphWindow)
        var next = hist
        for net in series {
            var buf = next[net.id] ?? []
            let prev = buf.last ?? Double(net.signal)
            var v = prev + (Double.random(in: 0...1) - 0.5) * 14
            v = max(2, min(100, v * 0.7 + Double(net.signal) * 0.3))
            buf.append(v)
            if buf.count > count { buf.removeFirst(buf.count - count) }
            next[net.id] = buf
        }
        hist = next
    }

    private func trimAll() {
        let count = sampleCount(for: state.graphWindow)
        var next = hist
        for (k, buf) in next where buf.count > count {
            next[k] = Array(buf.suffix(count))
        }
        hist = next
    }
}

// MARK: - Simple wrapping flow layout for the legend (.graph-legend flex-wrap)

@available(macOS 13.0, *)
struct GGFlowLayout: Layout {
    var hSpacing: CGFloat = 8
    var vSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, totalW: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW {
                totalW = max(totalW, x - hSpacing)
                y += rowH + vSpacing; x = 0; rowH = 0
            }
            x += sz.width + hSpacing
            rowH = max(rowH, sz.height)
        }
        totalW = max(totalW, x - hSpacing)
        return CGSize(width: min(totalW, maxW), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxW = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW {
                y += rowH + vSpacing; x = 0; rowH = 0
            }
            sv.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading,
                     proposal: ProposedViewSize(sz))
            x += sz.width + hSpacing
            rowH = max(rowH, sz.height)
        }
    }
}
