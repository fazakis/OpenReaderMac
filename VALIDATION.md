# Validation record

## Full-PDF extraction compatibility — 24 September 2026

- Reproduced the previously missed `U+0002` through PDFium bounded-text and raw
  character APIs. All **228 positions** match the range API's `U+FFFE` artifacts.
  Earlier audits covered range extraction only and therefore missed this path.
- Audited **all 31 pages** through PDFium range, bounded and character extraction,
  pypdf, and native PDFKit. Compiled the production Swift `Segmenter` for each
  output: **11,745 chunks** total across the five variants (overlapping content,
  not that many distinct passages). Each complete page and each chunk passes
  the installed Supertonic character validator after preparation/language runs.
- Verified the remaining legacy control glyphs against the rendered document:
  `U+0012/0013` parentheses, `U+0015` en dash, `U+0088` bullet. These explicit
  mappings preserve punctuation rather than deleting arbitrary control codes.
- **54 server tests pass**, including both API contracts, extraction variants,
  combined markers/ligatures/math, isolated delimiter chunks, unchanged Greek,
  marker-only rejection and byte-for-byte Kokoro forwarding.
- Staging and production audio checks passed for real chunks containing each
  remaining code, isolated parentheses, combined mixed-language captioned input,
  and previous PDF-marker/ligature/Greek/English/Kokoro regressions. PCM was
  nonempty, even-length and nonzero; no new listening-quality claim is made.
  The complete corpus also passes against the deployed source and model index.
- This audit establishes zero remaining unsupported-character failures in the
  supplied extraction corpus, not perfect mathematical pronunciation or universal
  PDF decoding. The private manuscript and corpus remain outside Git.

## Server ligature hotfix — 24 September 2026

- The updated client identified `U+001B` as the remaining rejection. In the
  supplied PDF this encodes the `ff` ligature. All **61 occurrences** were checked
  against the document's extracted word tokens; the repair restores their
  verified `ff` spelling, including compounds and the affected proper name.
- Added a pinned local CMU pronunciation dictionary as a spelling check for
  legacy `ff`/`fi`/`fl`/`ffi`/`ffl` repairs. Whole candidate words must be recognized,
  or each component of a hyphenated compound must be recognized. This is a
  constrained heuristic for a known PDF encoding, not a universal font decoder.
- **37 server tests** passed, including repaired raw/captioned API input, case
  handling, unchanged Greek, unknown words, standalone controls and ANSI escapes.
  Real staging audio checks passed for every distinct affected word, mixed
  Greek/English and captioned ligatures; unknown words retain a precise error.
- Reader text and Kokoro requests are unchanged. No Mac rebuild is needed;
  version 1.5.2 works with the updated server and dependency lock.

## Version 1.5.2 — speech validation diagnostics and math symbols

- A full PDFium character audit of the reported PDF found additional unsupported
  mathematical symbols and ambiguous embedded-font control codes beyond the two
  hyphenation markers addressed by the first server hotfix. The newly reported
  failing selection was not supplied, so this does not attribute every 422 to
  one specific character or claim all PDF font damage is repaired.
- **39 core tests**, **24 server tests**, and **12 native HTTP checks** passed.
  Native checks exercised actual URLSession raw/captioned paths against a
  loopback fixture: structured 422, oversized/HTML errors, unchanged 401/503
  handling, no audio on failure, and unchanged successful PCM delivery.
- The server maps ten known mathematical symbols to spoken names, preserves
  Greek/prose and the reader text, and identifies remaining unsupported scalars.
  Controlled tests verify that request text is not included in validation logs
  or structured character-error responses and the queue is released on failure.
- Universal Release **1.5.2 (8)** built on macOS 26 / Xcode 26.2. Minimum macOS
  remains 14. The installed app and existing permission grants were not replaced.
- Ambiguous legacy font codes are deliberately not guessed: use explicit region
  OCR or corrected pasted text. This version is not a universal PDF repair tool.

## Server PDF-marker hotfix — 24 September 2026

