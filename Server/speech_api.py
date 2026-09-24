"""Loopback compatibility adapter: unchanged Kokoro plus local Supertonic 3."""
import asyncio
import base64
from contextlib import asynccontextmanager
from functools import lru_cache
import json
import logging
import math
import os
import re
import subprocess

import anyio
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response, StreamingResponse
import httpx
import numpy as np
from scipy.signal import resample_poly
from starlette.background import BackgroundTask

GREEK = re.compile(r"[\u0370-\u03ff\u1f00-\u1fff]")
LATIN = re.compile(r"[A-Za-z]")
VOICES = [f"st_{gender}{i}" for gender in ("f", "m") for i in range(1, 6)]
SAMPLE_RATE = 24000
HOP_HEADERS = {"connection", "keep-alive", "transfer-encoding", "content-length"}
# PDFium's range API emits U+FFFE for discretionary hyphens; its bounded-text
# and character APIs expose the same positions as U+0002. Include both paths.
PDF_HYPHENATION_MARKERS = str.maketrans({"\ufffe": None, "\x02": None, "\u00ad": None})
# Legacy TeX PDF glyph slots seen in otherwise ordinary extracted prose/math.
# This explicit compatibility table is not a blanket purge of control codes.
PDF_PUNCTUATION = str.maketrans({"\x12": "(", "\x13": ")", "\x15": "–", "\x88": "•"})
PDF_LIGATURES = str.maketrans(dict(zip("\x1b\x1c\x1d\x1e\x1f", ["ff", "fi", "fl", "ffi", "ffl"])))
BROKEN_LATIN_WORD = re.compile(r"(?<!\w)[A-Za-z\x1b-\x1f]+(?:[-'][A-Za-z\x1b-\x1f]+)*(?!\w)")
MATH_NAMES = {
    "′": ("prime", "τόνος"), "↑": ("up arrow", "βέλος προς τα πάνω"),
    "∆": ("delta", "δέλτα"), "∈": ("is an element of", "ανήκει στο"),
    "∗": ("asterisk", "αστερίσκος"), "∥": ("double vertical bar", "διπλή κάθετη γραμμή"),
    "∪": ("union", "ένωση"), "≤": ("less than or equal to", "μικρότερο ή ίσο του"),
    "≥": ("greater than or equal to", "μεγαλύτερο ή ίσο του"), "⋆": ("star", "αστέρι"),
}
logger = logging.getLogger("openreader.speech")


@lru_cache(maxsize=1)
def english_dictionary():
    import cmudict
    return frozenset(word.casefold() for word in cmudict.words())


def repair_pdf_ligatures(text):
    def repair(match):
        word = match.group()
        if not LATIN.search(word) or not any(char in word for char in "\x1b\x1c\x1d\x1e\x1f"):
            return word
        candidate = word.translate(PDF_LIGATURES)
        key = candidate.casefold()
        vocabulary = english_dictionary()
        if key not in vocabulary and not all(part in vocabulary for part in key.split("-")):
            return word
        # These codes are legacy TeX ligatures only in a recognized Latin word.
        # Unknown words, standalone controls and terminal escapes stay untouched.
        return candidate.upper() if word.isupper() else candidate
    return BROKEN_LATIN_WORD.sub(repair, text)


def prepare_supertonic_text(text):
    cleaned = text.translate(PDF_HYPHENATION_MARKERS)
    changes = ["pdf-hyphenation"] if cleaned != text else []
    punctuation = cleaned.translate(PDF_PUNCTUATION)
    if punctuation != cleaned:
        changes.append("pdf-punctuation")
        cleaned = punctuation
    repaired = repair_pdf_ligatures(cleaned)
    if repaired != cleaned:
        changes.append("pdf-ligatures")
        cleaned = repaired
    # Speak literal operator names, without translating prose or interpreting
    # equations. English prose uses English names; Greek-only prose uses Greek.
    language = 1 if GREEK.search(cleaned) and not LATIN.search(cleaned) else 0
    if any(char in cleaned for char in MATH_NAMES):
        cleaned = "".join(" " + MATH_NAMES[char][language] + " " if char in MATH_NAMES else char for char in cleaned)
        changes.append("math-symbols")
    return cleaned, changes


class UnsupportedSpeechCharacters(ValueError):
    def __init__(self, characters):
        self.codepoints = [f"U+{ord(char):04X}" for char in sorted(set(characters))][:16]


def language_for(text, requested=None):
    if GREEK.search(text):
        return "na" if LATIN.search(text) else "el"
    aliases = {"a": "en", "b": "en", "e": "es", "f": "fr", "h": "hi", "i": "it", "p": "pt", "j": "ja"}
    return aliases.get(requested, requested) if requested not in (None, "auto", "mixed") else "na"


