import SwiftUI
import AppKit

@main struct OpenReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = ReaderModel()
    var body: some Scene {
        Window("OpenReader Mac", id: "reader") {
            ReaderRoot(model: model, delegate: delegate)
        }.defaultSize(width: 980, height: 720)
        Window("Permission setup", id: PermissionSetupView.windowID) {
            PermissionSetupView(model: model)
        }.windowResizability(.contentSize).defaultPosition(.center)
        Settings { SettingsView(model: model, preferences: model.preferences) }
        MenuBarExtra("OpenReader Mac", systemImage: "waveform.circle") {
            MenuContent(model: model)
        }
        .commands {
            CommandGroup(replacing: .newItem) { Button("Show reader") { model.showReader?() }.keyboardShortcut("n") }
        }
    }
}
struct ReaderRoot: View {
    @ObservedObject var model: ReaderModel
    let delegate: AppDelegate
    @AppStorage(PermissionSetupView.seenKey) private var hasSeenPermissionSetup = false
    @State private var checkedInitialSetup = false
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ReaderView(model: model).onAppear {
            delegate.configure(model)
            model.showReader = { openWindow(id: "reader"); NSApp.activate(ignoringOtherApps: true) }
            if !checkedInitialSetup {
                checkedInitialSetup = true
                if !hasSeenPermissionSetup && !ProcessInfo.processInfo.arguments.contains("--diagnostics") {
                    openWindow(id: PermissionSetupView.windowID)
                }
            }
        }
    }
}
struct MenuContent: View {
    @ObservedObject var model: ReaderModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("OpenReader Mac")
        ForEach(model.preferences.shortcuts) { shortcut in
            Button("\(shortcut.title)  \(shortcut.label)") { model.perform(shortcut.id) }
        }
        Divider()
        Button("Reader / Paste text…") { openWindow(id: "reader"); NSApp.activate(ignoringOtherApps: true) }
        Button("Permission setup…") { openWindow(id: PermissionSetupView.windowID); NSApp.activate(ignoringOtherApps: true) }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit OpenReader Mac") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private weak var model: ReaderModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--diagnostics"), args.count > index+1 {
            Task { await Diagnostics.run(reportPath: args[index+1]) }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model?.stop(); model?.tunnel.close() }
    func configure(_ model: ReaderModel) {
        guard panel == nil else { return }; self.model = model
        let panel = NSPanel(contentRect: NSRect(x: 140, y: 180, width: 382, height: 360), styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "OpenReader Player"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true; panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = NSHostingView(rootView: PlayerView(model: model))
        panel.setFrameAutosaveName("OpenReaderFloatingPlayer")
        self.panel = panel
        model.showPlayer = { [weak panel] in panel?.orderFrontRegardless() }
        model.togglePlayer = { [weak panel] in guard let panel else { return }; if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() } }
    }
}