- Reproduced Supertonic HTTP 422 using a PDFium-extracted passage with `U+FFFE`
  inside a hyphenated word. Removing only that marker returned valid audio;
  the Greek letters in the passage were supported and preserved.
- **20 server tests** passed, including six new API regression cases for raw and
  captioned synthesis, marker-only input, the original request-length bound,
  preserved Greek/math/combining accents, and byte-for-byte Kokoro forwarding.
- Staging and production checks passed for the original failing passage, combined
  `U+FFFE`/`U+00AD` input, captioned Supertonic output without invented timings,
  unmodified Greek/English, and Kokoro captioned audio with PDF markers. Returned
  PCM was nonempty, even-length and nonzero; Kokoro retained real timestamps.
- Only the server's Supertonic synthesis copy is cleaned. The app source/binary,
  displayed text, voice settings and model files are unchanged. No new Mac build
  is needed. Broken PDF font/ligature mappings remain a separate quality issue.
- The manuscript and extracted passages used for diagnosis are not committed.

## Version 1.5.1 — Chrome accessibility initialization (24 September 2026)

- Root-cause evidence came from the affected Mac's controlled diagnostic: Chrome
  returned `kAXErrorNoValue` (-25212) for focused UI element, while focused window
  and the enabled Copy command were available. A single application-level AXRole
  read followed by a one-second wait made focus and selected text available; the
  user confirmed both webpage and PDF reading in the unchanged app.
- The fix performs that role read only for Google Chrome variants reporting
  `.noValue`, then retries with a two-second deadline and a ten-poll cap. It keeps
  secure-field and Copy-target checks intact and checks the original app/window
  plus any initially available document/title metadata around each focus probe.
- **33 Swift core tests** passed, including nine recovery tests covering delayed
  focus, no overhead for warm focus, non-Chrome/permission failures, bounded
  retries, role-read failure, source changes during waiting and querying,
  cancellation, and subsequent AX errors. These tests use controlled probe
  responses; they are not a claim of another live cold-Chrome reproduction.
- **15 native clipboard checks** and **11 native shortcut checks** passed using
  the existing production regression harnesses, for **59 automated checks** in
  this release. Clipboard checks use separate named pasteboards.
- Universal **arm64 + x86_64** Release build **1.5.1 (7)** succeeded on macOS 26.0
  with Xcode 26.2; minimum macOS remains 14. The installed app was not replaced
  during development. No server changes were needed.
- Both binary architectures and the final ad-hoc signature were verified. The
  app is not Apple-notarized; runtime checks were not performed on Intel.


## Version 1.5.0 — multilingual speech (23 September 2026)

- Built on Apple Silicon with macOS 26.0 and Xcode 26.2. The Release app is
  universal **arm64 + x86_64**, minimum macOS 14, version **1.5.0 (6)**. Both
  architectures compile; runtime validation was on Apple Silicon, not Intel.
- **24 Swift core tests**, including Greek capability negotiation, old preference
  migration, Unicode preservation, voice selection, and legacy refusal, passed.
- **15 native clipboard regression checks** passed. The extraction fixture now
  explicitly disables autoplay rather than relying on Greek being unsupported.
- **14 backend tests** passed: byte-preserving Kokoro proxy, language routing,
  script-span preservation, 24 kHz resampling, invalid requests, and no invented
  word timings.
- The live native harness uses the production ReaderModel, SpeechBackend, and
  AVAudioEngine with muted output and disposable preferences. English captioned,
  Greek, mixed Greek/English, Greek raw playback, and Stop/late-audio rejection
  passed against the real services. This does not constitute a human listening
  assessment or a new OCR/source-overlay test.
- Greek audio was checked using local multilingual speech recognition, which
  recovered the Greek-only test sentence. Mixed readings use explicit Greek and
  English spans with a single voice; automatic transcription of code switching
  is imperfect and is not treated as proof of pronunciation quality.
- Greek/Supertonic exposes no word timestamps and uses honest sentence/chunk
  progress. English/Kokoro retains the existing caption timestamps.
