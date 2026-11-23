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

`cast/takes.py` defines source frame samples and timings at 24 fps. Sparse holds and source-specific key beats avoid baking every playback frame. Neutral T-poses are setup, not performances. Knight shield-away is the F8 stance with the whole detachable shield hierarchy invisible. Wizard Pull ends seated. Bard's duplicate closing loop keys are deliberately omitted.

### Five guild ready loops

`cast/ready_poses.py` is the editable choreography for Knight, Healer, Wizard, Rogue and Mixologist. `Ready Idle` is a derived bake timeline, not an action stored in the native master. It samples the original native pose and applies small additive turns in memory. The first drawing uses the previous ready pose unmodified, including the exact Knight and Healer pilot frames. It is still the stationary drawing used for the tinted move preview and default prone hold. The sample at the loop boundary is the first drawing again, not a duplicated closing key. No other clips use the overlays.

| Hero | Ready motion | Duration |
| --- | --- | ---: |
| Knight | Huddles behind the shield and eases back. Only the planted lead-in of Guard is sampled. | 1750 ms |
| Healer | Tilts her head skeptically, drops her free elbow, and settles without moving the staff. | 2125 ms |
| Wizard | Perks up with a small follow-through in the hat tip. | 1500 ms |
| Rogue | Checks the side, then settles his cap and cape without retreating. | 1833 ms |
| Mixologist | Checks the stowed bottles and settles her arm without drawing one. | 2000 ms |

To reproduce just these atlases, use an empty, disk-backed staging directory and bounded Blender workers:

```sh
tools=games/company-of-unlikely-heroes/tools/cast
scratch="$PWD/.lore/local/cast-bake"
mkdir -p "$scratch/tmp"
TMPDIR="$scratch/tmp" MAGICK_TEMPORARY_PATH="$scratch/tmp" \
  python "$tools/bake_subset.py" "$scratch/guild-ready" knight healer wizard rogue alchemist --threads 3
python "$tools/verify_cast.py" --assets "$scratch/guild-ready" knight healer wizard rogue alchemist
```

The full recipe also builds these loops. The staged manifest remains partial; merge only these five entries if publishing a subset. Review the loops at board scale rather than treating multiple packed samples as evidence of readable motion.

## Guild training gestures

`cast/training_poses.py` adds one-shot, owner-specific takes to the existing derived-pose recipe. It samples each owner's approved animation and adds bone turns in memory. The takes begin and end in the native Ready pose. No master, geometry, or existing take is edited. The Mixologist's active flask follows the original hand-to-prop transform through the altered poses; this contact take has no projectile or release marker.

| Clip | Gesture | Feedback frame |
| --- | --- | ---: |
| `rescue_line` / `rescue_line_unshielded` | Reach and haul with the free gauntlet. The same gesture can render with the shield hierarchy hidden. | 14 |
| `ring_sparks` | Both palms open low and wide from a planted gather, without the step or recoil of the base spells. | 12 |
| `tripwire` | Plant, reach down, and give a quick tug. No crossing step. | 13 |
| `grave_bell` | One short bell strike, without the high repeated ring and invitation of Summon Skeleton. | 12 |
| `etching_paste` | Draw the green flask, press it forward low, and return it to the rack. | 13 |

Use the disk-backed subset command above with `knight wizard rogue necromancer alchemist` and a fresh staging directory. Verify the staged atlas and compare the previous clips after alignment by their anchors: atlas shelf packing may move a rectangle even when the drawing, timing, and registration are unchanged.

## Cross-trained gestures

`cast/learner_poses.py` contains the seven learner performances. The samples use the learner's own source pose and equipment. The actor masters and donor clips are not inputs to any other actor's take. The Dodger's hand-fit corked vial is built by `cast/rogue_vial.py`, only appears during the offer, and has no release. The Mixologist's recoil is the only clip here that ends away from Ready: she sits on the ground in its final drawing with her rack and reserve bottles still attached.

| Clip | Action beat |
| --- | --- |
| `knight.bonk` / `knight.bonk_unshielded` | F13, downward knock with the free gauntlet |
| `healer.blast` | F12, pulse from the free palm with the staff planted |
| `wizard.dodge` | F11, tuck and turn in place while the board resolves the swap |
| `bard.push` | F12, shoulder check with fiddle and bow still carried |
| `rogue.potion` | F15, offer the corked vial |
| `necromancer.melody` | F13, first of the rhythmic bell strokes |
| `alchemist.pull` | F13, tug; F24 seat contact; F33 final seated drawing |

To rebuild just these actors, use the disk-backed subset recipe above with `knight healer wizard bard rogue necromancer alchemist` and a fresh staging directory. Verify the previous poses using registered pixels, not packed coordinates.

## Adventure reward gestures

`cast/reward_poses.py` derives two gestures from the SHA-pinned Knight and Necromancer masters in `masters.json`. To stage just these atlases, use `bake_subset.py` with a fresh disk-backed directory and the roles `knight necromancer`.

- `knight.shield_throw` turns the strapped shield back, swings it forward, and settles into the existing `shield_away` drawing. F15 is the last held sample. F16 is the first empty-handed sample and the release (625 ms). `shield_projectile` isolates the complete `Shield_L_Detachable` assembly at the same evaluated F16 pose and registers it to the projected shield mount. The drawing contains no character pixels. Runtime mirrors the actor-relative release offset and uses the committed shield drop cell for the 300 ms flight, before showing a ground marker.
- `necromancer.nominate` points with the free left hand at F13 (500 ms) and returns to Ready. The bell remains low and quiet; no projectile, summon or ground mark is baked.

## Living knockdown and recovery

