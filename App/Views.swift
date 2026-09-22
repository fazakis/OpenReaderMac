import SwiftUI
import AppKit
import Carbon

struct PlayerView: View {
    @ObservedObject var model: ReaderModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.circle.fill").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenReader").font(.headline)
                    Text(model.source).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { model.showReader?() } label: { Image(systemName: "text.book.closed") }.help("Open reader").accessibilityLabel("Open reader")
                SettingsLink { Image(systemName: "gearshape") }.help("Settings")
                Button { model.togglePlayer?() } label: { Image(systemName: "minus") }.help("Hide player · \(model.shortcut("player"))").accessibilityLabel("Hide player")
            }.buttonStyle(.plain)
            if !model.chunks.isEmpty {
                Text(model.chunks[min(model.audio.currentChunk, model.chunks.count-1)].text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 14)).lineLimit(3).frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            } else {
                Text("Select text in another app, then press \(model.shortcut("selection")).").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 20) {
                Spacer()
                control("backward.end.fill", "Previous sentence", "previous")
                Button { model.perform("play") } label: {
                    Image(systemName: model.audio.isActive && !model.audio.isPaused ? "pause.fill" : "play.fill").font(.title2).frame(width: 46, height: 46)
                }.buttonStyle(.borderedProminent).clipShape(Circle()).help("Play / pause · \(model.shortcut("play"))").accessibilityLabel(model.audio.isPaused ? "Resume reading" : "Play or pause")
                control("forward.end.fill", "Next sentence", "next")
                control("stop.fill", "Stop immediately", "stop")
                Spacer()
            }
            HStack {
                Text(model.audio.isPaused ? "Paused" : model.audio.isBuffering ? "Buffering…" : model.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !model.chunks.isEmpty { Text("Chunk \(min(model.audio.currentChunk+1,model.chunks.count)) / \(model.chunks.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }
            ProgressView(value: model.status == "Finished" ? 1 : Double(model.audio.currentChunk), total: model.status == "Finished" ? 1 : Double(max(1, model.chunks.count))).accessibilityLabel("Reading progress by chunk")
            HStack {
                Image(systemName: "speedometer").foregroundStyle(.secondary)
                Slider(value: $model.preferences.speed, in: 0.5...3, step: 0.1).accessibilityLabel("Playback speed")
                Text(String(format: "%.1f×", model.preferences.speed)).monospacedDigit().frame(width: 40)
            }
            HStack {
                Image(systemName: "speaker.wave.2").foregroundStyle(.secondary)
                Slider(value: $model.preferences.volume, in: 0...1).accessibilityLabel("Volume")
                Picker("Voice", selection: $model.preferences.connection.voice) {
                    ForEach(Array(Set(model.voices + [model.preferences.connection.voice])).sorted(), id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 140).help("Kokoro voice; changing it stops current playback")
            }
            Menu {
                ForEach(model.preferences.shortcuts.filter { ["selection","window","region","clipboard"].contains($0.id) }) { s in
                    Button("\(s.title)  \(s.label)") { model.perform(s.id) }
                }
                Button("Paste and read…") { model.showReader?() }
            } label: { Label("Read from…", systemImage: "plus") }.menuStyle(.borderlessButton)
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                HStack {
                    Button("Read clipboard") { model.perform("clipboard") }
                    Button("Choose region") { model.perform("region") }
                    Button("Dismiss") { model.error = nil }
                }.font(.caption)
            }
        }.padding(16).frame(width: 350).background(.regularMaterial)
    }
    private func control(_ symbol: String, _ name: String, _ action: String) -> some View {
        Button { model.perform(action) } label: { Image(systemName: symbol).frame(width: 25, height: 30) }.buttonStyle(.plain).help("\(name) · \(model.shortcut(action))").accessibilityLabel(name)
    }
}

struct ReaderView: View {
    @ObservedObject var model: ReaderModel
    @State private var showInput = true
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                Label("OpenReader Mac", systemImage: "waveform.circle.fill").font(.title2.weight(.semibold))
                Text("Your text. Your voice.").foregroundStyle(.secondary)
                ForEach(model.preferences.shortcuts.filter { ["selection","window","region","clipboard"].contains($0.id) }) { s in
                    Button { model.perform(s.id) } label: { VStack(alignment: .leading) { Text(s.title); Text(s.label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
                }
                Divider()
                Text("CONNECTION").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("Kokoro · \(model.preferences.connection.voice)").font(.callout)
                Text("Generation 1.0 · Playback \(String(format: "%.1f×",model.preferences.speed))").font(.caption).foregroundStyle(.secondary)
                Button("Test connection & refresh voices") { model.connect() }.disabled(model.isConnecting)
                SettingsLink { Label("Settings & permissions", systemImage: "gearshape") }
                Spacer()
                Text("Text leaves this Mac only for speech generation. Captured images are processed locally and discarded.").font(.caption).foregroundStyle(.secondary)
            }.padding(22).frame(minWidth: 210, idealWidth: 230, maxWidth: 280)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading) { Text(model.source).font(.title2.bold()); Text(model.note + " · " + model.wordHighlightStatus).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button { showInput.toggle() } label: { Label("Paste text", systemImage: "text.badge.plus") }
                    Button { model.showPlayer?() } label: { Label("Player", systemImage: "pip") }
                }.padding(22)
                if showInput {
                    VStack(alignment: .leading, spacing: 10) {
                        TextEditor(text: $model.inputText).font(.body).frame(height: 110).padding(6).background(.background).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                            .accessibilityLabel("Paste or type text to read")
                        HStack { Text("Paste the original text here.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Read text") { model.pasteAndRead(); if !model.chunks.isEmpty { showInput = false } }.buttonStyle(.borderedProminent).disabled(model.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                    }.padding(.horizontal,22).padding(.bottom,16)
                }
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        if model.chunks.isEmpty {
                            ContentUnavailableView("Ready when you are", systemImage: "text.book.closed", description: Text("Select text in another application, read your clipboard, or paste a passage above."))
                                .frame(maxWidth: .infinity).padding(.top, 60)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 7) {
                                ForEach(model.chunks) { chunk in
                                    Button { model.play(from: chunk.id) } label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            Text("\(chunk.id+1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                                            highlightedText(chunk).font(.system(size: 19)).lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.primary)
                                        }.padding(12).background(chunk.id == model.audio.currentChunk ? Color.accentColor.opacity(0.13) : .clear).clipShape(RoundedRectangle(cornerRadius: 10))
                                    }.buttonStyle(.plain).id(chunk.id).help(chunk.isFragment ? "Play from this sentence fragment" : "Play from this sentence")
                                }
                            }.padding(22)
                        }
                    }.onChange(of: model.audio.currentChunk) { _, index in withAnimation { proxy.scrollTo(index, anchor: .center) } }
                }
                if let error = model.error { Text(error).font(.callout).foregroundStyle(.orange).padding(18).textSelection(.enabled) }
                Divider()
                HStack(spacing: 16) {
                    Button { model.perform("previous") } label: { Image(systemName: "backward.end.fill") }.accessibilityLabel("Previous sentence")
                    Button(model.audio.isPaused ? "Resume" : model.audio.isActive ? "Pause" : "Play") { model.perform("play") }.buttonStyle(.borderedProminent)
                    Button { model.perform("next") } label: { Image(systemName: "forward.end.fill") }.accessibilityLabel("Next sentence")
                    Button("Stop") { model.stop() }
                    Spacer(); Text(model.audio.isPaused ? "Paused" : model.status).foregroundStyle(.secondary)
                }.padding(18)
            }.frame(minWidth: 470)
        }.frame(minWidth: 780, minHeight: 570)
    }
    private func highlightedText(_ chunk: Sentence) -> Text {
        guard model.preferences.highlightWords, model.audio.wordChunk == chunk.id, let range = model.audio.currentWord,
              let swiftRange = Range(range, in: chunk.text) else { return Text(chunk.text) }
        var word = AttributedString(String(chunk.text[swiftRange]))
        word.backgroundColor = .yellow.opacity(0.45)
        return Text(String(chunk.text[..<swiftRange.lowerBound])) + Text(word).bold() + Text(String(chunk.text[swiftRange.upperBound...]))
    }

}

