"""Offline corpus validation against the installed Supertonic character index.

Input: a JSON object mapping extraction names to arrays of strings (pages or
actual client chunks). Output contains counts and code points, never source text.
No audio, service requests, external network access, or model inference occurs.
"""
import argparse
from collections import Counter
import json

from speech_api import language_runs, prepare_supertonic_text


def audit(variants, processor):
    report = {}
    for name, chunks in variants.items():
        failed = 0
        before, after = Counter(), Counter()
        for text in chunks:
            _, bad = processor.validate_text(text)
            before.update(bad)
            speech, _ = prepare_supertonic_text(text)
            # Check exactly the fragments handed to the SDK, not just the page.
            bad = set()
            for fragment, _ in language_runs(speech):
                _, rejected = processor.validate_text(fragment)
                bad.update(rejected)
            failed += bool(bad)
            after.update(bad)
        codes = lambda counts: {f"U+{ord(c):04X}": n for c, n in sorted(counts.items())}
        report[name] = {"chunks": len(chunks), "failed": failed,
                        "before": codes(before), "after": codes(after)}
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("corpus", help="Private JSON corpus; do not commit document text")
    parser.add_argument("--indexer", required=True, help="Installed onnx/unicode_indexer.json")
    args = parser.parse_args()
    with open(args.corpus, encoding="utf-8") as f:
        variants = json.load(f)
    if not isinstance(variants, dict) or not variants or not all(
        isinstance(name, str) and isinstance(chunks, list) and chunks
        and all(isinstance(text, str) for text in chunks)
        for name, chunks in variants.items()
    ):
        parser.error("Expected a nonempty object of named, nonempty string arrays")
    from supertonic.core import UnicodeProcessor
    report = audit(variants, UnicodeProcessor(args.indexer))
    print(json.dumps(report, indent=2))
    return int(any(result["failed"] for result in report.values()))


if __name__ == "__main__":
    raise SystemExit(main())