def language_runs(text, requested=None):
    if not (GREEK.search(text) and LATIN.search(text)):
        return [(text, language_for(text, requested))]
    runs, start, current = [], 0, None
    for index, char in enumerate(text):
        language = "el" if GREEK.fullmatch(char) and char.isalpha() else "en" if LATIN.fullmatch(char) else None
        if language is None:
            continue
        if current is not None and language != current:
            runs.append((text[start:index], current))
            start = index
        current = language
    runs.append((text[start:], current or "na"))
    return runs


def pcm24(wav, rate):
    samples = np.asarray(wav).reshape(-1)
    if not np.isfinite(samples).all():
        raise ValueError("Invalid model audio")
    divisor = math.gcd(int(rate), SAMPLE_RATE)
    if rate != SAMPLE_RATE:
        samples = resample_poly(samples, SAMPLE_RATE // divisor, int(rate) // divisor)
    return (np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes()


class SupertonicEngine:
    def __init__(self, model_dir):
        from supertonic import TTS
        self.tts = TTS(model="supertonic-3", model_dir=model_dir, auto_download=False,
                       intra_op_num_threads=4, inter_op_num_threads=1)
        self.styles = {name: self.tts.get_voice_style(name[3:].upper()) for name in VOICES}

    def synthesize(self, text, voice, language, speed):
        valid, unsupported = self.tts.model.text_processor.validate_text(text)
        if not valid:
            raise UnsupportedSpeechCharacters(unsupported)
        audio = []
        for fragment, lang in language_runs(text, language):
            wav, _ = self.tts.synthesize(fragment, voice_style=self.styles[voice], lang=lang,
                                         speed=speed, total_steps=8, verbose=False)
            audio.append(pcm24(wav, self.tts.sample_rate))
        return b"".join(audio)


def encode(pcm, fmt):
    formats = {"mp3": ("libmp3lame", "mp3", "audio/mpeg"),
               "wav": ("pcm_s16le", "wav", "audio/wav"),
               "flac": ("flac", "flac", "audio/flac"),
               "opus": ("libopus", "ogg", "audio/ogg"),
               "aac": ("aac", "adts", "audio/aac")}
    if fmt == "pcm":
        return pcm, "audio/pcm"
    if fmt not in formats:
        raise HTTPException(422, "Unsupported audio format")
    codec, container, mime = formats[fmt]
    result = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "s16le",
                             "-ar", str(SAMPLE_RATE), "-ac", "1", "-i", "pipe:0",
                             "-c:a", codec, "-f", container, "pipe:1"],
                            input=pcm, capture_output=True, check=True, timeout=30)
    return result.stdout, mime


