//
//  GGStubViews.swift
//  KisMAC — Golden Gate UI (Stage 1)
//
//  Placeholder content views. The shell routes between them and they will be
//  replaced with the full implementations in later stages:
//    - Networks / Details / Map  → Stage 2
//    - Graph                     → Stage 3
//    - Preferences               → Stage 4
//

import SwiftUI

@available(macOS 12.0, *)
struct GGNetworksView: View {
    @ObservedObject var state: GGAppState
    var body: some View {
        GGStubView(title: "Networks",
                   stage: "\(state.filteredNetworks.count) of \(state.networks.count) networks · full sortable table coming in stage 2",
                   symbol: "wifi")
    }
}

@available(macOS 12.0, *)
struct GGDetailsView: View {
    @ObservedObject var state: GGAppState
    var body: some View {
        let name = state.selectedNetwork?.displaySSID ?? "—"
        GGStubView(title: "Details",
                   stage: "Selected: \(name) · inspector + client list coming in stage 2",
                   symbol: "magnifyingglass.circle")
    }
}

@available(macOS 12.0, *)
struct GGGraphView: View {
    @ObservedObject var state: GGAppState
    var body: some View {
        GGStubView(title: "Graph",
                   stage: "Unit: \(state.graphUnit) · window: \(state.graphWindow) · live chart coming in stage 3",
                   symbol: "chart.line.uptrend.xyaxis")
    }
}

@available(macOS 12.0, *)
struct GGMapView: View {
    @ObservedObject var state: GGAppState
    var body: some View {
        GGStubView(title: "Map",
                   stage: "GPS \(state.gps.label) · radar map coming in stage 2",
                   symbol: "map")
    }
}

@available(macOS 12.0, *)
struct GGPreferencesWindow: View {
    @Binding var isPresented: Bool
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                GGTrafficLights()
                Spacer()
                Text("Preferences").font(GGTheme.sans(13, weight: .bold))
                    .foregroundColor(GGTheme.ink)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(GGTheme.ink3)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Image(systemName: "gearshape")
                .font(.system(size: 40))
                .foregroundColor(GGTheme.accent.opacity(0.8))
            Text("Preferences")
                .font(GGTheme.sans(20, weight: .bold))
                .foregroundColor(GGTheme.ink)
            Text("Tabs (General · Scanning · Filter · Driver · GPS · Sounds · Traffic) coming in stage 4")
                .font(GGTheme.sans(13))
                .foregroundColor(GGTheme.ink2)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
        .frame(width: 560, height: 380)
        .background(.ultraThinMaterial)
        .background(Color(hex: 0x16171c).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.14), lineWidth: 1))
    }
}
