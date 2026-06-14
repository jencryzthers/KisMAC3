//
//  GGPreferencesView.swift
//  KisMAC — Golden Gate UI (Stage 4)
//
//  The Preferences window: a glass floating panel presented as an overlay over
//  the main content (see GGRootView.prefsOverlay). Mirrors prefs.jsx's
//  PreferencesWindow — a titlebar (traffic lights + centered "KisMAC
//  Preferences"), a single-row 8-tab toolbar (.ptab icon-over-label, active =
//  accent), and a scrollable body switching content per selected tab.
//
//  All 8 tabs (Scanning, Filter, Sounds, Driver, GPS, Map, Traffic, General)
//  are implemented faithfully to the design, with the reusable controls GGSwitch
//  (42×25 track+knob), GGCheck (rounded checkbox + title + small desc), GGSelect
//  (popup with accent chevron), stepper boxes, group cards, section labels and
//  toggle-rows. Field values are local @State (prototype only — NOT persisted to
//  NSUserDefaults), matching the design's behavior.
//

import SwiftUI

// MARK: - Tabs (mirror prefs.jsx PREF_TABS)

@available(macOS 12.0, *)
enum GGPrefTab: String, CaseIterable, Identifiable {
    case scanning, filter, sounds, driver, gps, map, traffic, general
    var id: String { rawValue }

    var label: String {
        switch self {
        case .scanning: return "Scanning"
        case .filter:   return "Filter"
        case .sounds:   return "Sounds"
        case .driver:   return "Driver"
        case .gps:      return "GPS"
        case .map:      return "Map"
        case .traffic:  return "Traffic"
        case .general:  return "General"
        }
    }
    /// SF Symbol approximating the design's custom icon set.
    var symbol: String {
        switch self {
        case .scanning: return "dot.radiowaves.left.and.right"
        case .filter:   return "line.3.horizontal.decrease.circle"
        case .sounds:   return "speaker.wave.2"
        case .driver:   return "cpu"
        case .gps:      return "location"
        case .map:      return "map"
        case .traffic:  return "chart.bar"
        case .general:  return "gearshape"
        }
    }
}

// MARK: - Prototype prefs state (local — not persisted, mirrors prefs.jsx useState)

@available(macOS 12.0, *)
final class GGPrefsState: ObservableObject {
    // scanning
    @Published var driverActive = true
    @Published var hopChannels = true
    @Published var keepEverything = false
    @Published var dwell = "0.25 s"
    // sounds
    @Published var wepOn = "None"
    @Published var wepOff = "None"
    @Published var playEvery = "250"
    @Published var playSound = "None"
    @Published var speak = "None"
    @Published var useSounds = true
    // filter
    @Published var bssids: [String] = []
    @Published var bssidInput = "01:23:45:67:89:AB"
    @Published var bssidSel: String? = nil
    // driver
    @Published var driver = "Apple AirPort Brcm43xx"
    @Published var injection = false
    @Published var channels = "1, 6, 11, 36, 149"
    // gps
    @Published var gpsDevice = "GPSd (localhost:2947)"
    @Published var baud = "4800 baud"
    @Published var traceColor = "Blue"
    @Published var reconnect = true
    // map
    @Published var mapSource = "Apple Imagery"
    @Published var mapZoom = "12"
    @Published var showWaypoints = true
    @Published var showSignal = true
    // traffic
    @Published var trafficUnit = "Bytes"
    @Published var trafficWindow = "15 sec"
    @Published var stacked = false
    // general
    @Published var noAsk = false
    @Published var terminate = true

    private static let bssidRegex = try? NSRegularExpression(
        pattern: "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$")

    func addBssid() {
        let v = bssidInput.trimmingCharacters(in: .whitespaces)
        let range = NSRange(v.startIndex..<v.endIndex, in: v)
        guard let re = Self.bssidRegex,
              re.firstMatch(in: v, range: range) != nil else { return }
        let upper = v.uppercased()
        guard !bssids.contains(upper) else { return }
        bssids.append(upper)
    }

    func removeBssid() {
        guard let sel = bssidSel else { return }
        bssids.removeAll { $0 == sel }
        bssidSel = nil
    }
}

// MARK: - Reusable controls (mirror prefs.jsx Switch / Check / Select)

/// 42×25 track + 20px knob, accent track when on (styles.css .switch).
@available(macOS 12.0, *)
struct GGSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(isOn ? GGTheme.accent : Color.white.opacity(0.16))
                    .frame(width: 42, height: 25)
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: Color.black.opacity(0.4), radius: 1.5, y: 1)
                    .padding(.horizontal, 2.5)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isOn)
        }
        .buttonStyle(.plain)
        .frame(width: 42, height: 25)
    }
}

