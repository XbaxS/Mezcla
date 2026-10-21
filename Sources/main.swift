import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var model: MixerModel!
    var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = MixerModel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "Mezcla: volumen por aplicación")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 440, height: 700)
        popover.contentViewController = NSHostingController(rootView: MixerView(model: model))
        showWindow()
    }
    func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 700), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Mezcla"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: MixerView(model: model))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
}

if CommandLine.arguments.contains("--diagnose") {
    let result: [String: Any] = [
        "defaultOutput": AudioRead.defaultOutput,
        "outputs": AudioRead.outputs().map { ["id": $0.objectID, "uid": $0.id, "name": $0.name, "sampleRate": $0.sampleRate] as [String: Any] },
        "applications": AudioRead.apps().map { ["id": $0.id, "name": $0.name, "processes": $0.processes, "active": $0.active] as [String: Any] }
    ]
    if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), let value = String(data: data, encoding: .utf8) { print(value) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.setActivationPolicy(.accessory)
    app.delegate = delegate
    app.run()
}
