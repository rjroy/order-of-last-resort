# Barnaby's Order: actor atlas recipe

From the repository root:

```sh
python games/company-of-unlikely-heroes/tools/bake_cast.py
python games/company-of-unlikely-heroes/tools/cast/test_packing.py
python games/company-of-unlikely-heroes/tools/cast/verify_cast.py
python games/company-of-unlikely-heroes/tools/cast/proof_sheet.py /tmp/opencode/cast-proof.jpg
```

The first command writes the registered PNGs and `manifest.json` under `assets/cast`. `--output DIR` builds separately; `--jobs` and `--threads` control CPU use. Requires Python 3, Blender 5.2.2 LTS and ImageMagick 7 (verified with 7.1.2-34). Only the optional labeled proof uses Fontconfig. No Godot import cache or local art history is an input. Regenerate the tracked Godot texture import sidecars with `godot --headless --editor --path games/company-of-unlikely-heroes --import` (verified with 4.7.2).

For a single actor, use an empty staging directory rather than publishing over the runtime assets:

```sh
tools=games/company-of-unlikely-heroes/tools/cast
stage=.lore/local/cast-bake/harpooner
python "$tools/bake_subset.py" "$stage" harpooner
python "$tools/verify_cast.py" --assets "$stage" harpooner
python "$tools/proof_sheet.py" "$stage/harpooner-proof.png" --assets "$stage"
```

The staging manifest contains only the selected entries and is not a replacement for the runtime manifest. To publish one actor, copy only its PNG and merge its one generated actor entry.

The full build and full verification discover one-role recipes in `tools/cast/actors/<role>.json`. Commit each accepted recipe alongside its atlas and manifest entry. Full verification requires every discovered recipe to have its atlas and manifest entry. Explicit subset verification loads only the requested actors, so another in-progress recipe cannot disrupt it. A staging `--recipe` identical to an installed role is allowed; a conflicting definition is rejected.

An individually approved actor can instead be staged with a single JSON recipe fragment, without changing either shared registry. Fragments are opt-in for `bake_subset.py` and `verify_cast.py`, not included by the full build, and cannot replace a registered actor. The fragment's `role` is a lowercase runtime identifier, `master` uses the same fields as an entry in `masters.json`, and `takes` maps clip names to `[action suffix, source-frame list, exclusive stop, loop]` as in `takes.py`. Optional `release` uses the five fields documented in `takes.py`. For example, with the source and hash replaced by an approved exact master:

```json
{
  "role": "example",
  "master": {
    "source": "models/example/example.blend",
    "sha256": "<approved SHA-256>",
    "rig_name": "Example_Rig",
    "action_prefix": "Example"
  },
  "takes": {"ready": ["Ready", [1], 25, true]}
}
```

Use `python "$tools/bake_subset.py" "$stage" example --recipe /path/to/example.json`, then `python "$tools/verify_cast.py" --assets "$stage" --recipe /path/to/example.json example`. The staging directory must be empty, and the fragment and approved master must remain available for both commands. The proof sheet reads the staged manifest as usual. A fragment is an extraction recipe, not model, runtime, or publication approval. Special prop visibility and release behavior still require appropriate renderer support; a generic release does not automatically handle every native action.

For any master, `rig_name` and `action_prefix` independently override native names. If omitted they retain the existing `source_actor` (or title-cased role) defaults: `<actor>_Rig` and `<actor> | <action>`. An explicitly empty `action_prefix` selects the unprefixed action name with no separator. These options do not alter the source, projection, lighting or timing.

`capture_size` can enlarge the square canvas without changing the camera orientation or pixels per metre. `capture_anchor: [x,y]` places the ground origin in that canvas; for example, `512` and `[256,344]` add 96 pixels on every side of the normal capture. Omitting both keeps the existing 320 px capture and anchor; the legacy `capture_anchor_x` remains supported. The renderer, projectile projections, packer and verifier use the selected size. Enlarging capture does not prove a pose fits: examine the full native motion, outline and three-pixel padding, then verify the rendered staging output. Do not reduce scale to force a fit.

For a detached-prop recipe, an optional master field `release_visible_frames` maps actor clip names to inclusive frame windows during which the prop is attached and visible. Other actor frames hide that prop hierarchy; the separate prop clip remains visible. Omit the field to retain existing release behavior. This affects only the release prop, not other carried or independently released objects.

An optional `projectile_tip_offsets` master map records `[x,y]` in capture pixels from an evaluated detached-prop root to its authored tip. The packer adds the crop-adjusted root anchor and emits clip-local `tip`; the verifier checks the same relation. Derive the offset from the exact approved source at the release frame and common camera, not another actor's geometry.

`masters.json` pins the approved native rigs under `.lore/work/games/company-of-unlikely-heroes/art/models`. Per-model READMEs there document orientation, approvals, source limitations and actions. The renderer opens each master and checks its SHA-256 before and after, without saving. Two exact strips are reused from the tracked `art/pilots/ferryman-crossing/assets`: Knight Guard and Healer Ally Heal, pinned in `takes.py`. Their original renderer is `art/pilots/ferryman-crossing/authoring/bake_sprites.py` and uses those same two masters. Other drawings come directly from the native files. Render-only review floors and lights are excluded, not unparented character geometry such as the Wizard's hat. The ink-light shader preserves model base color or pigment graphs with the pilot's warm outlined contour, common orthographic projection, deterministic 12-sample CPU Cycles lighting and Standard color transform. Capture padding does not change pixels per metre or actor registration. The optional `capture_anchor_x` reallocates blank space toward a long prop without changing the camera angle, scale, registered pose, or release offset.

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

## Harpooner

The registered `harpooner` uses the [exact accepted rig](../../../../.lore/work/games/company-of-unlikely-heroes/art/models/harpooner/README.md). Ready carries the diagonal harpoon. Pursue registers the in-place step at the cell anchor. Close Thrust keeps the weapon in hand and hits on F8 (292 ms). Ranged Cast keeps the weapon in hand through F10, then detaches `harpoon_projectile` on F11 (417 ms). The actor remains empty-handed until switching back to Ready; only the release drawing of the shaft is baked, not the model's preview flight. `hit` is a quick flinch; `defeat` holds the final crouched drawing with the shaft on the ground. The capture is biased toward the attack to fit the long shaft without scaling the actor.

Each take uses one fixed crop over all poses. `verify_cast.py` checks the delivered PNG alpha, padding, frame bounds, identities and timing. The proof sheet samples every take, including the paired actor and prop drawings at release.
