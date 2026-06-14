//
//  GGRootView.swift
//  KisMAC — Golden Gate UI (Stage 1)
//
//  The window content: unified glass toolbar (traffic lights, title,
//  LEADING segmented switcher, flexible spacer, contextual trailing controls,
//  Preferences gear, Scan capsule), the content router, and the bottom
//  status bar. Mirrors app.jsx's App() layout. Dark appearance.
//

import SwiftUI

@available(macOS 12.0, *)
struct GGRootView: View {
    @StateObject private var state = GGAppState()

    var body: some View {
        ZStack {
            // Window background gradient (mirrors body radial/linear gradients).
            backdrop

            VStack(spacing: 0) {
                toolbar
                contentRouter
                statusBar
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .preferredColorScheme(.dark)
        .overlay(prefsOverlay)
    }

    // MARK: backdrop

    private var backdrop: some View {
        LinearGradient(
            colors: [Color(hex: 0x0A0B0F), Color(hex: 0x06070A), Color(hex: 0x050608)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(colors: [Color(hex: 0x0A5AC8, alpha: 0.18), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 700)
        )
        .ignoresSafeArea()
    }

    // MARK: toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            GGTrafficLights()

            HStack(spacing: 5) {
                Text("KisMAC").font(GGTheme.sans(14, weight: .semibold))
                    .foregroundColor(GGTheme.ink)
                Text("v0.3.4").font(GGTheme.sans(11.5, weight: .medium))
                    .foregroundColor(GGTheme.ink3)
            }

            // LEADING segmented switcher — fixed width, never shifts.
            GGSegmentedSwitcher(selection: $state.view)

            Spacer(minLength: 0)

            // Contextual trailing controls.
            trailingControls

            GGIconButton(systemName: "gearshape", active: state.showPreferences) {
                state.showPreferences = true
            }

            GGScanCapsule(scanning: $state.isScanning)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .ggGlass(tint: Color(hex: 0x2C2E36, alpha: 0.55))
    }

    @ViewBuilder
    private var trailingControls: some View {
        switch state.view {
        case .networks, .details:
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13)).foregroundColor(GGTheme.ink3)
                TextField("Search For…", text: $state.searchQuery)
                    .textFieldStyle(.plain)
                    .font(GGTheme.sans(13))
                    .foregroundColor(GGTheme.ink)
                    .frame(width: 170)
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.32))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .stroke(GGTheme.hair2, lineWidth: 1))
            )
        case .graph:
            HStack(spacing: 8) {
                ggPopup($state.graphUnit, ["Bytes", "Packets"])
                ggPopup($state.graphWindow, ["15 sec", "30 sec", "60 sec", "5 min"])
            }
        case .map:
            EmptyView()
        }
    }

    private func ggPopup(_ binding: Binding<String>, _ options: [String]) -> some View {
        Menu {
            ForEach(options, id: \.self) { o in
                Button(o) { binding.wrappedValue = o }
            }
        } label: {
            HStack(spacing: 6) {
                Text(binding.wrappedValue).font(GGTheme.sans(13, weight: .medium))
                    .foregroundColor(GGTheme.ink)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9)).foregroundColor(GGTheme.accent)
            }
            .padding(.leading, 12).padding(.trailing, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(GGTheme.hair2, lineWidth: 1)))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: content router

    @ViewBuilder
    private var contentRouter: some View {
        Group {
            switch state.view {
            case .networks: GGNetworksView(state: state)
            case .details:  GGDetailsView(state: state)
            case .graph:    GGGraphView(state: state)
            case .map:      GGMapView(state: state)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GGTheme.panel)
    }

    // MARK: status bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            chip(symbol: "wifi", value: "\(state.networks.count)", suffix: "networks")
            chip(symbol: "desktopcomputer", value: "\(state.totalClients)", suffix: "clients")

            if state.isScanning {
                HStack(spacing: 6) {
                    Circle().fill(GGTheme.sigStrong).frame(width: 9, height: 9)
                        .shadow(color: GGTheme.sigStrong, radius: 4)
                    Text("Scanning · channel ").foregroundColor(GGTheme.ink2)
                    + Text("\(state.currentChannel)")
                        .foregroundColor(GGTheme.accent)
                }
                .font(GGTheme.sans(11.5))
            } else {
                Text("Idle — press Scan to start capture")
                    .font(GGTheme.sans(11.5))
                    .foregroundColor(GGTheme.ink3)
            }

            Spacer()

            Text(state.gps.label)
                .font(GGTheme.mono(11.5))
                .foregroundColor(GGTheme.ink3)
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .frame(minHeight: 30)
        .ggGlass(tint: Color(hex: 0x282A32, alpha: 0.45))
    }

    private func chip(symbol: String, value: String, suffix: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundColor(GGTheme.ink2)
            Text(value).font(GGTheme.sans(11.5, weight: .semibold)).foregroundColor(GGTheme.ink)
            Text(suffix).font(GGTheme.sans(11.5)).foregroundColor(GGTheme.ink2)
        }
    }

    // MARK: prefs overlay

    @ViewBuilder
    private var prefsOverlay: some View {
        if state.showPreferences {
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .onTapGesture { state.showPreferences = false }
                GGPreferencesWindow(isPresented: $state.showPreferences)
            }
            .transition(.opacity)
        }
    }
}
