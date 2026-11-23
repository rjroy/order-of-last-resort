# Hookhand model and motion

For Barnaby’s Order of Last Resort, `hookhand` (`mind-garage-xmy.4`). The exact [approved Hookhand art](../../concepts/non-hero-cast/approved-concepts.html#river) is the upper-right entry of `01-river-and-village.png`, SHA-256 `f3a93be9d71479a142b88c46597558e460ae9a729735b87fb8a54591c48af767`. Harpooner was used read-only as a tactical-size comparison. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

## Editable source

The self-contained [accepted `.blend`](hookhand.blend), SHA-256 `00a0381915c32fb33bf956cdab0c62b2c93f53c67f786d0a3cfdc621e8ad8098`, uses Blender 5.2.2 LTS (`d13f752e3b9c`), metres, −Y forward, +Z up. It has 50 bones and 141 named mesh/curve objects. Its neutral body measures 1.760 × 0.811 × 2.065 m, excluding the line and prop. There are no external image textures or model links. The authoring scripts reuse geometry and pose math helpers from the Harpooner source without changing that package; the saved `.blend` does not need either script package to open or play.

The file opens on Ready. Select `Hookhand_Rig`, choose one of its actions in **Dope Sheet → Action Editor** and set the timeline end from the table. The rig has a true T-rest, separately poseable fingers, a weighted main coat and vest, and a 19-bone towline on the root. The line and strand surfaces are regular meshes skinned to the line controls. Hide `04 · Coil, towline and detachable hook` for the unencumbered rest view. The forged hook and eye are grouped under `Hook_Detachable`; clear its parent with **Keep Transformation** to detach the prop assembly. The edited line need not move with it automatically outside the authored actions.

| Action, all prefixed `Hookhand \|` | Frames at 24 fps | Intent |
| --- | --- | --- |
| Neutral T | 1 | Actual armature rest. |
| Ready | 1–39 | Forward hunch, slack line and low hanging hook. |
| Approach | 1–29 | Alternating in-place steps for `move`; logic owns cell displacement. |
| Hook Pull | 1–43 | Pays out low, braces F14, rocks back through F18 and settles by F22. Both boots stay planted. One continuous line from coil to right fist, left fist and hook eye. |
| Flinch | 1–19 | Starts and returns to Ready. |
| Down | 1–30 | Buckles to a knee without delivering a hit; hangs low from F25. |
| Recover | 1–28 | Starts exactly at the Down hold and stands into Ready. |

`hook_pull` draws a target one tile closer, does not displace Hookhand, and does not deal damage. No opponent, target tie-in or force simulation is authored. The 94 cm on the review rig is visible prop travel, not gameplay distance. Runtime aligns displacement feedback with the F18 pull. Down supplies the terminal pose; Recover plays when Hookhand actually gets up from knockdown.

## Reopen, render, and compare

From the repository root:

```bash
m="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models"
o="$PWD/.lore/local/company-of-unlikely-heroes/non-hero-cast/hookhand"
mkdir -p "$o"
export PYTHONDONTWRITEBYTECODE=1

# Optional reconstruction; only pass a nonexistent absolute .blend path.
# blender -b --factory-startup -t 5 --python-exit-code 1 \
#   -P "$m/hookhand/build_hookhand.py" -- "$o/hookhand-rebuild.blend"

blend="$m/hookhand/hookhand.blend"
sha256sum "$blend" "$m/harpooner/harpooner.blend" > "$o/review-sources.sha"
blender -b "$blend" -t 3 --python-exit-code 1 -P "$m/hookhand/review_hookhand.py" -- check
blender -b "$blend" -t 5 --python-exit-code 1 -P "$m/hookhand/review_hookhand.py" -- poses "$o/poses"
blender -b "$blend" -t 5 --python-exit-code 1 -P "$m/hookhand/review_hookhand.py" -- motion "$o/frames"
blender -b "$m/harpooner/harpooner.blend" -t 4 --python-exit-code 1 \
  -P "$m/hookhand/review_hookhand.py" -- harpooner "$o/comparison"
bash "$m/hookhand/make_review_previews.sh" "$o"
sha256sum -c "$o/review-sources.sha"
```

The read-only review uses the roster tactical camera and a floor anchor for both rigs. The pose sheet includes the rear to show the long mantle. The shared 26.55 px/m proof samples the exact accepted Harpooner file, not generated concept art. Rendering and validation here do not include any runtime work.

| Evidence | Size | SHA-256 |
| --- | --- | --- |
| [Pose sheet](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/hookhand/hookhand-pose-sheet.png) | PNG, 930 × 1067 | `62735d34f93a7a4af344f47699ca886e1caa54e014ed686d75a16c21e737adff` |
| [Motion preview](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/hookhand/hookhand-motion.mp4) | MP4, 870 × 580, 30 frames at 12 fps | `f289d27d2cc77ba1b2311eec30f767b9d7493026674fbc93132d11f4b16e8d4a` |
| [Tactical-size comparison with Harpooner](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/hookhand/hookhand-vs-harpooner.png) | PNG, 278 × 389 | `4f04ae59c91e9585ec1ba6966853b9b5648da5b18422d128b2948070dc56fe13` |

Reopened checks covered 370 half-frame samples. The root stayed fixed, Hook Pull’s ankles were stationary to 0.01 mm precision, and the prop moved inward 94 cm while the lead grip drew back 26.8 cm. The taut span deviated less than 2 mm from straight, both grip anchors stayed within 0.001 mm of their centers, and the hook-eye join stayed continuous. The lowest measured sole was 6.5 mm above its plane. Ready and low pose transitions match across actions. These checks do not establish whole-body cloth clearance or forearm clearance under arbitrary edits.

The comparison reads as a round coil and dangling C at Ready versus Harpooner’s uninterrupted diagonal shaft. In action, the low line remains attached and shortens while Hookhand’s chest rocks back; Harpooner sends his shaft away. The direction is clear across frames, but the coil and hook gap are small at board scale. Verify the pull beside Harpooner, the target, and ground clutter after model acceptance, without adding a hit flash for a displacement-only ability.
