# Changelog

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