`cast/knockdown_poses.py` layers each performer’s own brace and recovery over the unchanged approved rig. The last `down` drawing and first `recover` drawing register to the same pose. The Knight has matching `down_unshielded` and `recover_unshielded` clips; only the detachable shield is hidden. Wizard and Mixologist `seated_recover` start from the exact final drawing of their respective Pull, not from ordinary Down. Every recovery ends on the original Ready drawing, or the exact shield-away drawing for the unshielded Knight.

| Take | Contact / rise | Duration |
| --- | --- | ---: |
| `down`, `down_unshielded` | F16 (625 ms) contacts; F24 settles | 1125 ms |
| `recover`, `recover_unshielded`, `seated_recover` | F22 (875 ms) is the final rise; F26 is ready | 1167 ms |

Use the same disk-backed subset command with `knight healer wizard rogue bard necromancer alchemist`. Compare ground-registered drawings for all three seams: Ready into fall, the down-to-recover hold, and return to Ready. These are living performances, not defeat art.

**Drawing contract.** `manifest.actors[art_key].clips[name]` gives `path`, `frames`, `anchor` and `loop`; each frame is an atlas `rect: [x,y,width,height]` with `source_frame` and `duration_ms`. Use the root-level `display_scale` (0.375) uniformly. Register the **clip-local** anchor, not the rectangle center, on the actor's ground position. If mirroring, mirror the entire draw around that position. Three clear pixels surround all nonzero alpha in each rectangle, including the warm outline. Rectangles can repeat. On actor drawings the anchor is the projected ground origin, unchanged by the current pose. Thus planted feet stay put; even the Wizard's slip moves relative to a stationary ground point.

At Zombie Offer Flower's `release.time_ms` (875 ms; F22), stop drawing a held gift. The baked actor already has an empty hand on this and every subsequent drawing. Start the separate `gift` clip at actor ground position plus `release.offset * display_scale`, mirroring the horizontal component when the actor faces the other way. The gift clip anchor locates its **stone root**, not its feet or bounds center. Its offset comes from the evaluated authored prop root at the marker. Draw flight to the chosen target; the model's review trajectory is deliberately absent. Only a switch back to Ready restores the held gift after the throw. For a shot sequence stay on its final empty frame until that transition.

## Zombie

The [accepted Zombie rig](../../../../.lore/work/games/company-of-unlikely-heroes/art/models/zombie/README.md) provides the still Ready pose. The derived Ready Idle uses seven drawings over 2333 ms: the head droops, the gift-side shoulder follows, then both settle without moving the boots. The first drawing is the original Ready pose for the stationary destination stamp. The flower-tied stone stays attached to the right hand; no release or native take changes. To stage just this atlas, use the same disk-backed `bake_subset.py` and `verify_cast.py` commands above with a fresh staging directory and the single role `zombie`.

## Mixologist

The `alchemist` atlas is derived from the [exact accepted Mixologist rig](../../../../.lore/work/games/company-of-unlikely-heroes/art/models/mixologist/README.md) at `5b7c52c`. Its SHA-256 is pinned in `masters.json`; that file also maps the runtime key `alchemist` to the native `Mixologist` action prefix. The recipe does not save changes to the master. The common orthographic capture uses 104.918 px/m, forward −Y and up +Z, with the projected origin at `[160, 248]` before crop. The Mixologist keeps the cast's painterly ink and registration. For her bottles only, the ink pass applies a translucent tinted shell over the original liquid colors, with stronger tint at the edges. Opaque ink on the glass hid the amber and green at board scale. No receiving hand or recipient is baked.

| Clip | Source and timing |
| --- | --- |
| `ready` | A derived two-second rack-check loop based on Ready F1. Prone and fallen use the board's existing drawing treatment, not new native takes. |
| `potion` | Healing Potion. The full two-hand offer starts at F17 (667 ms); the bottle is gone at F24 (958 ms). F36 returns to Ready. Total: 1583 ms. |
| `acid` | Acid Toss. F16 is the final held sample. At F18 (708 ms), the flask is detached and only the actor remains in the take; F32 returns to Ready. Total: 1417 ms. |
| `acid_flask` | F18, one drawing registered to the authored flask root. The `acid.release` offset places it at that same world-space departure pose (projected offset `[104.975, -165.482]` in atlas pixels). Mirror X around the actor's ground point when the throw faces left. The native flight is not baked; the board can fly this separate drawing to the resolved target. |

In the original Godot 4.7.2 art-only board preview, the PNG and imported texture both loaded, the Ready silhouette fit beside the other playable heroes at 96 × 80 tile scale, and the low offer and overhead release read distinctly. The flask is small at that scale, so its arc and the actor's silhouette carry most of the throw. Both right- and left-facing flights were inspected. Visual runtime acceptance is separate from these checks.

## Harpooner

The registered `harpooner` uses the [exact accepted rig](../../../../.lore/work/games/company-of-unlikely-heroes/art/models/harpooner/README.md). Ready carries the diagonal harpoon. Pursue registers the in-place step at the cell anchor. Close Thrust keeps the weapon in hand and hits on F8 (292 ms). Ranged Cast keeps the weapon in hand through F10, then detaches `harpoon_projectile` on F11 (417 ms). The actor remains empty-handed until switching back to Ready; only the release drawing of the shaft is baked, not the model's preview flight. `hit` is a quick flinch; `defeat` holds the final crouched drawing with the shaft on the ground. The capture is biased toward the attack to fit the long shaft without scaling the actor.

Each take uses one fixed crop over all poses. `verify_cast.py` checks the delivered PNG alpha, padding, frame bounds, identities and timing. The proof sheet samples every take, including the paired actor and prop drawings at release.
