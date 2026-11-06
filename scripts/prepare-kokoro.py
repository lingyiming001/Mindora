#!/usr/bin/env python3
"""Prepare the pinned Chinese/English Kokoro model for the Mindora app bundle."""
import argparse
import fcntl
import hashlib
from pathlib import Path
import shutil
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
MODEL = "kokoro-multi-lang-v1_1"
URL = f"https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/{MODEL}.tar.bz2"
SHA256 = "b78e1ac42b852e839cceaafbe88f66806bf5860992d1d7b9a3f2ad1198427aed"
REQUIRED = ("model.onnx", "voices.bin", "tokens.txt", "espeak-ng-data", "lexicon-us-en.txt",
            "lexicon-zh.txt", "date-zh.fst", "number-zh.fst", "phone-zh.fst", "LICENSE")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="Use an existing copy of the official archive.")
    args = parser.parse_args()
    cache = ROOT / ".build/kokoro"
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / "prepare.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        prepare(cache, args.archive)


def prepare(cache: Path, supplied_archive):
    destination = ROOT / "Resources/Kokoro"
    marker = destination / ".archive-sha256"
    if (marker.is_file() and marker.read_text() == SHA256
            and all((destination / name).exists() for name in REQUIRED)):
        return

    with tempfile.TemporaryDirectory(prefix="prepare-", dir=cache) as temporary:
        stage = Path(temporary)
        archive = supplied_archive or cache / "model.tar.bz2"
        download = not archive.exists() and supplied_archive is None
        if download:
            print("Downloading the offline Kokoro model…", flush=True)
            urllib.request.urlretrieve(URL, stage / archive.name)
            source = stage / archive.name
        else:
            source = archive

        digest = hashlib.sha256()
        with source.open("rb") as incoming:
            for block in iter(lambda: incoming.read(1024 * 1024), b""):
                digest.update(block)
        if digest.hexdigest() != SHA256:
            raise ValueError(f"Kokoro archive checksum mismatch: {source}")
        if download:
            source.replace(archive)

        with tarfile.open(archive, "r:bz2") as model_archive:
            for member in model_archive:
                path = Path(member.name)
                if path.is_absolute() or ".." in path.parts or path.parts[:1] != (MODEL,):
                    raise ValueError(f"Unexpected archive path: {member.name}")
                target = stage / path
                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                elif member.isfile():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with model_archive.extractfile(member) as incoming, target.open("wb") as outgoing:
                        shutil.copyfileobj(incoming, outgoing)
                else:
                    raise ValueError(f"Unexpected archive member: {member.name}")

        model = stage / MODEL
        if any(not (model / name).exists() for name in REQUIRED):
            raise ValueError("Incomplete Kokoro model archive")
        for license_file in (ROOT / "Vendor/KokoroRuntime").glob("*-LICENSE"):
            shutil.copy2(license_file, model)
        (model / marker.name).write_text(SHA256)
        if destination.exists():
            shutil.rmtree(destination)
        model.rename(destination)
        print(f"Prepared Kokoro model in {destination}")


if __name__ == "__main__":
    main()
