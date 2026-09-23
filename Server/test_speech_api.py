import base64
import json

from fastapi.testclient import TestClient
import httpx
import numpy as np
import pytest

from speech_api import create_app, language_for, language_runs, pcm24


class FakeEngine:
    def __init__(self):
        self.calls = []

    def synthesize(self, *args):
        self.calls.append(args)
        return b"\x01\x00" * 24000


class UpstreamStream(httpx.AsyncByteStream):
    async def __aiter__(self):
        yield b"original-"
        yield b"kokoro-bytes"


@pytest.fixture
def server():
    engine = FakeEngine()
    requests = []

    def upstream(req):
        requests.append(req)
        if req.url.path.endswith("voices"):
            return httpx.Response(200, json={"voices": [{"id": "af_alloy", "name": "af_alloy"}]})
        if req.url.path.endswith("models"):
            return httpx.Response(200, json={"data": [{"id": "kokoro"}]})
        return httpx.Response(200, stream=UpstreamStream(), headers={"content-type": "audio/pcm"})

    with TestClient(create_app(engine, transport=httpx.MockTransport(upstream))) as client:
        yield client, engine, requests


def test_english_is_forwarded_unchanged(server):
    client, engine, requests = server
    body = {"model": "kokoro", "voice": "af_alloy", "input": "Exact original English.", "return_timestamps": True}
    response = client.post("/dev/captioned_speech", json=body)
    assert response.content == b"original-kokoro-bytes"
    assert json.loads(requests[-1].content) == body
    assert not engine.calls


@pytest.mark.parametrize("text,lang", [("Καλημέρα κόσμε.", "el"), ("Καλημέρα world.", "na"), ("Hello world.", "na")])
def test_multilingual_preserves_text_and_pcm(server, text, lang):
    client, engine, requests = server
    response = client.post("/v1/audio/speech", json={"model": "supertonic-3", "voice": "st_f1", "input": text, "response_format": "pcm"})
    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/pcm"
    assert response.headers["x-sample-rate"] == "24000"
    assert len(response.content) == 48000
    assert engine.calls == [(text, "st_f1", lang, 1.0)]
    assert not requests


def test_no_fabricated_word_timestamps(server):
    client, _, _ = server
    packet = client.post("/dev/captioned_speech", json={"voice": "st_f1", "input": "Ελληνικά", "response_format": "pcm"}).json()
    assert packet["timestamps"] == []
    assert packet["audio_format"] == "audio/pcm"
    assert len(base64.b64decode(packet["audio"])) == 48000


def test_discovery_and_models(server):
    client, _, _ = server
    caps = client.get("/v1/capabilities").json()
    assert caps["greek"] and caps["mixed_greek_english"]
    assert not caps["greek_word_timestamps"]
    assert len(client.get("/v1/audio/voices").json()["voices"]) == 11
    assert client.get("/v1/models").json()["data"][-1]["id"] == "supertonic-3"


@pytest.mark.parametrize("body", [
    {"input": "Ελληνικά", "voice": "af_alloy"},
    {"input": "Ελληνικά", "voice": "st_unknown", "model": "supertonic-3"},
    {"input": "Ελληνικά", "voice": "st_f1", "speed": 0},
    {"input": "Ελληνικά", "voice": "st_f1", "response_format": "invalid"},
    {"input": "", "voice": "st_f1"},
])
def test_invalid_requests_do_not_synthesize_or_fall_back(server, body):
    client, engine, requests = server
    assert client.post("/v1/audio/speech", json=body).status_code == 422
    assert not engine.calls and not requests


def test_resampling_produces_exact_24khz_s16le_and_clips():
    assert len(pcm24(np.ones(44100), 44100)) == 48000
    assert np.frombuffer(pcm24(np.array([-2., 2.]), 24000), dtype="<i2").tolist() == [-32767, 32767]
    with pytest.raises(ValueError):
        pcm24(np.array([np.nan]), 24000)


def test_polytonic_and_explicit_english_language():
    assert language_for("Ἑλληνικά") == "el"
    assert language_for("Hello", "a") == "en"


def test_mixed_language_runs_preserve_every_character_and_force_pronunciation():
    text = "Καλημέρα! This is OpenReader. Διαβάζουμε ελληνικά and English, 12.5%."
    runs = language_runs(text)
    assert "".join(part for part, _ in runs) == text
    assert runs == [("Καλημέρα! ", "el"), ("This is OpenReader. ", "en"),
                    ("Διαβάζουμε ελληνικά ", "el"), ("and English, 12.5%.", "en")]
    for source in [" API στα Ελληνικά!", "👋 Γεια API.", "Ἑλληνικά and English", "Hello", "Ελληνικά", "123 45"]:
        assert "".join(part for part, _ in language_runs(source)) == source
