# Daft Dodger: approved Try This actions

These four supplementary takes use the actual accepted Daft Dodger, not the
donor heroes. The user accepted the four v3 source and cue auditions and
authorized production staging for the Dodger on 2026-11-24. This is not
Godot publication or runtime acceptance. The fitted clips do not replace
ordinary performances on a fallback. See the [approved character](../rogue/README.md), [conversion
design](../../../notes/hobby-smith-design.md) and [cast
recipe](../../../../../../../games/company-of-unlikely-heroes/tools/cast/README.md).

| Conversion | Is the stock Dodger take reusable? | New take and sound |
| --- | --- | --- |
| **It Was Me**, native Wasn't Me | No. `misdirect` offers an outward palm and never hits. Keep the idea of a hand to the chest, not the alibi clip or its voice recording. | A compact left-hand bonk at **F10 / 375 ms**, then a right-hand self-claim with the other hand down at **F19 / 750 ms**. Dry bonk based on the existing Bonk recipe, then a light vest tap and key jingle. No pointing at anyone else, and no redirect or bystander cue. |
| **Clear Jump**, native Confusing Dodge | No. `swap` is a grounded cross-step pivot that marks the old exchange. Keep the cape flash as vocabulary, not the cross-plant. | **F7 / 250 ms** takeoff and cloth swish, **F12 / 458 ms** airborne apex, **F17 / 667 ms** planted landing with the approved light footfall. Board translation is separate between F7 and F17: move only the Dodger beside the already resolved farthest foe. Never swap, move the foe, or imply an alternate target. |
| **Cut the Wire**, guild Tripwire | No. `tripwire` has a useful low gathering shape but ends with a tug that could tighten the hold. | The Dodger takes his own ticket punch off the belt. One hand steadies low, the punch clips at **F13 / 500 ms**, then both hands spring apart by F15. A short metallic nip leads into a dying wire twang. No trap placement, ground wire or victim is baked. An eventual board cue should identify the friendly hold that was freed; this is not a universal status cleanse. |
| **Bitter Medicine**, borrowed Healing Potion | No. `potion` gives a gentle corked offer. Reuse the stock learner's hand-fit vial geometry, not the offer or dose sound. | Show the vial clearly at **F10 / 375 ms**, snap it forward and tip it at **F13 / 500 ms**, then withdraw empty. A glass tick and wet pat mark hostile contact, without implying a thrown vial or glass shatter. The board owns the actual recipient, range, damage and reaction. If longer effective reach is shown, establish dose contact at the resolved target separately. |

Times run from the first drawing at 24 fps. For an eventual atlas bake use the
sample frames and marker metadata in `choreography.py`; the last frame is the
Ready recovery drawing, not an extra beat. Ready/Retreat and the unrelated
stock down, recover and defeat performances do not need substitutes. The
left-hand bonk and the chest claim do not require a second actor; launch and
landing are deliberately separate from hit/target dispatch.

## Approved source and review evidence

- [Editable Blender source](rogue-try-this.blend), the exact promoted v3 file
- [Stock vs. candidate tactical sheet](../../../../../../local/company-of-unlikely-heroes/rogue-try-this/review-v3/tactical-comparison.png)
- [Timed tactical motion with sound](../../../../../../local/company-of-unlikely-heroes/rogue-try-this/review-v3/tactical-motion.mp4)
- [Cue metadata](../../../../../../local/company-of-unlikely-heroes/rogue-try-this/frames-v3/cues.json)
- Audition sound components: [bonk](../../../../../../local/company-of-unlikely-heroes/rogue-try-this/review-v3/sound/bonk.wav),
  [claim](../../../../../../local/company-of-unlikely-heroes/rogue-try-this/review-v3/sound/claim.wav),
  [jump takeoff](../../../../../../local/company-of-unlikely-heroes/rogue-try-this/review-v3/sound/lift.wav),
  [landing audition mix](../../../../../../local/company-of-unlikely-heroes/rogue-try-this/review-v3/sound/land.wav),
  [cut](../../../../../../local/company-of-unlikely-heroes/rogue-try-this/review-v3/sound/cut.wav),
  [bitter](../../../../../../local/company-of-unlikely-heroes/rogue-try-this/review-v3/sound/bitter.wav).
  For future landing integration use the original stereo footfall WAV, not
  the mono audition mix.

Open the `.blend`, select `Rogue_Rig`, and choose `Rogue | It Was Me`,
`Rogue | Clear Jump`, `Rogue | Cut the Wire`, or `Rogue | Bitter Medicine` in
the Action Editor. Start at frame 1 and set the timeline end to 35, 27, 27 or
26, respectively. The new actions have independent FK curves sampled every
half-frame and named action markers, no NLA or live IK. The `Stage` group keys
cape folds and the action-only vial/tool switches. Reset to the first or last
frame before switching from a new action to a stock native action, since stock
actions do not animate the supplemental prop switches.

### Rebuild from the repository root

Requires Blender 5.2.2 LTS, Python 3, ImageMagick 7, Fontconfig with Liberation
Sans or a matching fallback and FFmpeg with H.264/AAC. No new installation or
external generator is needed. Rebuilds and renders go in ignored
`.lore/local/`; neither accepted Blender source is overwritten.

