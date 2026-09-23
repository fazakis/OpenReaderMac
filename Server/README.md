# Optional multilingual speech adapter

This small FastAPI adapter preserves the Mac client's Kokoro contract and adds
local Supertonic 3 Greek/English synthesis. It reuses the upstream Supertonic SDK;
it is not a new TTS implementation. The upstream SDK and weights are archived, so
both are pinned. No cloud synthesis, translation, or voice cloning is used.

Why an adapter: the client requires signed 16-bit little-endian mono **24 kHz PCM**,
`/v1/audio/voices`, and Kokoro's `/dev/captioned_speech`. Supertonic's original
server emits 44.1 kHz audio and does not provide that caption contract.

## Install (Linux, Python 3.12, ffmpeg)

Choose an isolated directory. Do not install these dependencies into Kokoro's venv.

```sh
mkdir -p ~/.local/share/openreader-speech
cp Server/{speech_api.py,download_model.py,requirements.lock} ~/.local/share/openreader-speech/
cd ~/.local/share/openreader-speech
python3 -m venv .venv
.venv/bin/pip install -r requirements.lock
.venv/bin/python download_model.py models/supertonic-3
```

The model downloader retrieves public assets from the archived Hugging Face
repository at revision `aafc6e32416a594460b32413efc49d7fe4ce6d46`. The SDK is pinned
to `df0f9686dac7fbbde391b759e2ee5286a3737622`. The model has its own OpenRAIL-M
license, downloaded with the assets; model weights are not bundled with the app.

Test first on a spare loopback port, with Kokoro still running unchanged:

```sh
SUPERTONIC_MODEL_DIR="$PWD/models/supertonic-3" \
KOKORO_URL=http://127.0.0.1:8880 HF_HUB_OFFLINE=1 \
  .venv/bin/uvicorn speech_api:app --host 127.0.0.1 --port 8890 --no-access-log
```

For production, inspect and back up the existing Kokoro service/start script.
Move only its loopback listening port to `8881`, then install the supplied user
unit to put this adapter at `8880`. Adjust its paths for the chosen directory.
Check both `/health` and `/v1/capabilities` before considering the rollout complete.
To roll back, stop the adapter, restore Kokoro's original port/start script, and
restart Kokoro. Keep the original venv, model, voices, and service intact.

This service has no standalone authentication: bind only to loopback and use SSH,
or put it behind an existing authenticated HTTPS proxy. Do not expose it directly
to the network. Request bodies/audio are held in memory; access logging is off.

## API behavior

- Existing non-Greek Kokoro requests, caption timings, formats, paths, and voices
  pass through unchanged to the fixed local upstream.
- `GET /v1/capabilities` advertises Greek/mixed support, 24 kHz output, ten Greek
  voices, and the absence of Greek word timings. Legacy Kokoro returns 404 here.
- `GET /v1/audio/voices` adds `st_f1`–`st_f5` and `st_m1`–`st_m5`.
- `GET /v1/models` adds `supertonic-3`.
- Select `model: "supertonic-3"` and a `st_` voice for Greek or mixed text.
  Greek-only input uses `el`; mixed Greek/English input is split at script boundaries and synthesized with explicit `el`/`en` using the same voice. Every original character is preserved across those spans.
  Other supported explicit language codes are passed to the SDK.
- Greek sent with a Kokoro voice is rejected, not transliterated or silently
  substituted. The Mac app selects the configured Greek voice explicitly.
- Supertonic output is resampled to 24 kHz. PCM, WAV, MP3, FLAC, Opus and AAC are
  supported; compressed formats use local ffmpeg. Supertonic responses are
  buffered per bounded request, not token-streamed. Kokoro streaming is unchanged.
- Supertonic caption responses contain the audio and an **empty timestamps list**.
  The app uses sentence/chunk progress; no approximate word timings are invented.
- Synthesis is serialized with bounded queue waiting, while Kokoro requests can
  proceed independently. Inference uses CPU ONNX with four intra-op threads.
  Disconnecting cancels client playback; in-flight inference may finish its unit.

```sh
curl http://127.0.0.1:8880/v1/audio/speech \
  -H 'Content-Type: application/json' \
  -d '{"model":"supertonic-3","voice":"st_f1","input":"Καλημέρα! Hello world.","response_format":"wav"}' \
  --output sample.wav
```

## Verification

Install pytest separately and run `.venv/bin/pytest -q Server/test_speech_api.py`
from the repository root (or copy the test next to `speech_api.py`). These tests
cover transparent Kokoro proxying, discovery, Unicode preservation, voice errors,
24 kHz conversion, and honest timestamp absence. On a Mac with a test SSH tunnel,
run `Scripts/test_speech_backend.sh http://127.0.0.1:18880/v1` to exercise real
ReaderModel → speech API → muted AVAudioEngine playback and cancellation. The
harness uses disposable preferences, leaving the installed app's settings intact.