- The binary has a valid ad-hoc signature; it is **not Apple-notarized**. No
  installed app was replaced during development. Server addresses, credentials,
  model weights, and private deployment records are not included in the release.

The sections below record earlier-version validation and are retained as history.

Development checks were performed on Apple Silicon, macOS 26.0 (25A354), Xcode 26.2 (17C52), Swift 6.2.3. Deployment target: macOS 14.0. This record distinguishes tests from implemented features still requiring broader validation. Machine-specific raw reports are excluded from Git.

## Source-highlighting fix (version 1.1)

- Production selection/geometry code mapped **20 of 20 words** in a Chrome HTML fixture, including wrapped text.
- It mapped **19 of 19 words** in a selected Preview PDF fixture across multiple lines.
- It mapped **9 of 9 words** in a selected Chrome built-in PDF paragraph.
- A native harness ran the real `ReaderModel`, `TextExtractor`, Kokoro backend, `AudioPlayback`, and `WordHighlighter` while the Chrome PDF fixture was foreground. **19 timed words and 19 source overlays** were observed through production state. A two-second pause retained the sample position and overlay; playback resumed and the overlay cleared on completion.
- The user subsequently installed version 1.1, renewed permissions, and reported the source highlighting worked very well.
- Four additional mapping tests cover PDF whitespace, repeated text, Unicode/formatting splits, and mismatched/missing text. These brought the suite to **14 passing tests** at that release.

## Existing backend and audio validation

Using the configured real Kokoro service, model `kokoro`, voice `af_alloy`:

- SSH tunnel and live discovery passed (68 voices at verification).
- Raw 24 kHz mono PCM streamed and played through AVAudioEngine. A warm request delivered its first 8,192-byte block in about 0.135 seconds; this is one observation, not a general latency guarantee.
- Pause retained sample position; resume advanced it. Rates 0.5× and 3× were applied locally, with generation remaining 1.0.
- Stop cleared pending audio, cancelled the network task, and rejected stale audio.
- Caption alignment validated all nine words in a fixture, with all nine word ranges observed during playback.
- Connection failure and rejection of a public plaintext HTTP URL were checked.
- HTTP 401/503 behavior was tested using a separately identified, **failure-only** local fixture. No successful synthesis mock was used and no public login password was guessed.

## Native UI and OCR

The release reader, floating controls, Settings, menu commands, global shortcut delivery, sentence/reader-word highlighting, Stop, and explicit unsupported-Greek behavior were exercised. The original mixed Unicode wording was preserved.

Production Vision recognized an English synthetic image fixture and queried available OCR languages at runtime. Region/window capture and multi-display extraction are implemented, but the original end-to-end OCR tests were blocked by stale ad-hoc app permissions. Those checks have not been retrospectively marked successful. Geometry tests cover Retina scaling and negative display origins; only one physical display was available.

## Repository preparation and shortcut update (version 1.2)

This version removes private deployment values from source, supports SSH aliases with an optional username, retains saved local connections, and allows Option-based shortcuts without Command.

- **18 regression tests passed**, including fresh generic defaults, decoding the existing saved-connection schema unchanged, SSH alias/explicit-user arguments, and invalid forwarding inputs. The original segmentation, ordering, cancellation, timing, and source-mapping tests remain passing.
- **11 native shortcut checks passed** using the production manager and real macOS Carbon registration. Control, Option, Control–Option, and Option–Shift registered without Command; duplicate and native registration conflicts were detected, disabled assignments were ignored, and serialization preserved modifiers. Plain/Shift-only typing keys were rejected. This checks registration and configuration; new simulated keystroke or foreground-app delivery tests were not performed in this pass.
- Xcode Release build succeeded for **arm64 and x86_64**. The app reports version **1.2 (3)**; its ad-hoc signature verifies and the MIT license is bundled.
- Source/documentation and the release app were scanned for the known private server address, account email, home-directory paths, and private-key markers. The Git index and source archive contain no builds, reports, local settings, keys, or signing files.
- The existing installed version 1.1 and its local preferences were retained. Live speech/source overlays were validated previously as recorded above; those end-to-end checks were not repeated for this repository/defaults update. No SSH configuration or server configuration was changed.

