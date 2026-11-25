# Hobby Smith petition artwork candidates

These three Guild Book petition plates were explicitly approved for runtime
integration on 2026-11-24, separate from the Smith's outing rewards. The Guild
Book supplies all text, controls and prices. The native and editable masters
remain here; the matching PNGs are packaged in `assets/guild-book/petitions`.

| Petition | Exact file stem | Visual cue |
| --- | --- | --- |
| Recruit the Hobby Smith | `recruit_blacksmith` | The Smith offers a finished fitting at her forge; the hammer is resting. |
| Learn Bonk and Taunt | `blacksmith_learn_bonk` | The Smith borrows the Healer's curled wooden staff and draws a brigand's attention with a short tap. |
| Learn Acid | `blacksmith_learn_acid` | The Smith throws one yellow-green vial toward a separate practice target. |

Each stem has an editable `masters/<stem>.ora` and a candidate
`plates/<stem>.png`. The OpenRaster document exposes the painting as a
named, movable, editable raster layer. The generator does not supply
separate underdrawing, pigment, character or backdrop layers. The untouched
generation atlas is retained separately as `hobby-smith-petitions-native.png`.

## Numbered stock convention

The approved 24 numbered petition plates use opaque, unresized 627 × 627
quadrants of native 1254 × 1254 masters. Match that convention: no added
alpha feather, no background removal, no lettered or UI decoration. The soft
border is painted watercolor falloff into opaque parchment, not transparency.
The 11-pixel alpha feather in the original Bard and Healer Blast concept
crops is a different historical route and is not applied here.

The Guild Book's petition `TextureRect` uses aspect-centered scaling, not
aspect-cover cropping. Minimum art heights are 215 px desktop and 145 px
compact. A headless Godot 4.7.2 geometry probe measured an unclipped
265/263/217-px square for Recruit/Bonk/Acid respectively at 1280 × 820, and
145 px each at 960 × 615. The probe uses the authored Smith copy and
prerequisites with existing stock square textures to obtain bounds; it does
not load any candidate into the shipping resolver. The ignored review sheet
renders the exact candidates off-line at those measured sizes on `#f7e0ba`,
alongside stock comparisons. It is not an in-game screenshot.

## Generation inputs

The exact approved Smith portrait supplied identity across all three scenes.
The Founders master supplied the Healer's crook shape and paired action
composition; the Mixologist master supplied the glass vial silhouette and
throwing cue. Neither borrowed move substitutes its donor's likeness.
Relative to `assets-source/guild-book/`:

| File | SHA-256 |
| --- | --- |
| `classes/blacksmith-native.png` | `e35c28dfa10db7dd6dcc211893ee7ca210f46f364be3b348433f0e1aabf4d248` |
| `petitions/masters/founders-a.png` | `f71e1eae4c47f30023245b0f494df638abe1f2bf425d315fd9183cefcd9b4a5d` |
| `petitions/masters/mixologist.png` | `d1af962f96b90ee184e0e154b453d72336fffa011fa068f14b371693bebb7804` |

The references are not conversion dependencies. `recipe.json` pins the native
atlas and its three crops; the bottom-right quadrant is not exported.

Generated on 2026-11-24 in one native OpenAI `image_gen` invocation through
Codex CLI 0.172.0 using the existing ChatGPT login. The OpenCode catalog listed
no OpenAI image model; the Codex tool did not report its model. Its thread ID,
also reported by Codex as the call ID, was
`01a210dc-9de5-7fc0-a751-d409c5f3c6cf`. The staging file was
`/home/rjroy/.codex/generated_images/01a210dc-9de5-7fc0-a751-d409c5f3c6cf/exec-5b0ac27d-cd6d-4a1b-b80a-82104c243783.png`.
The native and preserved files match byte for byte: 3,467,125 bytes, SHA-256
`34bc41de865c4e8a9fcd52c97c34787f48bc8a1fbaa34b2a7caea9ba2d9a8353`.

## Reproduce

From the repository root with Python 3.14.8 and ImageMagick 7.1.2-34 Q16-HDRI:

```sh
source=games/company-of-unlikely-heroes/assets-source/guild-book/petitions-hobby-smith-candidate
review=.lore/local/company-of-unlikely-heroes/storybook-nonbattle/petitions-hobby-smith
dest="$review/fresh-export"
python3 "$source/prepare.py" "$dest"
(
  cd "$dest"
  grep -E ' (plates|masters)/' "$OLDPWD/$source/delivery.sha256" | sha256sum -c -
)
```

The recipe checks the atlas SHA, exact extraction geometry, 8-bit RGB sRGB
opacity, unique pixels, and lossless pixel parity with the native quadrants.
It checks OpenRaster structure and reopens each master through ImageMagick's
OpenRaster decoder. Two exports produced byte-identical master and delivery
files. All three masters also reopened and exported in Krita 6.0.4.1 with
zero differing pixels compared to the PNGs. The numbered stock plates and
runtime assets are untouched.

## Inspection evidence

Opened the atlas, each PNG, and the actual-size [review sheet][review]. The
cut edges contain no neighboring quadrant art, and the baked watercolor
falloff remains visible at both sizes. Recruit is the amber close-up with
the fitting in a palm; Bonk is the close paired action with the recognizable
crook and the brigand looking back; Acid is the full-body throw with the
glass and separate training stand. At 145 px the vial is still visible,
though its glass outlines are less distinct than at desktop size. The figure
and target in Acid differ from the stock Mixologist plate, while the throwing
pose intentionally echoes the borrowed move.

The ignored evidence directory holds `ui-geometry.json`, the read-only
`probe_geometry.gd`, offline `review.py`, the generation result, and the Krita
pixel comparison. The sheet SHA-256 is
`20d6fb98c2a32cd7498247a0eb2b175c38b8edc5d2f903a5936548ba591afab0`.

[review]: ../../../../../.lore/local/company-of-unlikely-heroes/storybook-nonbattle/petitions-hobby-smith/review-sheet.png
