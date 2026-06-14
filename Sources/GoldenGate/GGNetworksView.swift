//
//  GGNetworksView.swift
//  KisMAC — Golden Gate UI (Stage 2)
//
//  The Networks table: a scrolling list of networks mirroring NetworksView in
//  components.jsx (.net-table / .net-row / .ssid-cell / .sig-cell styling from
//  styles.css). Sticky header, zebra striping, hover, accent selection with an
//  inset accent bar, and a "fresh" green flash when a row updates during a scan.
//  Reuses GGSignalBars / GGEncPill / GGTheme color mappers / GGAppState.
//

import SwiftUI

@available(macOS 12.0, *)
struct GGNetworksView: View {
    @ObservedObject var state: GGAppState

    // Column layout (matches the jsx cols + the right-aligned num columns).
    private let now = Date()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(GGTheme.hair2)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(state.filteredNetworks.enumerated()), id: \.element.id) { idx, net in
                        GGNetworkRow(net: net,
                                     index: idx,
                                     selected: net.id == state.selectedID,
                                     scanning: state.isScanning,
                                     now: now)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                state.selectedID = net.id
                                state.view = .details
                            }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GGTheme.panel)
    }

    // MARK: sticky header (.net-table thead th)

    private var header: some View {
        HStack(spacing: 0) {
            cell("#", .num, width: 40)
            cell("Ch", .num, width: 44)
            cell("SSID", .lead, minWidth: 180)
            cell("BSSID", .lead, width: 160)
            cell("Enc", .lead, width: 78)
            cell("Type", .lead, width: 86)
            cell("Signal", .lead, width: 120)
            cell("Packets", .num, width: 92)
            cell("Data", .num, width: 92)
            cell("Last Seen", .lead, width: 90)
            cell("Ch/Re", .lead, width: 52)
        }
        .padding(.horizontal, GGNetCols.hPad)
        .frame(height: 34)
        .background(
            LinearGradient(colors: [Color(hex: 0x16171d), Color(hex: 0x121319)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private enum Align { case lead, num }

    @ViewBuilder
    private func cell(_ title: String, _ align: Align, width: CGFloat? = nil, minWidth: CGFloat? = nil) -> some View {
        let label = Text(title)
            .font(GGTheme.sans(11, weight: .semibold))
            .foregroundColor(GGTheme.ink2)
        let a: Alignment = align == .num ? .trailing : .leading
        if let minWidth = minWidth {
            label.frame(minWidth: minWidth, maxWidth: .infinity, alignment: a)
                .padding(.horizontal, GGNetCols.cellPad)
        } else {
            label.frame(width: width, alignment: a)
                .padding(.horizontal, GGNetCols.cellPad)
        }
    }
}

// MARK: - Column metrics shared by header + rows

enum GGNetCols {
    static let hPad: CGFloat = 0
    static let cellPad: CGFloat = 10
    static let w0: CGFloat = 40       // #
    static let wCh: CGFloat = 44      // Ch
    static let wSSID: CGFloat = 180   // min
    static let wBSSID: CGFloat = 160
    static let wEnc: CGFloat = 78
    static let wType: CGFloat = 86
    static let wSig: CGFloat = 120
    static let wPkt: CGFloat = 92
    static let wData: CGFloat = 92
    static let wLast: CGFloat = 90
    static let wLive: CGFloat = 52
}

// MARK: - A single network row (.net-row)

@available(macOS 12.0, *)
private struct GGNetworkRow: View {
    var net: GGNetwork
    var index: Int
    var selected: Bool
    var scanning: Bool
    var now: Date

    @State private var hovering = false
    @State private var fresh = false

    private var sig: Int { scanning ? net.liveSignal : net.signal }

    var body: some View {
        HStack(spacing: 0) {
            // #
            text("\(net.id)", GGTheme.mono(12), GGTheme.ink3, .trailing)
                .frame(width: GGNetCols.w0).padding(.horizontal, GGNetCols.cellPad)
            // Ch
            text("\(net.ch)", GGTheme.sans(13), GGTheme.ink, .trailing)
                .frame(width: GGNetCols.wCh).padding(.horizontal, GGNetCols.cellPad)
            // SSID
            ssidCell
                .frame(minWidth: GGNetCols.wSSID, maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, GGNetCols.cellPad)
            // BSSID
            text(net.bssid, GGTheme.mono(12), GGTheme.ink3, .leading)
                .frame(width: GGNetCols.wBSSID, alignment: .leading).padding(.horizontal, GGNetCols.cellPad)
            // Enc
            HStack { GGEncPill(enc: net.enc); Spacer(minLength: 0) }
                .frame(width: GGNetCols.wEnc, alignment: .leading).padding(.horizontal, GGNetCols.cellPad)
            // Type
            text(net.type, GGTheme.sans(12), GGTheme.ink2, .leading)
                .frame(width: GGNetCols.wType, alignment: .leading).padding(.horizontal, GGNetCols.cellPad)
            // Signal
            HStack(spacing: 9) {
                GGSignalBars(value: sig)
                Text("\(GGTheme.dbm(sig))")
                    .font(GGTheme.sans(12).monospacedDigit())
                    .foregroundColor(GGTheme.ink2)
                    .frame(minWidth: 26, alignment: .leading)
                Spacer(minLength: 0)
            }
            .frame(width: GGNetCols.wSig, alignment: .leading).padding(.horizontal, GGNetCols.cellPad)
            // Packets
            text(GGFormat.num(net.packets), GGTheme.sans(13).monospacedDigit(), GGTheme.ink, .trailing)
                .frame(width: GGNetCols.wPkt, alignment: .trailing).padding(.horizontal, GGNetCols.cellPad)
            // Data (bytes)
            text(GGFormat.bytes(net.bytes), GGTheme.sans(13).monospacedDigit(), GGTheme.ink3, .trailing)
                .frame(width: GGNetCols.wData, alignment: .trailing).padding(.horizontal, GGNetCols.cellPad)
            // Last Seen
            text(GGFormat.relTime(net.lastSeen, now: now), GGTheme.sans(13), GGTheme.ink3, .leading)
                .frame(width: GGNetCols.wLast, alignment: .leading).padding(.horizontal, GGNetCols.cellPad)
            // Ch/Re live dot
            HStack { liveDot; Spacer(minLength: 0) }
                .frame(width: GGNetCols.wLive, alignment: .leading).padding(.horizontal, GGNetCols.cellPad)
        }
        .frame(minHeight: 36)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(GGTheme.accent).frame(width: 2)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1)
        }
        .onHover { hovering = $0 }
        // "fresh" flash: when this row gets a live update during scanning.
        .onChange(of: net.lastSeen) { _ in
            guard scanning else { return }
            fresh = true
            withAnimation(.easeOut(duration: 0.5)) { fresh = false }
        }
    }

    @ViewBuilder private var ssidCell: some View {
        let hidden = net.hidden || net.ssid.isEmpty
        HStack(spacing: 9) {
            Image(systemName: GGEncDisplay.isOpen(net.enc) ? "lock.open" : "lock.fill")
                .font(.system(size: 11))
                .foregroundColor(hidden ? GGTheme.ink3 : GGTheme.ink2)
                .frame(width: 13)
            Text(hidden ? "‹hidden›" : net.ssid)
                .font(GGTheme.sans(13, weight: hidden ? .medium : .semibold))
                .italic(hidden)
                .foregroundColor(hidden ? GGTheme.ink3 : GGTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var liveDot: some View {
        Circle()
            .fill(net.lastSeenLive ? GGTheme.sigStrong : GGTheme.sigNone)
            .frame(width: 9, height: 9)
            .shadow(color: net.lastSeenLive ? GGTheme.sigStrong : .clear, radius: 4)
    }

    private var rowBackground: some View {
        ZStack {
            // zebra striping (.net-row:nth-child(even))
            if index % 2 == 1 { GGTheme.panelRow }
            if selected { GGTheme.accentSoft }
            else if hovering { Color.white.opacity(0.05) }
            // fresh-row green flash (.net-row.fresh rowIn animation)
            if fresh { Color(hex: 0x32D74B, alpha: 0.18) }
        }
    }

    private func text(_ s: String, _ font: Font, _ color: Color, _ align: Alignment) -> some View {
        Text(s).font(font).foregroundColor(color).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: align)
    }
}

private extension Text {
    @ViewBuilder func italic(_ on: Bool) -> Text { on ? self.italic() : self }
}
