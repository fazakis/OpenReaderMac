# Speech backend integration

This document describes the service contract verified during development on 22 September 2026. Deployment addresses, SSH usernames, account email, internal account records, and private operational notes are intentionally excluded from the repository. The original deployment record is kept privately outside Git.

## Supported service

The client integrates with **Kokoro FastAPI 0.7.1**, verified at server source revision `b82122f`, using Kokoro v1.0 / Kokoro-82M speech weights. The API model ID is `kokoro`. It is a speech model, not a general-purpose LLM. The initial voice ID is `af_alloy`; voice discovery refreshes from the configured endpoint and unavailable voices are rejected rather than silently substituted.

The reference service had 68 voices, accepted generation speed 1.0, and supported PCM synthesis and model-derived word timestamps. Playback speed is applied locally. No speech instructions, summarization, translation, or rewriting are added. Optional server text normalization is explicitly disabled to preserve original wording; model phonemization is inherent to TTS.

Document layout and transcription/alignment tools used by a web application are separate from speech generation. This Mac client uses local Apple Vision for requested OCR and the speech service's own token timestamps for word progress. It does not call a separate LLM, document-layout service, or Whisper alignment service.

## Connection and authentication

`/app` is a web application path, not an assumed API endpoint. Web account APIs, document history, caches, quotas, and login cookies are not used by this client. The direct speech connection must be authorized separately by the server owner.

For a private loopback service, the app uses the Mac's system SSH client with an alias or explicit host saved in local macOS preferences. Leave the optional SSH user blank to use the alias's `User` directive in `~/.ssh/config`. Keys and passphrases stay with SSH. The actual address, username, SSH port, key path, or ProxyJump settings can therefore stay entirely in the user's SSH configuration.

Equivalent generic tunnel command:

```sh
ssh -N -T -o BatchMode=yes -o StrictHostKeyChecking=yes \
  -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:18880:127.0.0.1:8880 openreader-tts
```

The app does not edit SSH configuration, accept unknown host keys automatically, disable host checks, or guess passwords. Batch mode requires working noninteractive access configured locally first. The forward binds only to loopback. A self-managed tunnel or HTTPS endpoint can be used instead.

The reference private service accepted requests inside the authorized SSH connection without a separate API token. Other deployments may require a bearer token; the client stores it in macOS Keychain per API base URL. Redirects are refused so credentials cannot be forwarded to a different origin. Plaintext HTTP is restricted to loopback and ATS is not globally disabled. No account credentials or server address are embedded in fresh builds.

## Voice discovery

`GET /v1/audio/voices` returns `{"voices":[{"id":"af_alloy","name":"..."}, ...]}`; a legacy list of string IDs is also accepted. The app validates the chosen voice before synthesis.

## Raw streaming synthesis

`POST /v1/audio/speech`, JSON body:

```json
{
  "model": "kokoro",
  "input": "The original text.",
  "voice": "af_alloy",
  "speed": 1.0,
  "response_format": "pcm",
  "stream": true,
  "return_download_link": false,
  "volume_multiplier": 1.0,
  "normalization_options": {"normalize": false}
}
```

Optional `lang_code` overrides the voice-derived pipeline (`a`, `b`, `e`, `f`, `h`, `i`, `j`, `p`, `z`). The response is chunked `audio/pcm`: signed little-endian 16-bit mono at 24,000 Hz. Actual streaming and playback were exercised. The server also lists other formats; the client deliberately uses this verified PCM contract.

## Captioned speech and source highlights

`POST /dev/captioned_speech` is at the origin root, not under `/v1`. It accepts the same body plus `return_timestamps: true`. The verified response has `application/json` content type and contains one JSON object per line:

```json
{
  "audio": "<base64 PCM>",
  "audio_format": "audio/pcm",
  "timestamps": [{"word":"The","start_time":0.0008,"end_time":0.1008}]
}
```

The reference implementation derives timing from model token durations and adjusts for leading audio trimming and packet offsets. Punctuation may extend into trimmed trailing silence. The client accepts only finite, ordered timestamps whose tokens match the original text and whose duration fits the PCM with at most 350 ms trailing tolerance. Final ends are clamped to actual audio duration; missing/invalid timing falls back to sentence progress.

Word mode buffers one bounded sentence before playback to validate all token mappings. Raw mode starts from the first 8,192-byte block. Both use the same speech model, selected voice, and generation speed. Source overlays map the exact selected text into Accessibility text leaves and validate it again before reading word bounds. PDF whitespace differences are allowed only in the geometry mapping; the spoken original is unchanged.

## Bounds and cancellation

- The verified request schema declares no input character maximum; the client does not claim an invented server limit.
- Reference server processing targets 175–250 phoneme tokens with an internal absolute chunk bound of 450 tokens.
- The client splits at sentence boundaries into at most 350 grapheme clusters for latency. Complete readings are bounded to 500,000 characters.
- A response is limited to three minutes of PCM. The player queues about eight seconds plus one 8,192-byte block, with at most one following sentence prefetched.
- Local playback supports 0.5×–3.0× with pitch preservation; generation remains 1.0.
- No standalone cancellation route was provided by the reference service. Cancelling URLSession disconnects the stream. Inference may finish its current unit before the server notices.
- Stop immediately stops local playback; generation IDs reject stale responses. No automatic synthesis retries are made.
- Normal reading does not cache text, screenshots, or audio to disk. Preferences and optional Keychain credentials persist separately. Opt-in diagnostic reports are local and ignored by Git.

## Languages

The supported Kokoro pipeline includes American/British English, Spanish, French, Hindi, Italian, Japanese, Brazilian Portuguese, and Mandarin. It has no Greek pipeline. Greek and mixed Greek/English speech are refused explicitly while preserving the original text. No alternate provider is substituted.

Vision OCR language support is checked at runtime. Greek was absent from the development Mac's supported list. Accessibility, clipboard, and paste preserve Unicode independently of OCR and speech availability.
