# Changelog

## Server full-PDF compatibility hotfix — 24 September 2026

- Handle PDFium's bounded/character extraction marker `U+0002` as well as the
  range API's `U+FFFE`, plus verified legacy parentheses, en-dash and bullet slots.
- Audit complete documents through multiple extractors and actual app chunking;
  provide an offline corpus checker that reports counts/code points, not text.
- Server-only update compatible with Mac 1.5.2; reader text and Kokoro unchanged.

## Server ligature hotfix — 24 September 2026

- Repair legacy PDF `ff`/`fi`/`fl`/`ffi`/`ffl` codes inside dictionary-verified
  Latin words before Supertonic synthesis, including the reported U+001B error.
- Keep reader text and Kokoro forwarding unchanged. Unknown/control-only input
  still gets an explicit error rather than an arbitrary character substitution.
- Requires the updated server dependencies; works with Mac version 1.5.2.

## 1.5.2

- Show bounded speech-validation details for HTTP 422, including the selected
  engine/voice, instead of discarding the server's explanation. Error responses
  never enqueue audio and are not retried automatically.
- The server speaks names for common previously rejected mathematical symbols
  while preserving original displayed text. Remaining unsupported characters
  are identified by Unicode code point, with OCR guidance for broken PDF fonts.
- Keep authentication handling, speech streaming, Chrome recovery and existing
  voice/connection settings unchanged.

## Server hotfix — 24 September 2026

- Prevent Supertonic HTTP 422 failures from PDFium `U+FFFE` hyphenation markers
  and `U+00AD` soft hyphens. Clean only the synthesis copy, preserving displayed
  text, Greek letters and mathematical notation. Kokoro forwarding is unchanged.
- Compatible with the existing Mac app; no new macOS binary is required.

## 1.5.1

- Recover Chrome webpage and PDF selections when native accessibility has not
  initialized: read the application role once, then retry missing focus briefly.
- Keep normal selection reading fast. Do not retry other applications or hide
  permission/AX errors. Stop recovery on cancellation or a changed source context.
- Preserve secure-field checks, verified Copy fallback, and existing speech setup.

## 1.5.0

- Add Greek and mixed Greek/English speech with a local Supertonic 3 backend.
- Discover backend capabilities before synthesis; legacy Kokoro still works for
  its existing languages and rejects Greek without sending its text for synthesis.
- Preserve existing connection settings and English voices; add a separate Greek
  voice selection. Mixed readings use one multilingual voice throughout.
- Preserve 24 kHz playback and Kokoro word timings. Supertonic uses sentence
  highlighting when verified word timestamps are unavailable.
- Include an optional pinned Linux speech adapter and regression tests.
- Build universal Apple Silicon / Intel macOS binaries; minimum macOS 14.