struct SettingsView: View {
    @ObservedObject var model: ReaderModel
    @ObservedObject var preferences: Preferences
    @State private var token = ""
    @State private var credentialStatus = ""
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        TabView {
            Form {
                Section("Speech connection") {
                    LabeledContent("Model", value: "kokoro")
                    Text("Connect to your own Kokoro speech service. Keep server addresses and key paths in ~/.ssh/config and enter an alias below. Connection settings stay on this Mac.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Manage SSH tunnel", isOn: $preferences.connection.useSSH)
                    TextField("SSH alias or host", text: $preferences.connection.sshHost).disabled(!preferences.connection.useSSH)
                    TextField("SSH user (optional)", text: $preferences.connection.sshUser).disabled(!preferences.connection.useSSH)
                    TextField("Local port", value: $preferences.connection.localPort, format: .number.grouping(.never)).disabled(!preferences.connection.useSSH)
                    TextField("Speech API base URL", text: $preferences.connection.serverURL)
                    Text(preferences.connection.useSSH ? "For an SSH alias, leave the user empty to use ~/.ssh/config. The local port forwards to the server’s loopback port 8880. A web /app page is not a speech API." : "SSH management is off. The prefilled address requires a speech service or your own tunnel already running on local port 18880. You can enter a compatible HTTPS API URL instead, or enable SSH management above.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Optional HTTPS / self-managed connection") {
                    SecureField("API bearer token", text: $token)
                    HStack { Button("Save to Keychain") { do { try SecretStore.save(token, account: SecretStore.key(for: preferences.connection.serverURL)); token = ""; credentialStatus = "Saved in Keychain" } catch { credentialStatus = error.localizedDescription } }; Text(credentialStatus).font(.caption) }
                    Text("Leave empty if your speech endpoint does not require a bearer token. SSH keys remain in your existing SSH agent/files. Passwords and tokens are never stored in preferences.").font(.caption).foregroundStyle(.secondary)
                }
                Button(model.isConnecting ? "Connecting…" : "Test connection & load live voices") { model.connect() }.disabled(model.isConnecting)
                Text(model.status).font(.caption)
                if let error = model.error { Text(error).foregroundStyle(.orange).font(.caption) }
            }.formStyle(.grouped).tabItem { Label("Connection", systemImage: "network") }
            Form {
                Section("Voice & playback") {
                    Picker("Voice", selection: $preferences.connection.voice) { ForEach(Array(Set(model.voices + [preferences.connection.voice])).sorted(), id: \.self) { Text($0).tag($0) } }
                    Button("Refresh available voices") { model.connect() }
                    Picker("Speech language", selection: $preferences.connection.language) {
                        Text("From voice (verified default)").tag("auto")
                        Text("American English").tag("a"); Text("British English").tag("b")
                        Text("Spanish").tag("e"); Text("French").tag("f"); Text("Hindi").tag("h"); Text("Italian").tag("i"); Text("Japanese").tag("j"); Text("Brazilian Portuguese").tag("p"); Text("Mandarin").tag("z")
                    }
                    Toggle("Highlight words using Kokoro timestamps", isOn: $preferences.highlightWords)
                    Text("Word emphasis appears in the reader. For selections with accessible word bounds, a yellow overlay follows the word in the source app. Unsupported apps retain reader highlighting. Disable this option for the lowest-latency raw PCM stream.").font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Generation speed", value: "1.0× (fixed)")
                    LabeledContent("Local playback", value: String(format: "%.1f×", preferences.speed))
                    Slider(value: $preferences.speed, in: 0.5...3, step: 0.1).accessibilityLabel("Local playback speed")
                    Slider(value: $preferences.volume, in: 0...1) { Text("Volume") }
                    Text("Pitch is preserved. Playback speed is applied locally. Word timing is used only when returned tokens match the original text and pass timing validation. Otherwise progress stays at sentence/chunk level.").font(.caption).foregroundStyle(.secondary)
                }
                Section("OCR & languages") {
                    Picker("OCR language", selection: $preferences.ocrLanguage) { Text("English").tag("en"); Text("Greek").tag("el"); Text("English + Greek").tag("mixed") }
                    Text("Vision languages on this Mac: \(model.ocrLanguages.joined(separator: ", "))").font(.caption).textSelection(.enabled)
                    Text("The supported Kokoro backend has no Greek voice or language pipeline. Greek text stays intact in the reader, but Greek and mixed Greek/English speech are disabled. No translation or alternate provider is used.").font(.caption).foregroundStyle(.orange)
                }
            }.formStyle(.grouped).tabItem { Label("Playback", systemImage: "speaker.wave.2") }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Global keyboard shortcuts").font(.title2.bold())
                    Text("Every shortcut can be changed or disabled. Command is optional: choose Control, Option, or Command, with Shift if desired. Unmodified and Shift-only typing keys are excluded. macOS reports registered conflicts; app-local and system-reserved combinations may need manual testing.").font(.caption).foregroundStyle(.secondary)
                    ForEach($preferences.shortcuts) { $s in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Toggle(s.title, isOn: $s.enabled).frame(width: 190, alignment: .leading)
                                modifier("⌃", UInt32(controlKey), shortcut: $s)
                                modifier("⌥", UInt32(optionKey), shortcut: $s)
                                modifier("⇧", UInt32(shiftKey), shortcut: $s)
                                modifier("⌘", UInt32(cmdKey), shortcut: $s)
                                Picker("Key", selection: $s.key) { ForEach(Shortcut.keyNames, id: \.1) { Text($0.0).tag($0.1) } }.labelsHidden().frame(width: 85)
                            }
                            if let message = model.shortcuts.conflicts[s.id] { Text(message).font(.caption).foregroundStyle(.orange) }
                        }
                    }
                    Button("Restore proposed defaults") { preferences.shortcuts = Shortcut.defaults }
                }.padding(24)
            }.tabItem { Label("Shortcuts", systemImage: "keyboard") }
            Form {
                Section("Permission setup") {
                    Button("Open permission setup…") { openWindow(id: PermissionSetupView.windowID) }
                    Text("Revisit the first-run guide at any time. Permission prompts appear only when you choose an Enable button.").font(.caption)
                }
                Section("Selection compatibility") {
                    Toggle("Automatically use Copy when selected text is unavailable", isOn: $preferences.automaticCopyFallback)
                    Text("Enabled by default. Read selection first tries Accessibility, then the source app’s enabled Copy command. The previous clipboard is restored only while the copied contents remain unchanged. No keyboard shortcut or screen capture is sent. Copy fallback highlights words in the reader, not in the source app.").font(.caption)
                }
                Section("Permissions are requested only for the features that need them") {
                    LabeledContent("Accessibility", value: model.accessibilityGranted ? "Granted" : "Not granted")
                    Text("Reads selected and visible text from the source app. Secure fields are skipped. Automatic Copy fallback can be disabled above. It requires Accessibility access too.").font(.caption)
                    Button("Enable Accessibility…") { model.requestAccessibility() }
                    LabeledContent("Screen Recording", value: model.screenGranted ? "Granted" : "Not granted")
                    Text("Used only when you request region OCR, or active-window OCR is needed. Images are processed locally, not saved or uploaded. Select a region without password fields.").font(.caption)
                    Button("Enable Screen Recording…") { model.requestScreen() }
                    Button("Refresh permission status") { model.refreshPermissions() }
                }
                Section("If access still fails") {
                    Text("In System Settings → Privacy & Security, enable this exact OpenReader Mac build. Quit and reopen the app if prompted. After moving or rebuilding an ad-hoc signed app, remove its old permission entry and add the new copy if needed. Some apps and protected PDFs do not expose selected text; use the explicit clipboard or region command.").font(.callout)
                }
            }.formStyle(.grouped).onAppear { model.refreshPermissions() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshPermissions() }
                .tabItem { Label("Permissions", systemImage: "hand.raised") }
        }.frame(width: 700, height: 620)
    }
    private func modifier(_ title: String, _ flag: UInt32, shortcut: Binding<Shortcut>) -> some View {
        Toggle(title, isOn: Binding(get: { shortcut.wrappedValue.modifiers & flag != 0 }, set: { enabled in
            if enabled { shortcut.wrappedValue.modifiers |= flag } else { shortcut.wrappedValue.modifiers &= ~flag }
        })).toggleStyle(.button).help(title)
    }
}
