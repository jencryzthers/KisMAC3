//
//  GGModel.swift
//  KisMAC — Golden Gate UI (Stage 1)
//
//  Data model + seed data ported from the design's data.js, plus the
//  observable app state and the 1100ms scanning engine that mirrors
//  app.jsx's useEffect tick (signal jitter, channel hop, packet/byte growth).
//

import Foundation
import Combine

// MARK: - Model structs (mirror data.js fields)

struct GGGPS: Equatable {
    var lat: Double
    var lng: Double
    var label: String
}

struct GGClient: Identifiable, Equatable {
    var id: String { mac }
    var mac: String
    var vendor: String
    var signal: Int
    var sent: Int
    var recv: Int
    var ip: String
    var last: Date
}

struct GGNetwork: Identifiable, Equatable {
    var id: Int
    var ch: Int
    var ssid: String
    var bssid: String
    var enc: String          // open / wep / wpa / wpa2 / wpa3
    var type: String         // managed / adhoc / ...
    var signal: Int          // baseline 0–100
    var maxSignal: Int
    var avgSignal: Int
    var packets: Int
    var dataPackets: Int
    var mgmtPackets: Int
    var ctrlPackets: Int
    var uniqueIVs: Int
    var injPackets: Int
    var bytes: Int
    var dataBytes: Int
    var vendor: String
    var firstSeen: Date
    var lastSeen: Date
    var lat: Double
    var lng: Double
    var hidden: Bool
    var band: String         // "2.4 GHz" / "5 GHz"
    var comment: String
    var clients: [GGClient]

    // live scan state (mirrors _live / lastSeenLive in app.jsx)
    var liveSignal: Int = 0
    var lastSeenLive: Bool = false

    var displaySSID: String { hidden || ssid.isEmpty ? "<hidden>" : ssid }
}

// MARK: - Channel hop list (app.jsx CHANNELS)

enum GGChannels {
    static let list = [1, 6, 11, 36, 40, 44, 48, 149, 153, 157, 161, 165]
}

// MARK: - View selection

enum GGView: String, CaseIterable, Identifiable {
    case networks, details, graph, map
    var id: String { rawValue }
    var label: String {
        switch self {
        case .networks: return "Networks"
        case .details:  return "Details"
        case .graph:    return "Graph"
        case .map:      return "Map"
        }
    }
    /// SF Symbol approximating the design's custom icon set.
    var symbol: String {
        switch self {
        case .networks: return "wifi"
        case .details:  return "magnifyingglass.circle"
        case .graph:    return "chart.line.uptrend.xyaxis"
        case .map:      return "map"
        }
    }
}

// MARK: - Seed data (ported from data.js — capture near Trois-Rivières, QC)

enum GGSeed {
    /// NOW = 2026-06-14T16:20:30Z
    static let now: Date = ISO8601DateFormatter().date(from: "2026-06-14T16:20:30Z")
        ?? Date(timeIntervalSince1970: 1_781_799_630)

    private static func t(_ sec: Int) -> Date { now.addingTimeInterval(-Double(sec)) }

    static let gps = GGGPS(lat: 46.372955, lng: -72.543038,
                           label: "46.372955N 72.543038W")

