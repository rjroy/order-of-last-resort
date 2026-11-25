# Approved undead action cues

Ronald approved the revised full audition reel (13.077 s, SHA-256
`1e17466131281f3cda8f46650ad8a5be362c70d12aa6f04b986f9b8fd5452670`).
This directory contains the nine exact Mirli audition cuts and Ronald’s supplied
`wasnt-me.wav`, copied without processing as `wasnt_me.wav`. The supplied take
was checked against the download and against its reel slot at the reel’s
16-bit precision. The nine other reel slots match the shipped WAV PCM exactly.
The rejected Mirli Wasn’t Me is not included.

The Mirli recordings used the local `audiocpp-stable-audio-3-sfx` model.
`masters/originals/` holds the nine unedited WAVs and their catalog metadata,
including source UUIDs, prompts, negative prompts, seeds and source hashes.
`masters/.gdignore` excludes the entire subtree from Godot. The shipped WAVs
do not require those masters, Mirli, Python, FFmpeg, or the audition directory.
Approval covers this game’s cue selection, not commercial release clearance.

## Reproduce the Mirli cuts

From this directory, with Python 3.14, NumPy 2.5.4 and FFmpeg n9.0.2:

```sh
out=$(mktemp -d /tmp/opencode/undead-rebuilt.XXXXXX)
python -B masters/rebuild.py "$out"
for cut in "$out"/*.wav; do cmp "$cut" "./$(basename "$cut")" || exit 1; done
```

The recipe trims source padding, fades the edges and adjusts each cue toward
−20 dBFS strongest 100 ms RMS with a −2 dBFS sample-peak ceiling. Grave Bell
uses the first 575 ms of one recording with a shaped decay. Summon Skeleton
and Raise Dead start with that same edit, at reduced gain, then bring in
their own body takes after 110 ms and 170 ms respectively. No other cue uses
the bell. The nine rebuilds matched the shipped files byte for byte.
`wasnt_me.wav` is already the original, not a generated derivative.

## Import verification

All ten committed sidecars disable compression, forced conversion, trimming,
normalization and looping. Godot 4.7.2 loaded all ten as 44.1 kHz stereo
`AudioStreamWAV` resources with looping disabled. It preserved every PCM16
sample for the nine Mirli edits. It uses the high 16 bits of every PCM24
sample for `wasnt_me.wav`, without changing the original WAV on disk.
A fresh isolated import left all sidecars unchanged and imported no masters.

To reproduce the import check from this directory:

```sh
sandbox=$(mktemp -d /tmp/opencode/undead-import.XXXXXX)
mkdir -p "$sandbox/project/assets/audio" "$sandbox"/xdg/{cache,config,data}
cp -a . "$sandbox/project/assets/audio/approved_undead"
cp masters/verify_import.gd "$sandbox/project/"
printf 'config_version=5\n\n[application]\nconfig/name="Undead import check"\n' \
  > "$sandbox/project/project.godot"
export XDG_CACHE_HOME="$sandbox/xdg/cache" XDG_CONFIG_HOME="$sandbox/xdg/config"
export XDG_DATA_HOME="$sandbox/xdg/data"
godot --headless --path "$sandbox/project" --editor --import
godot --headless --path "$sandbox/project" --script res://verify_import.gd
```

## Accepted WAV SHA-256

```text
ae42a5ec1235cca8509314fbde9cabf89bb5e268ec893533087d8783a5061601  grave_bell.wav
dcbf2d78ff2034c68bd34cd5aa490048acd4b74dad8b6f755330a36154ea51ab  raise_dead.wav
56ca42f5741eeb7aeded1d70ba023ef5339c27435db883546c862cc0b1acefed  ring_of_sparks.wav
72e7eb6349f4695bd4759b329dc4b5bf428013ae7ffb34b5e0f89efed0a4e67d  say_hello_to_that_one.wav
79d5f8dec369579be3071dd9a4a4fdb6100154b8c9f02152a1601f9bc5e0f52e  skeleton_dont_go.wav
68a8b31c23f026f803edab792ac6cdaed0fb73e661fc4bbce92da3758b3199cd  skeleton_wave.wav
636b5b0bffff722867fc39e30bf9727b4d7ed6305f13359cf283277968906ac1  summon_skeleton.wav
7e2c689dd37b68f3c0b973d7fd7c7a12ce1a3915177f22ca476815c140dd4eb4  wasnt_me.wav
7b295183e472b12042b6086ea7c004f4c387b414a8384d40cd3cd6adf7e85a23  zombie_offer_flower.wav
a23c915658360564b56c8e26fcdac179f0532e88b7768bbe1c374b43a01a9bdd  zombie_say_hello.wav
```
