# Barnaby's Order: actor atlas recipe

From the repository root:

```sh
python games/company-of-unlikely-heroes/tools/bake_cast.py
python games/company-of-unlikely-heroes/tools/cast/test_packing.py
python games/company-of-unlikely-heroes/tools/cast/verify_cast.py
python games/company-of-unlikely-heroes/tools/cast/proof_sheet.py /tmp/opencode/cast-proof.jpg
```

The first command writes nine PNGs and `manifest.json` under `assets/cast`. `--output DIR` builds separately; `--jobs` and `--threads` control CPU use. Requires Python 3, Blender 5.2.2 LTS and ImageMagick 7 (verified with 7.1.2-34). Only the optional labeled proof uses Fontconfig. No Godot import cache or local art history is an input. Regenerate the tracked Godot texture import sidecars with `godot --headless --editor --path games/company-of-unlikely-heroes --import` (verified with 4.7.2).

`masters.json` pins the approved native rigs under `.lore/work/games/company-of-unlikely-heroes/art/models`. Per-model READMEs there document orientation, approvals, source limitations and actions. The renderer opens each master and checks its SHA-256 before and after, without saving. Two exact strips are reused from the tracked `art/pilots/ferryman-crossing/assets`: Knight Guard and Healer Ally Heal, pinned in `takes.py`. Their original renderer is `art/pilots/ferryman-crossing/authoring/bake_sprites.py` and uses those same two masters. Other drawings come directly from the native files. Render-only review floors and lights are excluded, not unparented character geometry such as the Wizard's hat. The ink-light shader preserves model base color or pigment graphs, with the pilot's warm outlined contour, common orthographic camera, deterministic 12-sample CPU Cycles lighting and Standard color transform. Enlarging the registration canvas preserves the pilot's pixels per metre. No fitted-to-silhouette scaling or individual recentering.

`cast/takes.py` defines source frame samples and timings at 24 fps. Sparse holds and source-specific key beats avoid baking every playback frame. Neutral T-poses are setup, not performances. Knight and Healer have no separate ready action; Rogue's retreat doubles as the ready pose at F1. Knight shield-away is the F8 stance with the whole detachable shield hierarchy invisible. No invented attack takes. Wizard Pull ends seated. Bard's duplicate closing loop keys are deliberately omitted.

**Drawing contract.** `manifest.actors[art_key].clips[name]` gives `path`, `frames`, `anchor` and `loop`; each frame is an atlas `rect: [x,y,width,height]` with `source_frame` and `duration_ms`. Use the root-level `display_scale` (0.375) uniformly. Register the **clip-local** anchor, not the rectangle center, on the actor's ground position. If mirroring, mirror the entire draw around that position. Three clear pixels surround all nonzero alpha in each rectangle, including the warm outline. Rectangles can repeat. On actor drawings the anchor is the projected ground origin, unchanged by the current pose. Thus planted feet stay put; even the Wizard's slip moves relative to a stationary ground point.

At Zombie Offer Flower's `release.time_ms` (875 ms; F22), stop drawing a held gift. The baked actor already has an empty hand on this and every subsequent drawing. Start the separate `gift` clip at actor ground position plus `release.offset * display_scale`, mirroring the horizontal component when the actor faces the other way. The gift clip anchor locates its **stone root**, not its feet or bounds center. Its offset comes from the evaluated authored prop root at the marker. Draw flight to the chosen target; the model's review trajectory is deliberately absent. Only a switch back to Ready restores the held gift after the throw. For a shot sequence stay on its final empty frame until that transition.

## Mixologist

The `alchemist` atlas is derived from the [exact accepted Mixologist rig](../../../../.lore/work/games/company-of-unlikely-heroes/art/models/mixologist/README.md) at `5b7c52c`. Its SHA-256 is pinned in `masters.json`; that file also maps the runtime key `alchemist` to the native `Mixologist` action prefix. The recipe does not save changes to the master. The common orthographic capture uses 104.918 px/m, forward −Y and up +Z, with the projected origin at `[160, 248]` before crop. The Mixologist keeps the cast's painterly ink and registration. For her bottles only, the ink pass applies a translucent tinted shell over the original liquid colors, with stronger tint at the edges. Opaque ink on the glass hid the amber and green at board scale. No receiving hand or recipient is baked.

| Clip | Source and timing |
| --- | --- |
| `ready` | Ready F1, held as a one-drawing loop (idle). Prone and fallen use the board's existing drawing treatment, not new native takes. |
| `potion` | Healing Potion. The full two-hand offer starts at F17 (667 ms); the bottle is gone at F24 (958 ms). F36 returns to Ready. Total: 1583 ms. |
| `acid` | Acid Toss. F16 is the final held sample. At F18 (708 ms), the flask is detached and only the actor remains in the take; F32 returns to Ready. Total: 1417 ms. |
| `acid_flask` | F18, one drawing registered to the authored flask root. The `acid.release` offset places it at that same world-space departure pose (projected offset `[104.975, -165.482]` in atlas pixels). Mirror X around the actor's ground point when the throw faces left. The native flight is not baked; the board can fly this separate drawing to the resolved target. |

The atlas is 864 × 950, 438,207 bytes, SHA-256 `c25ff32a9875447ed00d90c8439af158df4378db654febe72afc5ed6e5334f31`. It has 25 timed samples and 24 packed rectangles. In a Godot 4.7.2 art-only board preview, the PNG and imported texture both loaded, the Ready silhouette fit beside the other playable heroes at 96 × 80 tile scale, and the low offer and overhead release read distinctly. The flask is small at that scale, so its arc and the actor's silhouette carry most of the throw. Both right- and left-facing flights were inspected. Visual runtime acceptance is separate from these checks.

The full cast has 31 clips, 233 timed samples and 222 unique packed rectangles across nine cropped atlases (about 5.1 MiB PNG; 30.6 MiB when decoded to plain RGBA8). Each take uses one fixed crop over all poses. `verify_cast.py` checks the delivered PNG alpha, padding, frame bounds, identities and timing. The proof sheet samples every take, including both releases and their separate props.