/// Rounded checkbox + title + optional small description (styles.css .check).
@available(macOS 12.0, *)
struct GGCheck: View {
    @Binding var isOn: Bool
    var title: String
    var desc: String? = nil
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 11) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isOn ? GGTheme.accent : Color.black.opacity(0.25))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .stroke(isOn ? GGTheme.accent : GGTheme.hair2, lineWidth: 1))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(isOn ? 1 : 0)
                    )
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(GGTheme.sans(14))
                        .foregroundColor(GGTheme.ink)
                    if let desc = desc {
                        Text(desc)
                            .font(GGTheme.sans(12.5))
                            .foregroundColor(GGTheme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 420, alignment: .leading)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Popup with the accent chevron (styles.css .select).
@available(macOS 12.0, *)
struct GGSelect: View {
    @Binding var value: String
    var options: [String]
    var body: some View {
        Menu {
            ForEach(options, id: \.self) { o in
                Button(o) { value = o }
            }
        } label: {
            HStack(spacing: 8) {
                Text(value)
                    .font(GGTheme.sans(13))
                    .foregroundColor(GGTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(GGTheme.accent)
            }
            .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .stroke(GGTheme.hair2, lineWidth: 1))
            )
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity)
    }
}

/// Labeled field (styles.css .field): label over a control.
@available(macOS 12.0, *)
struct GGField<Content: View>: View {
    var label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(GGTheme.sans(13, weight: .medium)).foregroundColor(GGTheme.ink)
            content
        }
    }
}

/// A group-card container (styles.css .group-card).
@available(macOS 12.0, *)
struct GGGroupCard<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(GGTheme.hair, lineWidth: 1))
            )
    }
}

/// A toggle-row inside a group card (styles.css .toggle-row).
@available(macOS 12.0, *)
struct GGToggleRow: View {
    var title: String
    var desc: String? = nil
    @Binding var isOn: Bool
    var showDivider: Bool = true
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(GGTheme.sans(14)).foregroundColor(GGTheme.ink)
                    if let desc = desc {
                        Text(desc)
                            .font(GGTheme.sans(12.5))
                            .foregroundColor(GGTheme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                GGSwitch(isOn: $isOn)
            }
            .padding(.vertical, 13)
            if showDivider {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }
        }
    }
}

/// Section label (styles.css .section-label).
@available(macOS 12.0, *)
struct GGSectionLabel: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(GGTheme.sans(11, weight: .bold))
            .tracking(0.5)
            .foregroundColor(GGTheme.ink3)
            .padding(.leading, 4)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Divider between pref sections (styles.css .pref-divider).
@available(macOS 12.0, *)
struct GGPrefDivider: View {
    var body: some View {
        Rectangle().fill(GGTheme.hair).frame(height: 1).padding(.vertical, 22)
    }
}

// MARK: - Preferences window