## First-run permission setup (version 1.3)

- The Release app built successfully for **arm64 and x86_64**, version **1.3 (4)**. All **18 regression tests** passed again; the ad-hoc signature and privacy checks passed.
- A second build from the same production source used a separate validation bundle identifier and local preference domain. The installed app and its permission grants were not replaced or reset.
- With fresh preferences, the native setup window opened automatically and showed Accessibility and Screen Recording as **Not granted**, with individual Enable buttons. No access request appeared just from opening the guide.
- Visually checked the complete light-appearance layout and inspected its accessible controls. The Refresh status button worked without requesting access.
- **Set up later** dismissed the guide and exposed the reader. **Settings → Permissions → Open permission setup…** reopened it. **Continue** dismissed it again. After quitting and relaunching the validation app, the reader opened without showing setup again.
- The Settings UI also confirmed generic fresh connection defaults: SSH off, empty host/user, local port 18880, and loopback API URL.
- Enable buttons call the existing production permission request methods. OS permission grants and a denied-to-granted transition were not exercised in this isolated test; no additional permission was granted. Status refresh on app activation is implemented, with manual refresh and relaunch guidance available.
- Speech synthesis and source highlighting were unchanged and were not repeated in this UI-focused pass.

## Automatic Copy fallback (version 1.4)

- The Release app built successfully for **arm64 and x86_64**, version **1.4 (5)**. Its ad-hoc signature and MIT resource checks passed. The existing **18 core regression tests** and **11 native shortcut checks** passed again.
- **15 native clipboard checks passed** against separate named pasteboards: copied Unicode, multiple items/formats, empty clipboard, no-op Copy, a newer owner, same-owner data mutation, late response after cancellation, non-text output, focus loss, promised formats, the memory limit, pre-dispatch cancellation, uncertain command delivery, and serialization/restoration when a new reading replaces a cancelled one. The general clipboard is not used by these tests.
- An opt-in native integration harness ran the real `ReaderModel`, `TextExtractor`, Copy menu lookup/action, and clipboard reader against a disposable source app. The source intentionally withheld its Accessibility selection while exposing a real enabled Copy command. After the user brought it to the foreground, automatic Read selection returned the exact fixture text, restored the prior general clipboard items/formats, and reported reader-only word highlighting. Disabling the preference prevented Copy and left the clipboard ownership count unchanged.
- The integration fixture includes Greek specifically so the existing unsupported-language check stops before synthesis. No fixture text or previous clipboard data was sent to a backend. This test verifies extraction and fallback routing, not a new speech/playback run.
- In the isolated native UI test, **Automatically use Copy when selected text is unavailable** was initially on. Turning it off updated the switch, and the off state persisted after quitting/relaunching. The test used a separate bundle/preference identity; installed-app preferences and permissions were not modified.
- Secure-field ancestry, original app/window/focus/document, any exposed selection range, and enabled Copy are checked before dispatch. Actual ChatGPT desktop compatibility, customized/localized nonstandard Copy menus, OS clipboard privacy prompts on other macOS versions, and a real secure-field UI case remain unverified in this pass. There is no blanket claim of support for every app.
- Clipboard ownership and payload checks deliberately reject ambiguous/newer changes. macOS does not offer an atomic cross-process compare-and-restore operation; truly simultaneous writers and Copy responses arriving beyond the bounded timeout are documented limitations. No persistent clipboard watcher is installed.

## Remaining scope limits

- A scanned/protected PDF or source app without usable accessible text positions cannot provide dynamic source word overlays; reader progress remains available.
- Active-window/region OCR source overlays and automatic scrolling are not provided.
- Physical multiple-display capture, Intel/macOS 14 runtime, a full VoiceOver audit, and prolonged multi-hour/max-size stress tests remain unverified.
- Ad-hoc rebuilding can invalidate macOS permissions. Complete a release build before renewing permission for its final installed path.
