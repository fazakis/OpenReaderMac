import base64
import json

from fastapi.testclient import TestClient
import httpx
import numpy as np
import pytest

from speech_api import create_app, language_for, language_runs, pcm24, UnsupportedSpeechCharacters, SupertonicEngine, repair_pdf_ligatures, prepare_supertonic_text


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
    expected = "Two neighbourhoods and softhyphens. κ(x) = 1; γ = 0.15; cafe\u0301; the final result."
    response = client.post(endpoint, json={"model": "supertonic-3", "voice": "st_f1",
                                          "input": original, "response_format": "pcm"})
    assert response.status_code == 200
    assert engine.calls == [(expected, "st_f1", "na", 1.0)]
    assert not requests  # Never fall back to Kokoro or another provider.
    assert response.headers["x-speech-text-cleanup"] == "pdf-hyphenation,pdf-ligatures"
    if endpoint == "/dev/captioned_speech":
        assert response.json()["timestamps"] == []
        assert len(base64.b64decode(response.json()["audio"])) == 48000
    else:
        assert len(response.content) == 48000


@pytest.mark.parametrize("text", ["\ufffe", " \u00ad\ufffe\n", "\ufffe" * 10001, "\x02", " \x02\u00ad\ufffe\n"])
def test_marker_only_or_original_oversize_input_does_not_synthesize(server, text):
    client, engine, requests = server
    response = client.post("/v1/audio/speech", json={"voice": "st_f1", "input": text})
    assert response.status_code == 422
    assert not engine.calls and not requests


def test_kokoro_pdf_input_is_still_forwarded_byte_for_byte(server):
    client, engine, requests = server
    body = b'{"model":"kokoro", "voice":"af_alloy", "input":"neigh\\ufffebourhoods and soft\\u00adhyphens \\u0002 \\u0012 \\u0013 \\u0015 \\u0088"}'
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


@pytest.mark.parametrize("original,expected", [
    ("e\x1bects, di\x1berences, o\x1bers", "effects, differences, offers"),
    ("critical-di\x1berence, o\x1b-the-shelf, trade-o\x1bs", "critical-difference, off-the-shelf, trade-offs"),
    ("\x1cnal, classi\x1ccation, work\x1dow, e\x1ecient, shu\x1fed", "final, classification, workflow, efficient, shuffled"),
    ("E\x1bect and E\x1bECT", "Effect and EFFECT"),
    ("Greek κ and Ελληνικά stay intact.", "Greek κ and Ελληνικά stay intact."),
])
def test_dictionary_checked_legacy_ligatures(original, expected):
    assert repair_pdf_ligatures(original) == expected


@pytest.mark.parametrize("text", ["\x1b", "red\x1bblue", "zz\x1byy", "\x1b[31mred", "α\x1bβ", "red\x1cblue"])
def test_unknown_words_controls_and_escapes_are_not_guessed(text):
    assert repair_pdf_ligatures(text) == text


@pytest.mark.parametrize("endpoint", ["/v1/audio/speech", "/dev/captioned_speech"])
def test_pdf_ff_error_is_repaired_before_synthesis(server, endpoint):
    client, engine, requests = server
    response = client.post(endpoint, json={"voice": "st_f1", "input": "The e\x1bects di\x1ber; κ = 1.", "response_format": "pcm"})
    assert response.status_code == 200
    assert engine.calls == [("The effects differ; κ = 1.", "st_f1", "na", 1.0)]
    assert response.headers["x-speech-text-cleanup"] == "pdf-ligatures"
    assert not requests


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


@pytest.mark.parametrize("marker", ["\x02", "\ufffe", "\u00ad"])
@pytest.mark.parametrize("endpoint", ["/v1/audio/speech", "/dev/captioned_speech"])
def test_pdf_extraction_variants_before_synthesis(server, marker, endpoint):
    client, engine, upstream = server
    text = f"Two neigh{marker}bourhoods; κ = 1. Καλημέρα."
    response = client.post(endpoint, json={"model": "supertonic-3", "voice": "st_f1", "input": text, "response_format": "pcm"})
    assert response.status_code == 200
    assert engine.calls[0][0] == "Two neighbourhoods; κ = 1. Καλημέρα."
    assert response.headers["x-speech-text-cleanup"] == "pdf-hyphenation"
    assert not upstream


@pytest.mark.parametrize("source,expected", [
    ("Scores \x12x + y\x13.", "Scores (x + y)."),
    ("Range 1\x155, left\x15right.", "Range 1–5, left–right."),
    ("\x88 A list item.", "• A list item."),
    ("\x12", "("),  # App sentence boundaries can isolate a delimiter.
    ("\x13", ")"),
    ("\x15", "–"),
    ("\x88", "•"),
])
def test_verified_legacy_punctuation_including_isolated_chunks(source, expected):
    assert prepare_supertonic_text(source) == (expected, ["pdf-punctuation"])


def test_combined_pdf_artifacts_are_handled_in_one_request(server):
    client, engine, _ = server
    source = "\x88 The e\x1bects in neigh\x02bourhoods, pages 1\x153: \x12κ ≤ 1\x13."
    response = client.post("/v1/audio/speech", json={"voice": "st_f1", "input": source, "response_format": "pcm"})
    assert response.status_code == 200
    assert engine.calls[0][0] == "• The effects in neighbourhoods, pages 1–3: (κ  less than or equal to  1)."
    assert response.headers["x-speech-text-cleanup"] == "pdf-hyphenation,pdf-punctuation,pdf-ligatures,math-symbols"


def test_no_general_control_purge_or_unrelated_text_rewriting():
    # Unknown glyph encodings remain visible to validation. Normal Greek,
    # whitespace, punctuation, mathematical letters and numbers are untouched.
    source = "\x00\x01\x03\x04\x07\x0e\x11\x14\x16\x17\x18\x19\x1a\x7f Hello\tκόσμε\r\nα = 0.5 (x-y)!"
    assert prepare_supertonic_text(source) == (source, [])