@available(macOS 12.0, *)
struct GGPreferencesWindow: View {
    @Binding var isPresented: Bool
    @StateObject private var s = GGPrefsState()
    @State private var tab: GGPrefTab = .scanning
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            prefsBar
            ScrollView {
                tabBody
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 620)
        .frame(maxHeight: 620)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x1E1F26, alpha: 0.92), Color(hex: 0x16171C, alpha: 0.94)],
                        startPoint: .top, endPoint: .bottom))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.8), radius: 60, y: 30)
        // prefIn entrance: scale 0.96 + translateY 8 → identity, opacity fade.
        .scaleEffect(appeared ? 1 : 0.96)
        .offset(y: appeared ? 0 : 8)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { appeared = true } }
        .preferredColorScheme(.dark)
    }

    // MARK: titlebar + tabs (.prefs-bar)

    private var prefsBar: some View {
        VStack(spacing: 10) {
            // .prefs-titlebar — traffic lights left, centered title.
            ZStack {
                HStack {
                    HStack(spacing: 8) {
                        Button { isPresented = false } label: {
                            trafficDot(Color(hex: 0xEC6A5E))
                        }
                        .buttonStyle(.plain)
                        trafficDot(Color(hex: 0xF5BF4F))
                        trafficDot(Color(hex: 0x61C554)).opacity(0.5)
                    }
                    Spacer()
                }
                Text("KisMAC Preferences")
                    .font(GGTheme.sans(13, weight: .bold))
                    .foregroundColor(GGTheme.ink)
            }
            .frame(minHeight: 16)

            // .prefs-tabs — single-row 8-tab toolbar.
            HStack(spacing: 4) {
                ForEach(GGPrefTab.allCases) { t in
                    Button { tab = t } label: {
                        VStack(spacing: 4) {
                            Image(systemName: t.symbol).font(.system(size: 17))
                            Text(t.label).font(GGTheme.sans(10.5, weight: .medium))
                        }
                        .foregroundColor(tab == t ? .white : GGTheme.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7).padding(.horizontal, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(tab == t ? GGTheme.accent.opacity(0.28) : .clear)
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(tab == t ? Color.white.opacity(0.2) : .clear, lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 10)
        .overlay(Rectangle().fill(GGTheme.hair).frame(height: 1), alignment: .bottom)
    }

    private func trafficDot(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: tab body router

    @ViewBuilder
    private var tabBody: some View {
        switch tab {
        case .scanning: scanningTab
        case .filter:   filterTab
        case .sounds:   soundsTab
        case .driver:   driverTab
        case .gps:      gpsTab
        case .map:      mapTab
        case .traffic:  trafficTab
        case .general:  generalTab
        }
    }

    // MARK: Scanning

    private var scanningTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            GGSectionLabel(text: "Capture Engine")
            GGGroupCard {
                GGToggleRow(title: "Active driver scanning",
                            desc: "Continuously hop and collect frames on every supported channel.",
                            isOn: $s.driverActive)
                GGToggleRow(title: "Hop channels automatically", isOn: $s.hopChannels)
                GGToggleRow(title: "Keep everything in memory",
                            desc: "Retain all captured packets instead of summaries.",
                            isOn: $s.keepEverything, showDivider: false)
            }
            GGPrefDivider()
            GGField(label: "Dwell time per channel") {
                GGSelect(value: $s.dwell, options: ["0.10 s", "0.25 s", "0.50 s", "1.00 s"])
            }
            .frame(maxWidth: 220, alignment: .leading)
        }
    }

    // MARK: Filter (BSSID list + add/remove)

    private var filterTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            // .bssid-list
            VStack(spacing: 0) {
                Text("BSSID List")
                    .font(GGTheme.sans(12, weight: .semibold))
                    .foregroundColor(GGTheme.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .overlay(Rectangle().fill(GGTheme.hair2).frame(height: 1), alignment: .bottom)
                if s.bssids.isEmpty {
                    Text("No filtered BSSIDs — add one below to ignore it while scanning.")
                        .font(GGTheme.sans(12.5))
                        .foregroundColor(GGTheme.ink3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .frame(height: 190)
                        .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(s.bssids.enumerated()), id: \.element) { idx, b in
                                Text(b)
                                    .font(GGTheme.mono(12.5))
                                    .foregroundColor(GGTheme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(rowBackground(idx: idx, selected: s.bssidSel == b))
                                    .overlay(Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1),
                                             alignment: .bottom)
                                    .contentShape(Rectangle())
                                    .onTapGesture { s.bssidSel = b }
                            }
                        }
                    }
                    .frame(height: 190)
                }
            }
            .background(RoundedRectangle(cornerRadius: 11).fill(Color.black.opacity(0.2)))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(GGTheme.hair2, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 11))

            // .bssid-actions
            HStack(spacing: 9) {
                grayButton("remove", enabled: s.bssidSel != nil) { s.removeBssid() }
                TextField("01:23:45:67:89:AB", text: $s.bssidInput)
                    .textFieldStyle(.plain)
                    .font(GGTheme.mono(13))
                    .foregroundColor(GGTheme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.3))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(GGTheme.hair2, lineWidth: 1)))
                    .frame(maxWidth: .infinity)
                blueButton("add") { s.addBssid() }
            }
        }
    }

    private func rowBackground(idx: Int, selected: Bool) -> some View {
        Group {
            if selected {
                GGTheme.accentSoft.overlay(
                    Rectangle().fill(GGTheme.accent).frame(width: 2), alignment: .leading)
            } else if idx % 2 == 1 {
                Color.white.opacity(0.02)
            } else {
                Color.clear
            }
        }
    }

    // MARK: Sounds

    private var soundsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 30), GridItem(.flexible(), spacing: 30)],
                      alignment: .leading, spacing: 22) {
                GGField(label: "WEP enabled network:") {
                    GGSelect(value: $s.wepOn, options: soundOptions)
                }
                GGField(label: "Play every N packets") {
                    HStack(spacing: 8) {
                        stepperBox($s.playEvery)
                        GGSelect(value: $s.playSound, options: ["None", "Tink", "Pop", "Morse"])
                    }
                }
                GGField(label: "WEP disabled network:") {
                    GGSelect(value: $s.wepOff, options: soundOptions)
                }
                GGField(label: "Speak SSIDs with:") {
                    GGSelect(value: $s.speak, options: ["None", "Samantha", "Alex", "Daniel", "Victoria"])
                }
            }
            GGPrefDivider()
            GGCheck(isOn: $s.useSounds,
                    title: "Use sounds for cracking failure/success",
                    desc: "If the cracking was successful, the open network sound will be played 3 times. If the cracking failed, the closed network sound will be played 3 times.")
        }
    }

    private var soundOptions: [String] { ["None", "Glass", "Ping", "Sosumi", "Submarine"] }

    private func stepperBox(_ value: Binding<String>) -> some View {
        TextField("", text: Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = $0.filter { $0.isNumber } }
        ))
        .textFieldStyle(.plain)
        .multilineTextAlignment(.center)
        .font(GGTheme.mono(13))
        .foregroundColor(GGTheme.ink)
        .frame(width: 56)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(GGTheme.hair2, lineWidth: 1)))
    }

    // MARK: Driver

    private var driverTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            GGField(label: "Capture device") {
                GGSelect(value: $s.driver, options: [
                    "Apple AirPort Brcm43xx", "Apple AirPort (passive)",
                    "USB · Atheros AR9271", "USB · Ralink RT3070"])
            }
            GGField(label: "Channels to scan") {
                TextField("", text: $s.channels)
                    .textFieldStyle(.plain)
                    .font(GGTheme.mono(13))
                    .foregroundColor(GGTheme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.3))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(GGTheme.hair2, lineWidth: 1)))
            }
            GGGroupCard {
                GGToggleRow(title: "Enable packet injection",
                            desc: "Requires a driver and adapter that support monitor + inject.",
                            isOn: $s.injection, showDivider: false)
            }
        }
    }

    // MARK: GPS

    private var gpsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 30), GridItem(.flexible(), spacing: 30)],
                      alignment: .leading, spacing: 22) {
                GGField(label: "GPS device") {
                    GGSelect(value: $s.gpsDevice, options: [
                        "GPSd (localhost:2947)", "Serial /dev/tty.usbserial", "CoreLocation", "None"])
                }
                GGField(label: "Baud rate") {
                    GGSelect(value: $s.baud, options: ["4800 baud", "9600 baud", "38400 baud", "115200 baud"])
                }
                GGField(label: "Trace color") {
                    GGSelect(value: $s.traceColor, options: ["Blue", "Green", "Orange", "Magenta"])
                }
            }
            GGPrefDivider()
            GGGroupCard {
                GGToggleRow(title: "Reconnect automatically if the fix is lost",
                            isOn: $s.reconnect, showDivider: false)
            }
        }
    }

    // MARK: Map

    private var mapTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 30), GridItem(.flexible(), spacing: 30)],
                      alignment: .leading, spacing: 22) {
                GGField(label: "Map source") {
                    GGSelect(value: $s.mapSource, options: [
                        "Apple Imagery", "Apple Standard", "OpenStreetMap", "Offline tiles"])
                }
                GGField(label: "Default zoom") {
                    GGSelect(value: $s.mapZoom, options: ["8", "10", "12", "14", "16"])
                }
            }
            GGPrefDivider()
            GGGroupCard {
                GGToggleRow(title: "Show network waypoints", isOn: $s.showWaypoints)
                GGToggleRow(title: "Color waypoints by signal strength",
                            isOn: $s.showSignal, showDivider: false)
            }
        }
    }

    // MARK: Traffic

    private var trafficTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 30), GridItem(.flexible(), spacing: 30)],
                      alignment: .leading, spacing: 22) {
                GGField(label: "Measure") {
                    GGSelect(value: $s.trafficUnit, options: ["Bytes", "Packets"])
                }
                GGField(label: "Time window") {
                    GGSelect(value: $s.trafficWindow, options: ["15 sec", "30 sec", "60 sec", "5 min"])
                }
            }
            GGPrefDivider()
            GGGroupCard {
                GGToggleRow(title: "Stack series instead of overlaying",
                            isOn: $s.stacked, showDivider: false)
            }
        }
    }

    // MARK: General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            GGSectionLabel(text: "General Options")
            GGGroupCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                VStack(alignment: .leading, spacing: 16) {
                    GGCheck(isOn: $s.noAsk, title: "Do not ask to save data on exit")
                    GGCheck(isOn: $s.terminate, title: "Terminate KisMAC on close of Main Window")
                }
            }
        }
    }

    // MARK: button helpers (.btn.gray / .btn.blue)

    private func grayButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(GGTheme.sans(13, weight: .semibold))
                .foregroundColor(GGTheme.ink)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }

    private func blueButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(GGTheme.sans(13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 9).fill(GGTheme.accent)
                    .shadow(color: GGTheme.accentGlow, radius: 6, y: 3))
        }
        .buttonStyle(.plain)
    }
}
