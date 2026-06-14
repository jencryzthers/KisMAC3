//
//  GGWindowController.swift
//  KisMAC — Golden Gate UI (Stage 1)
//
//  Obj-C-callable hosting controller that lazily creates and shows the
//  native SwiftUI "Golden Gate" window. Bridged to AppKit via @objc so the
//  existing Obj-C app startup (ScanController) can open it without a XIB.
//
//  Stage 1 scope: the shell (toolbar / segmented switcher / status bar) over
//  the stub content views. Stages 2–4 fill in the real views.
//

import AppKit
import SwiftUI

@available(macOS 13.0, *)
@objc(KGGoldenGateWindowController)
public final class GGWindowController: NSObject, NSWindowDelegate {

    // Strong reference so the window/controller isn't deallocated.
    private var window: NSWindow?

    @objc public func showWindow() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = GGRootView()
        let hosting = NSHostingController(rootView: root)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Golden Gate Interface"
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentViewController = hosting
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        win.setFrameAutosaveName("KGGoldenGateWindow")

        self.window = win

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Keep the controller alive even after the window closes (lazy re-show).
    public func windowWillClose(_ notification: Notification) {
        // Intentionally retain `window`; re-showing reuses it.
    }
}
