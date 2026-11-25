#!/usr/bin/env python3
"""Rebuild the nine approved Mirli cuts from the packaged masters."""

import argparse
from hashlib import sha256
import json
import math
from pathlib import Path
import subprocess
import wave

import numpy as np

MASTERS = Path(__file__).resolve().parent
RATE = 44100
CHANNELS = 2


def samples(ms):
    return round(ms * RATE / 1000)


def gain(db):
    return 10 ** (db / 20)


def db(value):
    return 20 * math.log10(max(float(value), 1e-12))


def decode(config):
    sid = config["id"]
    path = MASTERS / "originals" / f"{sid}.wav"
    meta = json.loads(path.with_suffix(".json").read_text())
    if meta["id"] != sid or sha256(path.read_bytes()).hexdigest() != meta["sha256"]:
        raise ValueError(f"Mismatched original: {sid}")
    raw = subprocess.run(
        ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-xerror",
         "-i", str(path), "-map", "0:a:0", "-ac", str(CHANNELS), "-ar", str(RATE),
         "-f", "f32le", "-"],
        check=True, stdout=subprocess.PIPE,
    ).stdout
    return np.frombuffer(raw, dtype="<f4").reshape(-1, CHANNELS).astype(np.float64)


def cut(x, config):
    width = samples(5)
    padded = np.pad(x, ((0, (-len(x)) % width), (0, 0)))
    rms = np.sqrt(np.mean(padded.reshape(-1, width, CHANNELS) ** 2, axis=(1, 2)))
    active = np.flatnonzero(rms >= rms.max() * gain(-30))
    start = max(0, int(active[0]) * width - samples(10))
    stop = min(len(x), (int(active[-1]) + 1) * width + samples(45))
    if "start_ms" in config:
        start = samples(config["start_ms"])
    if "end_ms" in config:
        stop = samples(config["end_ms"])
    lead = samples(config.get("fade_in_ms", 2))
    tail = samples(config.get("fade_out_ms", 24))
    if not 0 <= start < stop <= len(x) or lead + tail > stop - start:
        raise ValueError(f"Invalid edit for {config['id']}")
    y = x[start:stop].copy()
    if lead:
        y[:lead] *= np.linspace(0, 1, lead)[:, None]
    if tail:
        y[-tail:] *= np.linspace(1, 0, tail)[:, None] ** config.get("fade_out_power", 1)
    return y


def level(x):
    width = min(samples(100), len(x))
    energy = np.r_[0, np.cumsum(np.mean(x * x, axis=1))]
    strongest = np.sqrt(np.max(energy[width:] - energy[:-width]) / width)
    adjust = min(-20 - db(strongest), -2 - db(np.max(np.abs(x))))
    return x * gain(adjust)


def mix(bell, body, config):
    delay = samples(config["body_delay_ms"])
    y = np.zeros((max(len(bell), delay + len(body)), CHANNELS))
    y[:len(bell)] += bell * gain(config["bell_gain_db"])
    y[delay:delay + len(body)] += body
    return level(y)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="empty destination outside the accepted asset folder")
    output = parser.parse_args().output.resolve()
    if output.is_relative_to(MASTERS.parent):
        parser.error("destination must be outside the accepted asset folder")
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        parser.error("destination must be empty")

    recipe = json.loads((MASTERS / "recipe.json").read_text())
    stems = {key: level(cut(decode(spec), spec)) for key, spec in recipe["sources"].items()}
    for key, stem in stems.items():
        spec = recipe["summon_mix"].get(key)
        x = mix(stems["grave_bell"], stem, spec) if spec is not None else stem
        pcm = np.rint(x * 32768).astype("<i2").tobytes()
        with wave.open(str(output / f"{key}.wav"), "wb") as wav:
            wav.setparams((CHANNELS, 2, RATE, len(x), "NONE", "not compressed"))
            wav.writeframes(pcm)


if __name__ == "__main__":
    main()