def create_app(engine=None, upstream=None, transport=None):
    @asynccontextmanager
    async def lifespan(app):
        app.state.engine = engine or await anyio.to_thread.run_sync(
            SupertonicEngine, os.environ["SUPERTONIC_MODEL_DIR"])
        app.state.queue = asyncio.Semaphore(1)
        async with httpx.AsyncClient(base_url=upstream or os.getenv("KOKORO_URL", "http://127.0.0.1:8881"),
                                    timeout=180, follow_redirects=False, transport=transport) as client:
            app.state.client = client
            yield

    app = FastAPI(title="OpenReader multilingual speech", version="1.5.0", lifespan=lifespan)

    @app.get("/health")
    async def health(request: Request):
        try:
            response = await request.app.state.client.get("/health", timeout=5)
            ready = response.status_code == 200
        except httpx.HTTPError:
            ready = False
        return JSONResponse({"status": "healthy" if ready else "degraded", "kokoro": ready,
                             "supertonic": True}, status_code=200 if ready else 503)

    @app.get("/v1/capabilities")
    async def capabilities():
        return {"version": 1, "greek": True, "mixed_greek_english": True,
                "sample_rate": SAMPLE_RATE, "greek_model": "supertonic-3",
                "greek_voices": VOICES, "greek_word_timestamps": False}

    @app.get("/v1/audio/voices")
    async def voices(request: Request):
        try:
            response = await request.app.state.client.get("/v1/audio/voices")
            response.raise_for_status()
            existing = response.json()["voices"]
        except (httpx.HTTPError, ValueError, KeyError):
            raise HTTPException(502, "Kokoro voice discovery unavailable") from None
        return {"voices": existing + [{"id": v, "name": f"Supertonic 3 {v[3:].upper()} (Greek / English)"} for v in VOICES]}

    async def proxy(request, body):
        client = request.app.state.client
        headers = {k: v for k, v in request.headers.items() if k.lower() not in HOP_HEADERS | {"host"}}
        path = request.url.path + ("?" + request.url.query if request.url.query else "")
        req = client.build_request(request.method, path, content=body, headers=headers)
        try:
            response = await client.send(req, stream=True)
        except httpx.HTTPError:
            raise HTTPException(502, "Kokoro speech service unavailable") from None
        return StreamingResponse(response.aiter_raw(), status_code=response.status_code,
                                 headers={k: v for k, v in response.headers.items() if k.lower() not in HOP_HEADERS},
                                 background=BackgroundTask(response.aclose))

    @app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD"])
    async def route(request: Request, path: str):
        body = await request.body()
        if len(body) > 2_000_000:
            raise HTTPException(413, "Request too large")
        if request.method != "POST" or path not in ("v1/audio/speech", "dev/captioned_speech"):
            if path == "v1/models" and request.method == "GET":
                response = await request.app.state.client.get("/v1/models")
                if response.status_code != 200:
                    return Response(response.content, response.status_code, media_type="application/json")
                data = response.json()
                data["data"].append({"id": "supertonic-3", "object": "model", "owned_by": "local"})
                return data
            return await proxy(request, body)
        try:
            payload = json.loads(body)
            if not isinstance(payload, dict):
                raise ValueError()
        except (ValueError, TypeError):
            raise HTTPException(400, "Expected a JSON object") from None
        text = payload.get("input", "")
        if not isinstance(text, str):
            raise HTTPException(422, "input must be text")
        voice = payload.get("voice", "")
        if not isinstance(voice, str) or not isinstance(payload.get("model", "kokoro"), str):
            raise HTTPException(422, "model and voice must be strings")
        if payload.get("lang_code") is not None and not isinstance(payload["lang_code"], str):
            raise HTTPException(422, "lang_code must be a string")
        use_supertonic = payload.get("model") == "supertonic-3" or voice in VOICES
        if not use_supertonic:
            if GREEK.search(text):
                raise HTTPException(422, "Greek requires model supertonic-3 and a st_f1..st_m5 voice")
            return await proxy(request, body)
        if voice not in VOICES:
            raise HTTPException(422, "Select an available Supertonic voice")
        if not text.strip() or len(text) > 10000:
            raise HTTPException(422, "input must contain 1–10000 characters")
        # Clean only the Supertonic synthesis copy, never the reader/source text
        # or proxied Kokoro requests. Only documented compatibility mappings apply.
        speech_text, cleanup = prepare_supertonic_text(text)
        if not speech_text.strip():
            raise HTTPException(422, "input contains no speakable text after PDF marker cleanup")
        try:
            speed = float(payload.get("speed", 1))
            if not math.isfinite(speed) or not 0.5 <= speed <= 2:
                raise ValueError()
        except (ValueError, TypeError):
            raise HTTPException(422, "speed must be between 0.5 and 2") from None
        fmt = payload.get("response_format", "mp3")
        if fmt not in ("pcm", "wav", "mp3", "flac", "opus", "aac"):
            raise HTTPException(422, "Unsupported audio format")
        captioned = path == "dev/captioned_speech"
        if captioned and fmt != "pcm":
            raise HTTPException(422, "Captioned speech requires PCM")
        try:
            await asyncio.wait_for(request.app.state.queue.acquire(), timeout=15)
        except asyncio.TimeoutError:
            raise HTTPException(429, "Speech engine busy; try again later") from None
        try:
            if await request.is_disconnected():
                return Response(status_code=499)
            pcm = await anyio.to_thread.run_sync(request.app.state.engine.synthesize,
                speech_text, voice, language_for(speech_text, payload.get("lang_code")), speed)
        except UnsupportedSpeechCharacters as error:
            # Log only code points, never document text, credentials, or audio.
            logger.warning("speech_validation model=supertonic-3 code=unsupported_characters codepoints=%s", ",".join(error.codepoints))
            raise HTTPException(422, {"code": "unsupported_characters", "codepoints": error.codepoints,
                "message": "Supertonic cannot read these characters: " + ", ".join(error.codepoints)
                + ". For broken PDF font text, use Select screen region or corrected pasted text."}) from None
        except ValueError:
            logger.warning("speech_validation model=supertonic-3 code=invalid_model_input")
            raise HTTPException(422, "The model cannot synthesize this text or language") from None
        finally:
            request.app.state.queue.release()
        headers = {"X-Sample-Rate": str(SAMPLE_RATE), "X-Speech-Model": "supertonic-3", "X-Speech-Voice": voice}
        if cleanup:
            headers["X-Speech-Text-Cleanup"] = ",".join(cleanup)
        if captioned:
            packet = {"audio": base64.b64encode(pcm).decode(), "audio_format": "audio/pcm", "timestamps": []}
            return Response(json.dumps(packet) + "\n", media_type="application/json", headers=headers)
        audio, mime = await anyio.to_thread.run_sync(encode, pcm, fmt)
        return Response(audio, media_type=mime, headers=headers)

    return app


app = create_app()
