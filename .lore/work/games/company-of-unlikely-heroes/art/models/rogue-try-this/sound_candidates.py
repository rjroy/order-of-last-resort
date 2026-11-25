"""Isolated cue WAVs and an audition mix. No Godot or external audio generator."""

from pathlib import Path
from math import exp, pi, sin
from struct import pack
from wave import open as wav_open
import hashlib
import random

RATE = 44100
HERE = Path(__file__).resolve().parent
GAME = HERE.parents[6] / "games/company-of-unlikely-heroes"
FOOT = GAME / "assets/audio/light_footfall.wav"
FOOT_SHA = "76cbcaa8e9b44d9ae69d882245a47969ae7864fb2d8bdb7c562c5f895e68bf4f"

# start, duration, initial/end pitch (zero = noise), gain, decay, noise smoothing.
RECIPES = {
    # Adapt the published Bonk modes, not the old recorded alibi.
    "bonk": [(0,.08,0,0,.12,28,.25),(0,.14,260,210,.16,22,0),
             (.01,.10,570,500,.06,28,0)],
    "claim": [(0,.072,190,140,.11,48,0),(0,.060,0,0,.20,50,.31),
              (.027,.09,1910,1770,.045,49,0),(.042,.073,2740,2410,.025,51,0)],
    "lift": [(0,.17,0,0,.25,11,.21),(.052,.068,0,0,.18,37,.53)],
    "cut": [(0,.035,2220,1740,.14,43,0),(0,.058,0,0,.32,43,.61),
            (.019,.092,752,330,.19,33,0),(.020,.07,1394,650,.081,47,0)],
    "bitter": [(0,.032,0,0,.20,39,.48),(.009,.08,1630,1490,.08,48,0),
               (.021,.11,0,0,.30,26,.17),(.022,.11,430,105,.20,28,0),
               (.041,.08,842,420,.07,35,0)],
}


def synth(layers):
    out = [0.] * round(RATE*max(start+dur for start,dur,*_ in layers))
    for i, (start,duration,hz,end,gain,decay,filt) in enumerate(layers):
        rng = random.Random(104729+7919*i)
        off = round(start*RATE)
        phase, noise = 0., 0.
        for j in range(min(round(RATE*duration),len(out)-off)):
            t = j/RATE
            u = t/duration
            env = min(1,t*670)*min(1,(1-u)*25)*exp(-t*decay)
            if hz:
                phase += 2*pi*(hz+(end-hz)*u)/RATE
                value = sin(phase)
            else:
                noise += filt*(rng.uniform(-1,1)-noise)
                value = noise
            out[off+j] += gain*value*env
    return out


def footfall():
    assert hashlib.sha256(FOOT.read_bytes()).hexdigest() == FOOT_SHA
    with wav_open(str(FOOT),"rb") as part:
        assert (part.getframerate(),part.getnchannels(),part.getsampwidth()) == (RATE,2,3)
        data = part.readframes(part.getnframes())
    # Audition-only mono mix. For any eventual integration use the exact original stereo WAV.
    return [
        .40*min(1, i/(6*.002*RATE)) *
        sum(int.from_bytes(data[i+j:i+j+3],"little",signed=True)/(1<<23) for j in (0,3))/2
        for i in range(0,len(data),6)
    ]


def write(path, samples):
    assert all(abs(v) < 1 for v in samples)
    with wav_open(str(path),"wb") as wav:
        wav.setparams((1,2,RATE,0,"NONE","not compressed"))
        wav.writeframes(pack(f"<{len(samples)}h",*[round(v*32767) for v in samples]))


def generate(output):
    output.mkdir(parents=True,exist_ok=True)
    samples = {name:synth(layers) for name,layers in RECIPES.items()}
    samples["land"] = footfall()
    for name, data in samples.items():
        assert 0.045 < max(map(abs,data)) < .65 and abs(data[0]) < .012
        write(output/f"{name}.wav", data)
    return samples
