# Combat and planning audio

Ronald approved the original nine cues for integration. The filenames in this directory are runtime assets at `res://assets/audio/`. The eight Mirli WAVs are exact copies of the accepted auditions, not fresh generations. The pencil runtime cut removes audition padding from a separately preserved master.

The revised ten-cue audition is also approved for integration. Its runtime WAVs
are in `approved_undead/`, including Ring of Sparks and the user-supplied
Wasn't Me. See that directory's provenance record for source and processing
details. Stock Summon Skeleton uses its new recording; `bone_summon.wav`
remains the generic custom summon fallback.

## Mirli cues

Model: `audiocpp-stable-audio-3-sfx` in the local Mirli Soundbox library, originally `~/.mirli/sounds/<ID>.wav`. Generation metadata came from the library catalog. Commercial release is **not cleared**. Any commercial use is conditional on confirming the applicable model/checkpoint and output terms and meeting their requirements. Approval to integrate these trials does not establish rights or commercial clearance.

| Runtime WAV | Mirli ID | Seed | Positive prompt |
| --- | --- | ---: | --- |
| `shield_strike.wav` | `15c6fa1a-21a8-4808-925b-3774f532a22a` | 4210 | One small leather-bound wooden shield meeting a blunt steel weapon. A short woody knock with a muted metal edge, close and dry. |
| `bow_harpoon.wav` | `65bb2b4e-b705-4d8b-aa23-2b8b4d19bd79` | 4211 | One short bowstring release into a small wood target. Restrained string twang then a compact dry wooden thunk; close foley. |
| `magical_blast.wav` | `5ca83c5b-265c-499a-b540-cc116bd7da85` | 6813 | Single fantasy spell hit, like the air being punched by a giant felt-covered mallet. Immediate low hollow whump with a brief flutter of displaced air, tight dry finish. One close, rounded, weighty impact. No windup. |
| `bone_summon.wav` | `557d91ed-9fcf-4f19-86ad-ce413d9dc78e` | 4213 | A tiny handful of dry bones snapping neatly together, two or three hollow clacks at slightly different pitches. Close dry sound. |
| `rope_pull.wav` | `69da03a6-d54a-4562-8fcb-da926196f9aa` | 4214 | One short length of coarse hemp rope whipping taut under tension, fiber swish into a small tight snap. Close dry foley. |
| `war_drum.wav` | `589c795a-38ed-4fbe-ae9e-561b92a806d2` | 4215 | One muted hide drum struck with a padded mallet. Compact round woody resonance, dry and short. |
| `light_footfall.wav` | `dc10fbee-a494-4a21-aa00-e81e04e69c93` | 4201 | One light leather shoe footfall on packed earth, a soft short scuff into a muted sole contact. Dry, close, isolated, small in scale. Silence after the single step. |
| `potion_smash.wav` | `2ff60d16-fed5-4fa3-9b09-b3d6583d730e` | 4202 | A single small thin glass potion vial smashes on a flagstone. A short brittle glass crack followed immediately by a tiny wet splat and two settling glass grains. Dry close foley, quiet room, compact one-shot game effect. |

Negative prompts:

- Shield through drum, except the replacement Blast: `music, ambient background, voice, long reverb, repeated hits`
- Force Blast: `music, voice, long reverb, gunfire, cinematic boom, repeated attacks, ambient bed`
- Footfall: `marching, multiple steps, stomp, bass boom, music, ambience, reverb`
- Potion: `explosion, large window, prolonged tinkling, reverb, music`

All eight are 44.1 kHz stereo PCM24 masters. Ronald selected the Force audition to replace the original Blast. The [original recording](masters/magical_blast_original.wav) is preserved outside the runtime importer (Mirli ID `6b5e7e10-7a18-40ef-bedb-3aa550293eb7`, seed `4212`).

## Pencil provenance

The [accepted master](masters/pencil_flick.wav) is the single procedural pencil audition originally at `.lore/local/audio/pencil-flick.wav`. It is not a Mirli asset. Ronald supplied the original recipe (Python standard library, random seed `38`), verified against the accepted bytes:

```python
import math, random, struct, wave

r = 44100
starts = [0.15]
x = [0] * int((starts[-1] + 0.45) * r)
rng = random.Random(38)
for start in starts:
    a = b = 0.0
    j = int(start * r)
    n = int(0.042 * r)
    for i in range(n):
        a += 0.31 * (rng.uniform(-1, 1) - a)
        b += 0.105 * (a - b)
        u = i / (n - 1)
        env = (1 - math.exp(-i / (r * 0.0035))) * math.exp(-i / (r * 0.011)) * (1 - u * u)
        x[j + i] = round(20000 * (a - b) * env)
with wave.open("pencil_flick.wav", "wb") as out:
    out.setparams((1, 2, r, 0, "NONE", "not compressed"))
    out.writeframes(struct.pack(f"<{len(x)}h", *x))
```

To make the runtime WAV, remove exactly the first 6,615 zero frames (150 ms) from the master using `wave`, then write the remaining 19,845 frames with the same PCM16 mono 44.1 kHz format. No other samples change. The first nonzero runtime sample is one frame from the start. `masters/.gdignore` keeps the duplicate master out of Godot's importer.

## Import verification

Godot 4.7.2 loaded all nine runtime assets as 44.1 kHz `AudioStreamWAV` resources. The `.import` sidecars disable extra compression, normalization and trimming. Godot uses the high 16 bits of each source PCM24 sample, preserving frame count and channel order; the source 24-bit WAVs stay intact and need no separate PCM16 files. Pencil imports without changing sample bytes. If Godot previously imported these files with default settings, explicitly reimport the audio files to refresh its cache.

SHA-256:

```text
ceba8f5867a8509f439db70f54e31bb4c9b0e16da0f6db3f2256ef1bec1f0c27  bone_summon.wav
ec0af0f00db958e1884cd75fef44786b328965d1ad04a7c82e84f19de7edb76c  bow_harpoon.wav
76cbcaa8e9b44d9ae69d882245a47969ae7864fb2d8bdb7c562c5f895e68bf4f  light_footfall.wav
899127378a5c79ec12bb35e0cdbbbe42cf7eafd8f8123dd6117a9944f22a7012  magical_blast.wav
b9f012aacd3a52d42dfdfce2e830702141bfb64c3e40dda4756b8cb9248d068a  masters/magical_blast_original.wav
b7338971af7a224f4ad59f3d74d9c2300257c6aba4bab21759ed11285050e073  pencil_flick.wav
7f0b7e28159a53448ca2f021fd0ebfc780b1d6000a6371063ebefc5d93e2207f  potion_smash.wav
a32ba8ebec09c7e3878bcddaecaf34599f76ecdf2dba5a8718c9191195413abb  rope_pull.wav
2130d43d0fc935375d8d16244b18fed3f720c95733d81a0a29781aab561296fa  shield_strike.wav
66b556d0febea5c42d50e3ae0bd60cec1076ea677043f70a95225b826bfc0770  war_drum.wav
13736c2872965d9a7e16b4d1450f63ec68bd97719c1a065bf4f03e4d725747b4  masters/pencil_flick.wav
```
