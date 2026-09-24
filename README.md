# OpenReader Mac

A native macOS reader built with SwiftUI, AppKit, Accessibility, ScreenCaptureKit, Vision, and AVAudioEngine. Read selected text in another app, visible window text, a chosen screen region, clipboard text, or pasted text using your own compatible speech service, with Kokoro for its existing languages and optional local Supertonic 3 for Greek and mixed Greek/English.

Licensed under the [MIT License](LICENSE). The repository contains the Mac client and an optional [multilingual server adapter](Server/README.md). The app does not bundle model weights, SSH keys, account settings, or credentials.

## Features

- Menu-bar commands, a draggable floating player, a reader window, and native Settings.
- Accessibility selection extraction, including Chrome web/PDF views and Preview text PDFs, with automatic Copy fallback for compatible apps that do not expose selected text.
- Local Vision OCR for explicitly requested window/region captures; runtime language checks.
- Play/pause, immediate stop, sentence navigation, local pitch-preserving 0.5×–3× playback, volume, live voice discovery, and sentence progress.
- Word highlighting from validated Kokoro timestamps. For supported selections, a click-through overlay follows the word in the source app without changing its selection or document.
- Customizable global shortcuts, conflict reporting, and per-shortcut disable switches. **Command is optional:** use Control, Option, or Command, optionally with Shift. Bare typing keys and Shift-only typing shortcuts are excluded. Option combinations can overlap with accented-character input; choose combinations that suit your keyboard layout.
- Bounded streaming/prefetch, ordered playback, and cancellation that rejects stale responses.

## Download

