# Trickster: model

`mind-garage-xmy.15`. Ronald approved [the exact concept sheet](../../concepts/non-hero-cast/04-odd-couple.png) for modeling. This [editable Blender master](trickster.blend), SHA-256 `0dfe1ba48e545da2c815d6ce4bf68cfacfc286fcb48a3e6704e060a191c963ba`. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

The Trickster wears a mustard split-tail coat and carries a short knife. The low knife feint contrasts with the rising, empty-hand signal and turn toward the partner. Switch Places is the once-per-battle swap with the living Ogre; the board, not the rig, owns the position exchange.

**Inspect:** [pose sheet](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/xmy-oddkin/trickster/pose-sheet.png) · [short motion study](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/xmy-oddkin/trickster/motion-preview.mp4). The small figures use approximately 26.5 pixels per metre. The larger figures use an actor-specific fixed crop, not a common height comparison. These are renders of the saved rig, not Godot captures. Hands and facial features are not expected to resolve individually at board size.

## Edit and review

Blender 5.2.2 LTS, +Z up, frontal rest facing −Y; ready turned toward screen right for the fixed cast camera. The source opens in Ready. Select the armature, then choose its take in the Action Editor. Each mesh is a separate rigid bone-parented sculptural part, including any carried kit. It is not a continuous skinned body for arbitrary retargeting. Neutral T at frame 1 is an identity-pose rest, separate from acting. 16 FK bones, 109 mesh pieces, 17 assigned procedural pigments. Neutral bounds, including kit, are 1.733 × 0.633 × 1.752 m. At 24 fps the other takes are: Defeat (1–25), Hit (1–15), Melee Feint (1–23), Quick Step (1–25), Ready (1–33), Switch Places (1–34).

The review reopens this exact file, checks rest transforms, parent/material assignments and action movement/ends, renders at the existing cast projection with its surface shader, and checks source integrity. Native action samples every second frame play at 12 fps; the comparison holds shorter takes after they finish. Root translation remains with the board. No production atlas or runtime change is included.

From the project root, with Blender, ImageMagick 7 and FFmpeg available:

```sh
art="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models"
out="$PWD/.lore/local/company-of-unlikely-heroes/non-hero-cast/xmy-oddkin/trickster"
PYTHONDONTWRITEBYTECODE=1 timeout 450 blender -b "$art/trickster/trickster.blend" -t 2 --python-exit-code 1 \
  -P "$art/../model-tools/oddkin/review_oddkin.py" -- "$out" all
python "$art/../model-tools/oddkin/compose_oddkin.py" "$out"
```