    static func networks() -> [GGNetwork] {
        [
            GGNetwork(
                id: 0, ch: 64, ssid: "DEVJC-AP", bssid: "94:2A:6F:36:E6:92",
                enc: "wpa2", type: "managed", signal: 78, maxSignal: 86, avgSignal: 71,
                packets: 184213, dataPackets: 96420, mgmtPackets: 81204, ctrlPackets: 6589,
                uniqueIVs: 0, injPackets: 0, bytes: 41238144, dataBytes: 38112000,
                vendor: "Ubiquiti Inc.", firstSeen: t(3120), lastSeen: t(0),
                lat: 46.3712, lng: -72.5402, hidden: false, band: "5 GHz",
                comment: "Primary lab access point — UniFi U6.",
                clients: [
                    GGClient(mac: "3C:22:FB:8A:11:0E", vendor: "Apple, Inc.", signal: 74, sent: 8421000, recv: 22140000, ip: "192.168.1.24", last: t(2)),
                    GGClient(mac: "F0:18:98:2C:7D:A1", vendor: "Apple, Inc.", signal: 61, sent: 1204000, recv: 5520000, ip: "192.168.1.41", last: t(11)),
                    GGClient(mac: "B8:27:EB:44:90:1C", vendor: "Raspberry Pi Foundation", signal: 48, sent: 644000, recv: 980000, ip: "192.168.1.77", last: t(34)),
                ]),
            GGNetwork(
                id: 1, ch: 11, ssid: "DEVJC-AP (2.4Gh)", bssid: "9A:2A:6F:36:E6:92",
                enc: "wpa2", type: "managed", signal: 64, maxSignal: 70, avgSignal: 58,
                packets: 52310, dataPackets: 21044, mgmtPackets: 29800, ctrlPackets: 1466,
                uniqueIVs: 0, injPackets: 0, bytes: 9120512, dataBytes: 7740000,
                vendor: "Ubiquiti Inc.", firstSeen: t(3110), lastSeen: t(1),
                lat: 46.3712, lng: -72.5402, hidden: false, band: "2.4 GHz",
                comment: "",
                clients: [
                    GGClient(mac: "24:62:AB:9F:33:70", vendor: "Espressif Inc.", signal: 39, sent: 122000, recv: 88000, ip: "192.168.1.103", last: t(6)),
                ]),
            GGNetwork(
                id: 2, ch: 36, ssid: "BELL-A1F2", bssid: "D4:6A:91:0C:A1:F2",
                enc: "wpa3", type: "managed", signal: 71, maxSignal: 75, avgSignal: 66,
                packets: 98750, dataPackets: 60230, mgmtPackets: 36900, ctrlPackets: 1620,
                uniqueIVs: 0, injPackets: 0, bytes: 22456000, dataBytes: 20100000,
                vendor: "Sagemcom Broadband SAS", firstSeen: t(2890), lastSeen: t(0),
                lat: 46.3741, lng: -72.5438, hidden: false, band: "5 GHz",
                comment: "",
                clients: [
                    GGClient(mac: "9C:FC:01:42:18:BB", vendor: "Samsung Electronics", signal: 52, sent: 990000, recv: 3120000, ip: "192.168.2.18", last: t(4)),
                    GGClient(mac: "AC:DE:48:00:11:22", vendor: "Private", signal: 44, sent: 210000, recv: 410000, ip: "192.168.2.31", last: t(28)),
                ]),
            GGNetwork(
                id: 3, ch: 6, ssid: "eero-guest", bssid: "F8:BB:BF:21:5D:09",
                enc: "wpa3", type: "managed", signal: 55, maxSignal: 62, avgSignal: 50,
                packets: 31200, dataPackets: 12010, mgmtPackets: 18900, ctrlPackets: 290,
                uniqueIVs: 0, injPackets: 0, bytes: 4210000, dataBytes: 3380000,
                vendor: "eero inc.", firstSeen: t(1740), lastSeen: t(2),
                lat: 46.3689, lng: -72.5371, hidden: false, band: "2.4 GHz",
                comment: "", clients: []),
            GGNetwork(
                id: 4, ch: 1, ssid: "Meross_SW_0B57", bssid: "48:E1:E9:8E:0B:57",
                enc: "open", type: "managed", signal: 22, maxSignal: 28, avgSignal: 19,
                packets: 4120, dataPackets: 980, mgmtPackets: 3100, ctrlPackets: 40,
                uniqueIVs: 0, injPackets: 0, bytes: 286000, dataBytes: 120000,
                vendor: "Chengdu Meross Technology Co., Ltd.", firstSeen: t(620), lastSeen: t(0),
                lat: 46.3702, lng: -72.5410, hidden: false, band: "2.4 GHz",
                comment: "Smart plug in setup/AP mode.", clients: []),
            GGNetwork(
                id: 5, ch: 1, ssid: "Meross_SW_1430", bssid: "48:E1:E9:87:14:30",
                enc: "open", type: "managed", signal: 18, maxSignal: 24, avgSignal: 15,
                packets: 3010, dataPackets: 640, mgmtPackets: 2350, ctrlPackets: 20,
                uniqueIVs: 0, injPackets: 0, bytes: 198000, dataBytes: 80000,
                vendor: "Chengdu Meross Technology Co., Ltd.", firstSeen: t(540), lastSeen: t(1),
                lat: 46.3705, lng: -72.5412, hidden: false, band: "2.4 GHz",
                comment: "", clients: []),
            GGNetwork(
                id: 6, ch: 11, ssid: "linksys", bssid: "C0:56:27:AA:34:90",
                enc: "wep", type: "managed", signal: 40, maxSignal: 47, avgSignal: 36,
                packets: 21900, dataPackets: 14200, mgmtPackets: 7100, ctrlPackets: 600,
                uniqueIVs: 18442, injPackets: 5210, bytes: 3120000, dataBytes: 2810000,
                vendor: "Belkin International Inc.", firstSeen: t(2200), lastSeen: t(3),
                lat: 46.3668, lng: -72.5455, hidden: false, band: "2.4 GHz",
                comment: "Legacy WEP — collecting IVs.",
                clients: [
                    GGClient(mac: "00:21:6A:3C:99:14", vendor: "Intel Corporate", signal: 33, sent: 540000, recv: 1240000, ip: "192.168.1.6", last: t(9)),
                ]),
            GGNetwork(
                id: 7, ch: 6, ssid: "xfinitywifi", bssid: "3C:7A:8A:11:62:D0",
                enc: "open", type: "managed", signal: 33, maxSignal: 41, avgSignal: 28,
                packets: 8800, dataPackets: 3200, mgmtPackets: 5400, ctrlPackets: 200,
                uniqueIVs: 0, injPackets: 0, bytes: 760000, dataBytes: 510000,
                vendor: "Technicolor CH USA Inc.", firstSeen: t(980), lastSeen: t(5),
                lat: 46.3725, lng: -72.5360, hidden: false, band: "2.4 GHz",
                comment: "", clients: []),
            GGNetwork(
                id: 8, ch: 149, ssid: "", bssid: "E0:CB:BC:7F:02:AE",
                enc: "wpa2", type: "managed", signal: 60, maxSignal: 64, avgSignal: 55,
                packets: 14500, dataPackets: 9100, mgmtPackets: 5200, ctrlPackets: 200,
                uniqueIVs: 0, injPackets: 0, bytes: 3010000, dataBytes: 2700000,
                vendor: "ASUSTek Computer Inc.", firstSeen: t(1500), lastSeen: t(0),
                lat: 46.3760, lng: -72.5395, hidden: true, band: "5 GHz",
                comment: "Hidden SSID — beaconing suppressed.",
                clients: [
                    GGClient(mac: "70:4D:7B:55:2A:10", vendor: "ASUSTek Computer Inc.", signal: 50, sent: 1100000, recv: 2900000, ip: "10.0.0.5", last: t(7)),
                ]),
            GGNetwork(
                id: 9, ch: 149, ssid: "NETGEAR-5G", bssid: "A0:40:A0:6C:9B:31",
                enc: "wpa2", type: "managed", signal: 67, maxSignal: 72, avgSignal: 62,
                packets: 40220, dataPackets: 25600, mgmtPackets: 14100, ctrlPackets: 520,
                uniqueIVs: 0, injPackets: 0, bytes: 8800000, dataBytes: 8010000,
                vendor: "NETGEAR", firstSeen: t(2600), lastSeen: t(1),
                lat: 46.3650, lng: -72.5330, hidden: false, band: "5 GHz",
                comment: "",
                clients: [
                    GGClient(mac: "DC:A6:32:11:88:42", vendor: "Raspberry Pi Trading", signal: 41, sent: 320000, recv: 540000, ip: "192.168.0.51", last: t(15)),
                    GGClient(mac: "5C:CF:7F:09:AA:B3", vendor: "Espressif Inc.", signal: 36, sent: 90000, recv: 60000, ip: "192.168.0.88", last: t(40)),
                ]),
        ]
    }
}