```sh
pkg="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/rogue-try-this"
out="$PWD/.lore/local/company-of-unlikely-heroes/rogue-try-this/rebuild"
mkdir -p "$out"
export PYTHONDONTWRITEBYTECODE=1
timeout 90 blender -b "$pkg/../rogue/rogue-blockout.blend" -t 4 \
  --python-exit-code 1 --python "$pkg/build_actions.py" -- "$out/rogue-try-this.blend"
timeout 220 blender -b "$out/rogue-try-this.blend" -t 6 \
  --python-exit-code 1 --python "$pkg/review_actions.py" -- "$out/frames"
timeout 90 env MAGICK_THREAD_LIMIT=2 python -B "$pkg/package_review.py" "$out/frames" "$out/review"
```

The authoring script consumes the accepted master at
`99d4607ab9e9792c51e15ae90d11d412973e98e3e17f481b5c976fbac02cfbb1`.
The vial comes from `tools/cast/rogue_vial.py`; the held punch uses the exact
existing mesh/curve data, with a separate grip. The source and review inherit
metres, −Y forward, +Z up, common tactical ortho camera, 104.918 px/m,
320 × 320 transparent capture and `[160, 248]` projected ground anchor.
Review uses the existing cast ink treatment and shipped stock atlas for
comparison. The film is a single-actor staging example, not a Godot capture.
There is no target motion, recipient reaction, hit feedback, status effect or
wire baked into the character drawings. No changes to Godot, the original
`.blend`, stock atlas, other actors or approved sounds.

### Verification

The linked `.blend` SHA-256 is
`2fa08088d5da15c27f22debe0911ebbe4749a3d0062b4f66b0a159675347d3d1`.
Reopening found 40 bones, 229 mesh or curve objects excluding the review
floor, four original actions and four supplementary actions. At 226
half-frame samples, the root stayed fixed, the sole floor minimum was
4.07 mm and planted foot matrix differences from Ready were at most
0.000001. Every take returned to Ready. Sampled figure geometry stayed
at least 28 px inside capture; the two prop switches and key spatial beats
passed their checks. The tactical PNG opened and the 203-frame H.264/AAC
film decoded without errors. An independent rebuild produced byte-identical
27 tactical PNGs, cue metadata, comparison sheet, six component WAVs and
synchronized WAV. This checks authoring and delivery, not whole-body cloth
collision, a fresh human audition or runtime playback.

At the smaller size, the jump silhouette and chest claim stay distinct.
The iron punch is clear up close, but the low cut and snap-apart motion
carry that read at board scale. Likewise, the vial is only a few pixels,
so the change from a presented bottle to a downward jab and the committed
contact sound matter more than its detail. These are the two beats to
check next against real board feedback once integration is authorized.

### Production atlas staging

The [Dodger-only supplement](../../../../../../../games/company-of-unlikely-heroes/tools/cast/supplements/rogue.json)
adds the four clips through the shared additive shelf. The stock role still
bakes from `rogue-blockout.blend`; the new shelf opens `rogue-try-this.blend`
directly. The extra vial and held punch are limited to their owning takes,
with native driver windows within those takes. Neither is a detached atlas
projectile.

After rendering `"$out/frames"` above, stage the complete role in an empty
directory. The stock comparison pulls only the prior shipped PNG and
manifest from revision `5952801588efe25d1d2a60a40bbc179172573f53`.

```sh
set -e
game="$PWD/games/company-of-unlikely-heroes"
stock="$out/prior-stock"
stage="$out/staged-rogue"
tmp=$(mktemp -d "$out/rogue-bake-tmp.XXXXXX")
mkdir -p "$stock"
base=5952801588efe25d1d2a60a40bbc179172573f53
for f in manifest.json rogue.png; do
  git show "$base:games/company-of-unlikely-heroes/assets/cast/$f" > "$stock/$f"
done
TMPDIR="$tmp" timeout 270 python -B "$game/tools/cast/bake_subset.py" "$stage" rogue --threads 4
python -B "$game/tools/cast/verify_cast.py" --assets "$stage" rogue
python -B "$pkg/verify_rogue_atlas.py" "$stock" "$stage" "$out/frames" \
  --proof "$out/production-contact.png"
rmdir -- "$tmp"
```

The [staged atlas](../../../../../../local/company-of-unlikely-heroes/rogue-try-this/production-rogue/rogue.png)
is 1440 × 2732 px, SHA-256
`ddeafd7e285e6ebdb9385bc5e7c9206dde0d557d122e2cb109b82bf67d4470f5`.
The [partial manifest](../../../../../../local/company-of-unlikely-heroes/rogue-try-this/production-rogue/manifest.json)
has SHA-256
`ffedcee568ccba6ead7b8f50dc9b463638e61a20b7d4aa374c33c365fcc70157`.
The 4-thread and 5-thread runs produced identical atlas and manifest files.
All 70 stock frames, including anchors, rectangles and durations, stayed
unchanged, and the full 1440 × 1563 stock image region matches byte-for-byte
in decoded RGBA. All 34 new frames preserve the approved silhouettes and
timing: 13 drawings match exactly; the remaining images differ by at most
one RGB level on at most four opaque pixels per frame. The [packed contact
proof](../../../../../../local/company-of-unlikely-heroes/rogue-try-this/production-rogue-contact.png)
comes from the staged atlas rectangles, not from the source review.
