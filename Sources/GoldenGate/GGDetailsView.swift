//
//  GGDetailsView.swift
//  KisMAC — Golden Gate UI (Stage 2)
//
//  The Details split view, mirroring DetailsView + PropRow in components.jsx
//  (.details / .insp* / .prop-* / .comment-box / .clients / .cl-table /
//  .empty-state styling from styles.css). Left: inspector (~46%, min 360pt)
//  with header, scrollable property groups, and a comment textarea bound to the
//  selected network. Right: clients panel (table) or an empty-state.
//  Reuses GGSignalBars / GGTheme / GGFormat / GGAppState.
//

import SwiftUI

@available(macOS 12.0, *)
struct GGDetailsView: View {
    @ObservedObject var state: GGAppState
    private let now = Date()

    var body: some View {
        Group {
            if let net = state.selectedNetwork {
                // Split: inspector ~46% (min 360pt), clients fill the rest.
                GeometryReader { geo in
                    let inspW = max(360, min(geo.size.width * 0.46, geo.size.width - 200))
                    HStack(spacing: 0) {
                        inspector(net).frame(width: inspW)
                        clientsPanel(net)
                    }
                }
            } else {
                emptyState(symbol: "magnifyingglass.circle",
                           text: "Select a network to inspect its details.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GGTheme.panel)
    }

    // MARK: - Inspector (.insp)

    @ViewBuilder
    private func inspector(_ net: GGNetwork) -> some View {
        VStack(spacing: 0) {
            inspHead(net)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let sig = state.isScanning ? net.liveSignal : net.signal
                    propGroup("Identity") {
                        propRow("Vendor", net.vendor)
                        propRow("Type", net.type)
                        propRow("Encryption", GGEncDisplay.isOpen(net.enc) ? "disabled" : GGEncDisplay.label(net.enc))
                        propRow("Band", net.band)
                        propRow("First Seen", GGDetailsFormat.full(net.firstSeen), mono: true)
                        propRow("Last Seen", GGDetailsFormat.full(net.lastSeen), mono: true)
                    }
                    propGroup("Signal") {
                        propRow("Channel", "\(net.ch)")
                        propRow("Main Channel", "\(net.ch)")
                        propRow("Signal", "\(GGTheme.dbm(sig)) dBm")
                        propRow("Max Signal", "\(GGTheme.dbm(net.maxSignal)) dBm")
                        propRow("Avg Signal", "\(GGTheme.dbm(net.avgSignal)) dBm")
                    }
                    propGroup("Packets") {
                        propRow("Packets", GGFormat.num(net.packets))
                        propRow("Data Packets", GGFormat.num(net.dataPackets))
                        propRow("Management Packets", GGFormat.num(net.mgmtPackets))
                        propRow("Control Packets", GGFormat.num(net.ctrlPackets))
                        propRow("Unique IVs", GGFormat.num(net.uniqueIVs))
                        propRow("Inj. Packets", GGFormat.num(net.injPackets))
                        propRow("Bytes", GGFormat.bytes(net.bytes))
                    }
                }
            }
            commentBox(net)
        }
        .background(GGTheme.panel2)
        .overlay(alignment: .trailing) {
            Rectangle().fill(GGTheme.hair2).frame(width: 1)
        }
    }

    private func inspHead(_ net: GGNetwork) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x0A84FF, alpha: 0.22), Color(hex: 0x0A84FF, alpha: 0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 11)
                        .stroke(Color(hex: 0x0A84FF, alpha: 0.3), lineWidth: 1))
                Image(systemName: GGEncDisplay.isOpen(net.enc) ? "lock.open" : "lock.fill")
                    .font(.system(size: 22))
                    .foregroundColor(GGTheme.accent)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(net.ssid.isEmpty || net.hidden ? "‹hidden network›" : net.ssid)
                    .font(GGTheme.sans(17, weight: .bold))
                    .foregroundColor(GGTheme.ink)
                    .lineLimit(1)
                Text(net.bssid)
                    .font(GGTheme.mono(12))
                    .foregroundColor(GGTheme.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(GGTheme.hair).frame(height: 1) }
    }

    // MARK: prop group (.prop-group)

    @ViewBuilder
    private func propGroup<Content: View>(_ title: String, @ViewBuilder _ rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(GGTheme.sans(11, weight: .bold))
                .tracking(0.6)
                .foregroundColor(GGTheme.ink3)
                .padding(.bottom, 7)
            rows()
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
    }

    private func propRow(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack(spacing: 16) {
            Text(k).font(GGTheme.sans(13)).foregroundColor(GGTheme.ink2)
            Spacer(minLength: 0)
            Text(v)
                .font(mono ? GGTheme.mono(12.5) : GGTheme.sans(13).monospacedDigit())
                .foregroundColor(GGTheme.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1) }
    }

    // MARK: comment box (.comment-box)

    private func commentBox(_ net: GGNetwork) -> some View {
        let binding = Binding<String>(
            get: { state.selectedNetwork?.comment ?? "" },
            set: { state.setComment(net.id, $0) }
        )
        return VStack(alignment: .leading, spacing: 7) {
            Text("COMMENT")
                .font(GGTheme.sans(11, weight: .bold)).tracking(0.5)
                .foregroundColor(GGTheme.ink3)
            GGCommentEditor(text: binding, placeholder: "Add a note about this network…")
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.3))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(GGTheme.hair2, lineWidth: 1))
                )
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 18)
        .overlay(alignment: .top) { Rectangle().fill(GGTheme.hair).frame(height: 1) }
    }

    // MARK: - Clients panel (.clients)

    @ViewBuilder
    private func clientsPanel(_ net: GGNetwork) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "display").font(.system(size: 13)).foregroundColor(GGTheme.ink2)
                Text("\(net.clients.count) associated \(net.clients.count == 1 ? "client" : "clients")")
                    .font(GGTheme.sans(12, weight: .semibold))
                    .foregroundColor(GGTheme.ink2)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(GGTheme.hair).frame(height: 1) }

            if net.clients.isEmpty {
                emptyState(symbol: "display",
                           text: "No clients observed on this network yet.")
            } else {
                clientsTable(net)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func clientsTable(_ net: GGNetwork) -> some View {
        VStack(spacing: 0) {
            // header (.cl-table th)
            clientHeaderRow
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(net.clients) { c in
                        clientRow(c)
                    }
                }
            }
        }
    }

    private var clientHeaderRow: some View {
        HStack(spacing: 0) {
            clHead("Client", width: GGClCols.mac, align: .leading)
            clHead("Vendor", minWidth: GGClCols.vendor, align: .leading)
            clHead("Signal", width: GGClCols.sig, align: .leading)
            clHead("sent Bytes", width: GGClCols.bytes, align: .trailing)
            clHead("recv Bytes", width: GGClCols.bytes, align: .trailing)
            clHead("IP Address", width: GGClCols.ip, align: .leading)
            clHead("Last Seen", width: GGClCols.last, align: .leading)
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .overlay(alignment: .bottom) { Rectangle().fill(GGTheme.hair2).frame(height: 1) }
    }

    @ViewBuilder
    private func clHead(_ t: String, width: CGFloat? = nil, minWidth: CGFloat? = nil, align: Alignment) -> some View {
        let label = Text(t).font(GGTheme.sans(11, weight: .semibold)).foregroundColor(GGTheme.ink3)
        if let minWidth = minWidth {
            label.frame(minWidth: minWidth, maxWidth: .infinity, alignment: align).padding(.horizontal, 12)
        } else {
            label.frame(width: width, alignment: align).padding(.horizontal, 12)
        }
    }

    private func clientRow(_ c: GGClient) -> some View {
        HStack(spacing: 0) {
            Text(c.mac).font(GGTheme.mono(12)).foregroundColor(GGTheme.ink).lineLimit(1)
                .frame(width: GGClCols.mac, alignment: .leading).padding(.horizontal, 12)
            Text(c.vendor).font(GGTheme.sans(12.5)).foregroundColor(GGTheme.ink3).lineLimit(1)
                .frame(minWidth: GGClCols.vendor, maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
            HStack { GGSignalBars(value: c.signal); Spacer(minLength: 0) }
                .frame(width: GGClCols.sig, alignment: .leading).padding(.horizontal, 12)
            Text(GGFormat.bytes(c.sent)).font(GGTheme.sans(12.5).monospacedDigit()).foregroundColor(GGTheme.ink3)
                .frame(width: GGClCols.bytes, alignment: .trailing).padding(.horizontal, 12)
            Text(GGFormat.bytes(c.recv)).font(GGTheme.sans(12.5).monospacedDigit()).foregroundColor(GGTheme.ink3)
                .frame(width: GGClCols.bytes, alignment: .trailing).padding(.horizontal, 12)
            Text(c.ip).font(GGTheme.mono(12)).foregroundColor(GGTheme.ink).lineLimit(1)
                .frame(width: GGClCols.ip, alignment: .leading).padding(.horizontal, 12)
            Text(GGFormat.relTime(c.last, now: now)).font(GGTheme.sans(12.5)).foregroundColor(GGTheme.ink3).lineLimit(1)
                .frame(width: GGClCols.last, alignment: .leading).padding(.horizontal, 12)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 34)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1) }
    }

    // MARK: empty state (.empty-state)

    private func emptyState(symbol: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .foregroundColor(GGTheme.ink3.opacity(0.7))
            Text(text)
                .font(GGTheme.sans(13))
                .foregroundColor(GGTheme.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Client column metrics

private enum GGClCols {
    static let mac: CGFloat = 150
    static let vendor: CGFloat = 130
    static let sig: CGFloat = 70
    static let bytes: CGFloat = 92
    static let ip: CGFloat = 110
    static let last: CGFloat = 80
}

// MARK: - Full timestamp (fullTime in components.jsx — UTC, "+0000")

enum GGDetailsFormat {
    static func full(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func p(_ x: Int?) -> String { String(format: "%02d", x ?? 0) }
        return "\(c.year ?? 0)-\(p(c.month))-\(p(c.day)) \(p(c.hour)):\(p(c.minute)):\(p(c.second)) +0000"
    }
}

// MARK: - Comment editor (NSTextView-backed multiline; .comment-box textarea)

#if canImport(AppKit)
import AppKit

@available(macOS 12.0, *)
struct GGCommentEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.drawsBackground = false
        scroll.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textColor = NSColor.white.withAlphaComponent(0.94)
        tv.insertionPointColor = NSColor(red: 0.039, green: 0.518, blue: 1.0, alpha: 1.0)
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.string = text
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GGCommentEditor
        init(_ p: GGCommentEditor) { parent = p }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
#else
@available(macOS 12.0, *)
struct GGCommentEditor: View {
    @Binding var text: String
    var placeholder: String
    var body: some View {
        TextEditor(text: $text).font(GGTheme.sans(13)).padding(8)
    }
}
#endif