// MARK: - App state + scanning engine

@available(macOS 12.0, *)
final class GGAppState: ObservableObject {
    @Published var networks: [GGNetwork]
    @Published var selectedID: Int? = 0
    @Published var isScanning: Bool = false { didSet { scanningChanged() } }
    @Published var view: GGView = .networks
    @Published var searchQuery: String = ""
    @Published var graphUnit: String = "Bytes"          // Bytes / Packets
    @Published var graphWindow: String = "15 sec"
    @Published var channelIndex: Int = 0
    @Published var showPreferences: Bool = false

    let gps = GGSeed.gps
    private var timer: Timer?

    init() {
        var nets = GGSeed.networks()
        for i in nets.indices { nets[i].liveSignal = nets[i].signal }
        self.networks = nets
    }

    var totalClients: Int { networks.reduce(0) { $0 + $1.clients.count } }
    var currentChannel: Int { GGChannels.list[channelIndex % GGChannels.list.count] }
    var selectedNetwork: GGNetwork? {
        guard let id = selectedID else { return nil }
        return networks.first { $0.id == id }
    }

    var filteredNetworks: [GGNetwork] {
        let q = searchQuery.lowercased()
        guard !q.isEmpty else { return networks }
        return networks.filter {
            $0.displaySSID.lowercased().contains(q)
            || $0.bssid.lowercased().contains(q)
            || $0.vendor.lowercased().contains(q)
        }
    }

