# OpenReader Mac

- Native SwiftUI/AppKit app, deployment target macOS 14. Core logic is shared with Swift Package tests.
- Keep server addresses, account identifiers, private keys, tokens, local configuration, and private deployment notes out of source and tracked files.
- Use generic examples in documentation. Machine-specific connection settings belong in macOS preferences, SSH configuration, or Keychain.
- Do not commit build/dist folders, diagnostic reports, signing material, or Xcode user state.
- Run `python3 Scripts/generate_project.py` after adding app or core files. Build with `Scripts/build.sh`; test with `swift test` and relevant native harnesses.
- Avoid replacing the installed app during development: ad-hoc rebuilds can invalidate macOS Accessibility and Screen Recording grants. Prepare the final build first.