Get the universal macOS app from [GitHub Releases](https://github.com/fazakis/openreadermac/releases/latest). It supports Apple Silicon and Intel Macs running macOS 14 or later. Release builds are ad-hoc signed, not Apple-notarized; Gatekeeper may require approval through System Settings → Privacy & Security → Open Anyway after an initial launch attempt.

## Build and run

Requires Xcode with the macOS 14 SDK or newer. Development was validated with Xcode 26.2 on macOS 26.0; macOS 14 is the deployment target. The Release build includes native arm64 and x86_64 executables; runtime testing was on Apple Silicon.

```sh
git clone https://github.com/fazakis/OpenReaderMac.git ~/OpenReaderMac
cd ~/OpenReaderMac
./Scripts/build.sh
swift test
./Scripts/test_shortcuts.sh
./Scripts/test_clipboard.sh
```

Copy `dist/OpenReader Mac.app` into Applications, then run that copy. Complete the build before granting Accessibility and Screen Recording permissions. Rebuilding an ad-hoc app can invalidate prior grants. Keep using the same installed copy after granting access.

The normal Xcode project is `OpenReaderMac.xcodeproj`, with a shared `OpenReaderMac` scheme. There are no external Swift package dependencies. If adding files under `App/` or `Core/`, regenerate project references with `python3 Scripts/generate_project.py`.

## Connect your own server

Fresh installations start with **Manage SSH tunnel off**, an empty SSH host and username, local port `18880`, and API URL `http://127.0.0.1:18880/v1`. That loopback URL requires an already-running service or self-managed tunnel; it does not connect to a bundled server. Enter a compatible API URL or explicitly enable SSH management in Settings. Existing local preferences are retained on upgrade.

The recommended SSH setup keeps server details in `~/.ssh/config`, outside this repository:

```sshconfig
Host openreader-tts
    HostName your-server.example.com
    User your-ssh-user
    # Optional: choose a key; otherwise SSH uses its normal keys/agent.
    # IdentityFile ~/.ssh/id_ed25519
```

Replace the example values locally. Establish and verify SSH access in Terminal first. In OpenReader Settings:

- Enable **Manage SSH tunnel**.
- Set **SSH alias or host** to `openreader-tts`.
- Leave **SSH user (optional)** blank so SSH uses the alias's `User` setting.
- Use local port `18880` and API URL `http://127.0.0.1:18880/v1`.

The app uses the system SSH client with batch mode and strict host-key checking, forwarding only local loopback to server loopback port `8880`. An explicit SSH host and user can also be saved in local app preferences. For another remote speech port, use a self-managed tunnel and disable Manage SSH tunnel. A direct HTTPS deployment is also supported if it exposes the same API contract.

The app invokes `/usr/bin/ssh` without overriding its identity selection, so your normal `~/.ssh/config`, SSH agent, and default identity files apply. SSH private keys and passphrases stay in the existing SSH files/agent. Optional speech API bearer tokens are stored in macOS Keychain, scoped to the API base URL. Settings are stored in macOS preferences, outside the source tree. The app does not create or edit your SSH configuration. See [OpenSSH's configuration reference](https://man.openbsd.org/ssh_config) and [BACKEND_INTEGRATION.md](BACKEND_INTEGRATION.md) for the exact speech contract.

## Permissions and reading

On first launch, a native **Permission setup** window explains Accessibility and Screen Recording, shows their current status, and offers a separate Enable button for each. macOS permission requests appear only after you choose an Enable button; opening the guide does not capture the screen or request access automatically. **Set up later**, **Continue**, or closing the guide lets you proceed without granting either permission. Clipboard and pasted-text reading remain available once your speech connection is configured.

The guide is shown automatically once per local app profile, including the first launch after upgrading from a version without onboarding. Reopen it through **Settings → Permissions → Open permission setup…** or **Permission setup…** in the menu-bar menu. Status refreshes when you return from System Settings; a manual Refresh button is also available. Viewing the guide does not reset existing permissions or connection preferences.

In **Settings → Permissions**, you can also enable Accessibility to read other apps' accessible text and Screen Recording for requested OCR captures. Quit and reopen when macOS requires it. If an ad-hoc rebuild leaves a stale enabled entry, remove that app's old entry and add the final Applications copy again in System Settings.

Focus the source app, select text, and use **Control–Option–Command–R**. Read selection tries Accessibility first. **Automatically use Copy when selected text is unavailable** is enabled by default, including on upgrade; disable it in **Settings → Permissions → Selection compatibility** to use Accessibility only. With the setting enabled, no extra confirmation is shown for each requested reading.

Chrome can delay initializing its native accessibility tree. If it reports no
focused element, OpenReader reads Chrome's application role once and briefly
retries focus before continuing selection extraction. Keep the PDF or webpage
foreground while this happens. Recovery stops on cancellation or a changed
app/window/document; it does not toggle browser flags or reset permissions.

Fallback invokes the source app’s enabled standard Copy menu command using Accessibility; it does not synthesize a keyboard shortcut. It checks the original foreground app, window, focused element, document, and any exposed selection range before invoking Copy. Secure fields and missing Accessibility permission do not trigger fallback. If the source changes or Copy is unavailable, choose Read clipboard or Select screen region explicitly. Apps with no usable Copy menu or insufficient focus information remain unsupported by automatic selection reading; this is not a guarantee for every application.

The previous clipboard’s items and formats are held briefly in memory. Restoration occurs only after one observed ownership change remains stable and both the owner count and contents still match, immediately before writing. Newer or ambiguous changes are retained and the reading is stopped. Promised data, unreadable formats, and existing clipboard data over 16 MB are refused before Copy. An in-flight Copy has up to 1.2 seconds to finish, even after Stop, for cleanup only; cancelled text is never spoken. A very late Copy response can remain on the clipboard after timeout. macOS provides no atomic cross-process compare-and-restore operation, so restoration is best effort for truly simultaneous writers; the app does not continuously monitor or later roll back the clipboard.

Copy-based readings preserve the copied wording and show word progress in OpenReader’s reader. They do not claim source word geometry. A selection request never silently captures the screen. Captured OCR images are processed locally and discarded; only text accepted for speech is sent to your configured service.

Source overlays require real accessible word geometry and valid speech timestamps. Unsupported views, scanned PDFs, clipboard/paste readings, and OCR retain progress in the reader. Source geometry refreshes while playing or paused; the overlay hides for offscreen words, changed text, another window/tab, or another foreground app. The app does not automatically scroll your source document.

With the multilingual server adapter, Greek and mixed Greek/English readings use your selected Supertonic 3 voice for the entire reading. English-only readings retain your regular voice. Test the connection to discover support, then choose the Greek voice under Settings → Playback. The app verifies server capabilities before synthesis; a legacy Kokoro-only server still refuses Greek. Text is not translated or sent to another provider. Supertonic currently uses sentence/chunk highlighting, while Kokoro retains validated word highlighting. Vision OCR languages depend on the installed macOS revision; Greek OCR was unavailable on the development Mac. See [VALIDATION.md](VALIDATION.md) for tested behavior and remaining limits.

## Default shortcuts

All modifiers can be changed in Settings; Command is not required.

| Action | Default |
| --- | --- |
| Read selection | Control–Option–Command–R |
| Read active window | Control–Option–Command–S |
| Select region | Control–Option–Command–A |
| Read clipboard | Control–Option–Command–C |
| Play/pause | Control–Option–Command–P |
| Stop | Control–Option–Command–Period |
| Previous/next sentence | Control–Option–Command–Left/Right |
| Decrease/increase speed | Control–Option–Command–Down/Up |
| Show/hide player | Control–Option–Command–F |

Shortcuts use `RegisterEventHotKey`; there is no typing event tap. Duplicate assignments and registration failures are shown. App-local and some system-reserved conflicts still require testing in the apps you use.

## Development and privacy

- `Core/`: segmentation, text-position mapping, word timing, audio ordering, coordinates, and connection/SSH argument validation.
- `App/`: native UI, extraction, playback, backend, preferences/Keychain, and shortcuts.
- `Tests/`: deterministic regression tests.
- `Validation/`: harmless fixtures and opt-in native test harnesses. Generated reports are ignored.
- `Scripts/`: build, project generation, source-position tests, shortcut/clipboard tests, and live diagnostics.

`build/`, `dist/`, `.build/`, diagnostic output, local config, signing files, and private keys are excluded by `.gitignore`. Do not force-add those files or paste actual connection details into documentation. Only placeholder configuration belongs in the repository. A `.gitignore` does not remove anything already committed; this repository was initialized after sanitizing its source and documentation.

Live diagnostics are opt-in and synthesize audible fixture speech using your locally saved connection. Close the regular app first; run `Scripts/run_diagnostics.sh`. Diagnostics use separate local port `18881` for managed SSH and do not change server configuration. The source-position harness requires a selected fixture in Chrome or Preview: `Scripts/test_source_highlighting.sh com.google.Chrome`.

For an opt-in live Copy integration test, build the disposable source app with `Scripts/build_copy_fixture.sh`, open `build/OpenReader Copy Fixture.app`, and run `Scripts/test_selection_copy.sh` from an Accessibility-authorized terminal. Keep the fixture in the foreground while the test runs. It checks the production Read selection flow and compares the restored clipboard without printing its contents. The fixture runs in explicit extraction-only mode, so the test makes no backend request. The native clipboard tests use separate named pasteboards and never access the general clipboard.

## Signing

The local build is ad-hoc signed with hardened runtime and has no App Sandbox. Release builds strip local debug paths before signing; debug symbols remain only in the ignored build folder. It needs cross-application Accessibility access and the system SSH client. Ad-hoc signing is not notarization or Developer ID signing. Distributing a notarized macOS download requires your own Apple Developer signing identity and notarization workflow. Keep signing material outside Git. See [APPLE_API_NOTES.md](APPLE_API_NOTES.md).
