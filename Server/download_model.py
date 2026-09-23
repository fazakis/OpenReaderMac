"""Download the pinned public weights once; synthesis never downloads assets."""
import argparse
from huggingface_hub import snapshot_download

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory")
    args = parser.parse_args()
    snapshot_download(
        "supertone-oss-archive/supertonic-3",
        revision="aafc6e32416a594460b32413efc49d7fe4ce6d46",
        local_dir=args.directory,
        allow_patterns=["onnx/*", "voice_styles/*", "LICENSE", "README.md"],
    )
