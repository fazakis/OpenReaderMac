import base64
import json

from fastapi.testclient import TestClient
import httpx
import numpy as np
import pytest

from speech_api import create_app, language_for, language_runs, pcm24, UnsupportedSpeechCharacters, SupertonicEngine


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


@pytest.mark.parametrize("endpoint", ["/v1/audio/speech", "/dev/captioned_speech"])
def test_pdf_markers_are_removed_only_from_supertonic_synthesis_copy(server, endpoint):
    client, engine, requests = server
    original = "Two neigh\ufffebourhoods and soft\u00adhyphens. κ(x) = 1; γ = 0.15; cafe\u0301; the \x1cnal result."
    expected = "Two neighbourhoods and softhyphens. κ(x) = 1; γ = 0.15; cafe\u0301; the \x1cnal result."
    response = client.post(endpoint, json={"model": "supertonic-3", "voice": "st_f1",
                                          "input": original, "response_format": "pcm"})
    assert response.status_code == 200
    assert engine.calls == [(expected, "st_f1", "na", 1.0)]
    assert not requests  # Never fall back to Kokoro or another provider.
    assert response.headers["x-speech-text-cleanup"] == "pdf-hyphenation"
    if endpoint == "/dev/captioned_speech":
        assert response.json()["timestamps"] == []
        assert len(base64.b64decode(response.json()["audio"])) == 48000
    else:
        assert len(response.content) == 48000


@pytest.mark.parametrize("text", ["\ufffe", " \u00ad\ufffe\n", "\ufffe" * 10001])
def test_marker_only_or_original_oversize_input_does_not_synthesize(server, text):
    client, engine, requests = server
    response = client.post("/v1/audio/speech", json={"voice": "st_f1", "input": text})
    assert response.status_code == 422
    assert not engine.calls and not requests


def test_kokoro_pdf_input_is_still_forwarded_byte_for_byte(server):
    client, engine, requests = server
    body = b'{"model":"kokoro", "voice":"af_alloy", "input":"neigh\\ufffebourhoods and soft\\u00adhyphens"}'
    response = client.post("/dev/captioned_speech", content=body, headers={"content-type": "application/json"})
    assert response.status_code == 200
    assert requests[-1].content == body
    assert "x-speech-text-cleanup" not in response.headers
    assert not engine.calls


@pytest.mark.parametrize("text,expected,language", [
    ("x ≤ 1; ∆x ≥ 0; x ∈ A ∪ B; x′ ∗ y ⋆ z; ∥x∥ ↑", "x  less than or equal to  1;  delta x  greater than or equal to  0; x  is an element of  A  union  B; x prime   asterisk  y  star  z;  double vertical bar x double vertical bar   up arrow ", "na"),
    ("Η τιμή α ≤ β", "Η τιμή α  μικρότερο ή ίσο του  β", "el"),
])
def test_math_names_preserve_prose_and_greek_letters(server, text, expected, language):
    client, engine, _ = server
    response = client.post("/v1/audio/speech", json={"voice": "st_f1", "input": text, "response_format": "pcm"})
    assert response.status_code == 200
    assert engine.calls == [(expected, "st_f1", language, 1.0)]
    assert response.headers["x-speech-text-cleanup"] == "math-symbols"


def test_unsupported_characters_are_identified_without_logging_document_text(caplog):
    class RejectOnce(FakeEngine):
        def synthesize(self, *args):
            if not self.calls:
                self.calls.append(args)
                raise UnsupportedSpeechCharacters(["\x1b"])
            return super().synthesize(*args)
    engine = RejectOnce()
    with TestClient(create_app(engine, transport=httpx.MockTransport(lambda r: httpx.Response(200)))) as client:
        response = client.post("/v1/audio/speech", json={"voice": "st_f1", "input": "PRIVATE-DOCUMENT-EXAMPLE e\x1bects"})
        assert response.status_code == 422
        detail = response.json()["detail"]
        assert detail["code"] == "unsupported_characters"
        assert detail["codepoints"] == ["U+001B"]
        assert "Select screen region" in detail["message"]
        assert "PRIVATE-DOCUMENT-EXAMPLE" not in response.text + caplog.text
        assert "U+001B" in caplog.text
        # Validation failures must release the synthesis slot.
        assert client.post("/v1/audio/speech", json={"voice": "st_f1", "input": "Valid", "response_format": "pcm"}).status_code == 200


def test_real_engine_preflight_stops_before_inference_for_unsupported_input():
    from types import SimpleNamespace
    engine = object.__new__(SupertonicEngine)
    engine.tts = SimpleNamespace(model=SimpleNamespace(text_processor=SimpleNamespace(validate_text=lambda text: (False, ["\x1b"]))))
    with pytest.raises(UnsupportedSpeechCharacters) as error:
        engine.synthesize("e\x1bects", "st_f1", "en", 1)
    assert error.value.codepoints == ["U+001B"]


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
