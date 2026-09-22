import SwiftUI
import AppKit

struct PermissionSetupView: View {
    static let windowID = "permission-setup"
    static let seenKey = "hasSeenPermissionSetup"
    @ObservedObject var model: ReaderModel
    @AppStorage(Self.seenKey) private var hasSeenPermissionSetup = false
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 44)).foregroundStyle(.tint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to OpenReader Mac").font(.title2.bold())
                    Text("Choose how you’d like to read.").foregroundStyle(.secondary)
                }
            }
            Text("Enable the features you want, or set them up later. Clipboard and pasted-text reading work without either permission.")
                .fixedSize(horizontal: false, vertical: true)

            permissionCard("Accessibility", symbol: "hand.raised", granted: model.accessibilityGranted,
                description: "Read selected and accessible window text in other apps. If selected text is unavailable, automatic Copy is tried. You can disable it in Settings → Permissions. Secure fields are skipped.",
                actionTitle: "Enable Accessibility…", action: model.requestAccessibility)
            permissionCard("Screen Recording", symbol: "rectangle.dashed.badge.record", granted: model.screenGranted,
                description: "Read a chosen region or window with OCR. Capture happens only when you request it. Images are processed on this Mac and are not saved or uploaded.",
                actionTitle: "Enable Screen Recording…", action: model.requestScreen)

            HStack(alignment: .top, spacing: 12) {
                Text("After granting access in System Settings, return here to update the status. Quit and reopen OpenReader Mac if macOS asks you to.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Refresh status") { model.refreshPermissions() }
                    .help("Check Accessibility and Screen Recording permissions again")
            }
            Text("You’ll also need to configure your speech service in Settings → Connection.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                if !model.accessibilityGranted || !model.screenGranted {
                    Button("Set up later", action: finish).keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button("Continue", action: finish).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28).frame(width: 580)
        .onAppear {
            // Showing the guide counts as the first visit, including closing its window.
            // Reopening it from Settings never resets or requests any permission.
            hasSeenPermissionSetup = true
            model.refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
        }
    }

    private func finish() { dismissWindow(id: Self.windowID) }

    private func permissionCard(_ title: String, symbol: String, granted: Bool, description: String,
                                actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: symbol).font(.headline)
                Spacer()
                Label(granted ? "Granted" : "Not granted", systemImage: granted ? "checkmark.circle.fill" : "circle")
                    .font(.callout).foregroundStyle(granted ? Color.green : Color.secondary)
                    .accessibilityLabel("\(title): \(granted ? "Granted" : "Not granted")")
            }
            Text(description).font(.callout).fixedSize(horizontal: false, vertical: true)
            if granted {
                Text("Ready to use").font(.caption).foregroundStyle(.secondary)
            } else {
                Button(actionTitle, action: action)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
