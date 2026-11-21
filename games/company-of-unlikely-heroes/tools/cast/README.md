# Barnaby's Order: actor atlas recipe

From the repository root:

```sh
python games/company-of-unlikely-heroes/tools/bake_cast.py
python games/company-of-unlikely-heroes/tools/cast/test_packing.py
python games/company-of-unlikely-heroes/tools/cast/verify_cast.py
python games/company-of-unlikely-heroes/tools/cast/proof_sheet.py /tmp/opencode/cast-proof.jpg
```

The first command writes eight PNGs and `manifest.json` under `assets/cast`. `--output DIR` builds separately; `--jobs` and `--threads` control CPU use. Requires Python 3, Blender 5.2.2 LTS and ImageMagick 7 (verified with 7.1.2-34). Only the optional labeled proof uses Fontconfig. An independent full rebuild produced byte-identical PNGs and JSON on this machine. No Godot import cache or local art history is an input.

`masters.json` pins the approved native rigs under `.lore/work/games/company-of-unlikely-heroes/art/models`. Per-model READMEs there document orientation, approvals, source limitations and actions. The renderer opens each master and checks its SHA-256 before and after, without saving. Two exact strips are reused from the tracked `art/pilots/ferryman-crossing/assets`: Knight Guard and Healer Ally Heal, pinned in `takes.py`. Their original renderer is `art/pilots/ferryman-crossing/authoring/bake_sprites.py` and uses those same two masters. Other drawings come directly from the native files. Render-only review floors and lights are excluded, not unparented character geometry such as the Wizard's hat. The ink-light shader preserves model base color or pigment graphs, with the pilot's warm outlined contour, common orthographic camera, deterministic 12-sample CPU Cycles lighting and Standard color transform. Enlarging the registration canvas preserves the pilot's pixels per metre. No fitted-to-silhouette scaling or individual recentering.

`cast/takes.py` defines source frame samples and timings at 24 fps. Sparse holds and source-specific key beats avoid baking every playback frame. Neutral T-poses are setup, not performances. Knight and Healer have no separate ready action; Rogue's retreat doubles as the ready pose at F1. Knight shield-away is the F8 stance with the whole detachable shield hierarchy invisible. No invented attack takes. Wizard Pull ends seated. Bard's duplicate closing loop keys are deliberately omitted.

**Drawing contract.** `manifest.actors[art_key].clips[name]` gives `path`, `frames`, `anchor` and `loop`; each frame is an atlas `rect: [x,y,width,height]` with `source_frame` and `duration_ms`. Use the root-level `display_scale` (0.375) uniformly. Register the **clip-local** anchor, not the rectangle center, on the actor's ground position. If mirroring, mirror the entire draw around that position. Three clear pixels surround all nonzero alpha in each rectangle, including the warm outline. Rectangles can repeat. On actor drawings the anchor is the projected ground origin, unchanged by the current pose. Thus planted feet stay put; even the Wizard's slip moves relative to a stationary ground point.

At Zombie Offer Flower's `release.time_ms` (875 ms; F22), stop drawing a held gift. The baked actor already has an empty hand on this and every subsequent drawing. Start the separate `gift` clip at actor ground position plus `release.offset * display_scale`, mirroring the horizontal component when the actor faces the other way. The gift clip anchor locates its **stone root**, not its feet or bounds center. Its offset comes from the evaluated authored prop root at the marker. Draw flight to the chosen target; the model's review trajectory is deliberately absent. Only a switch back to Ready restores the held gift after the throw. For a shot sequence stay on its final empty frame until that transition.

These eight roles use 27 clips, 208 timed samples and 198 unique packed rectangles, in eight cropped atlases (about 4.8 MiB PNG; 27.5 MiB when decoded to plain RGBA8). Each take uses one fixed crop over all poses. `verify_cast.py` checks the delivered PNG alpha, padding, frame bounds, identities and timing. The proof sheet samples every take including the released hand and separate gift. Offline checks do not prove acceptance at game scale or that a player reads the action correctly.
