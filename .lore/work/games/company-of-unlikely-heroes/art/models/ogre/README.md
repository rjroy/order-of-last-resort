# Ogre: model

`mind-garage-xmy.14`. Ronald approved [the exact concept sheet](../../concepts/non-hero-cast/04-odd-couple.png) for modeling. This [editable Blender master](ogre.blend), SHA-256 `de684dfd64989017877291cfeaa44579f842616a55ec6e2e4d6659dfe5a67560`. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

The Ogre carries a hooped wooden beetle (a broad mallet). Both hands collect it for a slow load and downward strike. The swap reaction interrupts that weight: the free hand and boot reach out while the tool swings aside. This is the receiving role, not a second cast.

**Inspect:** [pose sheet](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/xmy-oddkin/ogre/pose-sheet.png) · [short motion study](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/xmy-oddkin/ogre/motion-preview.mp4). The small figures use approximately 26.5 pixels per metre. The larger figures use an actor-specific fixed crop, not a common height comparison. These are renders of the saved rig, not Godot captures. Hands and facial features are not expected to resolve individually at board size.

## Edit and review

Blender 5.2.2 LTS, +Z up, frontal rest facing −Y; ready turned toward screen right for the fixed cast camera. The source opens in Ready. Select the armature, then choose its take in the Action Editor. Each mesh is a separate rigid bone-parented sculptural part, including any carried kit. It is not a continuous skinned body for arbitrary retargeting. Neutral T at frame 1 is an identity-pose rest, separate from acting. 16 FK bones, 111 mesh pieces, 17 assigned procedural pigments. Neutral bounds, including kit, are 3.490 × 1.026 × 2.287 m. At 24 fps the other takes are: Defeat (1–25), Heavy Strike (1–41), Heavy Tread (1–25), Hit (1–15), Ready (1–33), Swap Reaction (1–26).

The review reopens this exact file, checks rest transforms, parent/material assignments and action movement/ends, renders at the existing cast projection with its surface shader, and checks source integrity. Native action samples every second frame play at 12 fps; the comparison holds shorter takes after they finish. Root translation remains with the board. No production atlas or runtime change is included.

From the project root, with Blender, ImageMagick 7 and FFmpeg available:

```sh
art="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models"
out="$PWD/.lore/local/company-of-unlikely-heroes/non-hero-cast/xmy-oddkin/ogre"
PYTHONDONTWRITEBYTECODE=1 timeout 450 blender -b "$art/ogre/ogre.blend" -t 2 --python-exit-code 1 \
  -P "$art/../model-tools/oddkin/review_oddkin.py" -- "$out" all
python "$art/../model-tools/oddkin/compose_oddkin.py" "$out"
```