    // MARK: scanning engine — 1100ms tick mirroring app.jsx
    private func scanningChanged() {
        timer?.invalidate(); timer = nil
        if isScanning {
            let t = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: true) { [weak self] _ in
                self?.tick()
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else {
            for i in networks.indices { networks[i].lastSeenLive = false }
        }
    }

    private func tick() {
        channelIndex = (channelIndex + 1) % GGChannels.list.count
        let nowDate = Date()
        for i in networks.indices {
            let jitter = (Double.random(in: 0...1) - 0.5) * 12.0
            let blended = Double(networks[i].signal) * 0.8
                        + Double(networks[i].liveSignal) * 0.2 + jitter
            let live = max(2, min(100, Int(blended.rounded())))
            let active = Double.random(in: 0...1) > 0.25
            networks[i].liveSignal = live
            networks[i].lastSeenLive = active
            if active {
                networks[i].lastSeen = nowDate
                networks[i].packets += Int.random(in: 0..<140)
                networks[i].bytes   += Int.random(in: 0..<30000)
            }
        }
    }

    func setComment(_ id: Int, _ value: String) {
        if let idx = networks.firstIndex(where: { $0.id == id }) {
            networks[idx].comment = value
        }
    }

    deinit { timer?.invalidate() }
}

// MARK: - Formatting helpers (mirror components.jsx)

enum GGFormat {
    static func bytes(_ n: Int) -> String {
        if n == 0 { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        let i = min(units.count - 1, Int(log(Double(n)) / log(1024)))
        let v = Double(n) / pow(1024, Double(i))
        return String(format: i == 0 ? "%.0f %@" : "%.1f %@", v, units[i])
    }

    static func num(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func relTime(_ date: Date, now: Date) -> String {
        let s = max(0, Int((now.timeIntervalSince(date)).rounded()))
        if s < 3 { return "now" }
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }
}
