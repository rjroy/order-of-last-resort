# Village Troll: model

`mind-garage-xmy.6`. Ronald approved [the exact concept sheet](../../concepts/non-hero-cast/01-river-and-village.png) for modeling. This [editable Blender master](village_troll.blend), SHA-256 `8e33879195777ff6e4cff32310de546d2a5532e99d510929fb97f31b973dc4e3`. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

The Troll is a civilian follower. Its long, empty hands and borrowed shawl hang low until it stops beside a hero and brings one palm up. Displaced is an involuntary stagger. Leaves Square Alive holds the upright farewell; Defeat folds down for the separate mission-failure outcome. It has no strike.

**Inspect:** [pose sheet](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/xmy-oddkin/village_troll/pose-sheet.png) · [short motion study](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/xmy-oddkin/village_troll/motion-preview.mp4). The small figures use approximately 26.5 pixels per metre. The larger figures use an actor-specific fixed crop, not a common height comparison. These are renders of the saved rig, not Godot captures. Hands and facial features are not expected to resolve individually at board size.

## Edit and review

Blender 5.2.2 LTS, +Z up, frontal rest facing −Y; ready turned toward screen right for the fixed cast camera. The source opens in Ready. Select the armature, then choose its take in the Action Editor. Each mesh is a separate rigid bone-parented sculptural part, including any carried kit. It is not a continuous skinned body for arbitrary retargeting. Neutral T at frame 1 is an identity-pose rest, separate from acting. 16 FK bones, 160 mesh pieces, 19 assigned procedural pigments. Neutral bounds, including kit, are 3.841 × 0.744 × 2.224 m. At 24 fps the other takes are: Curious Follow (1–25), Defeat (1–25), Displaced (1–18), Hit (1–15), Leaves Square Alive (1–28), Ready (1–33), Stop Beside Hero (1–30).

The review reopens this exact file, checks rest transforms, parent/material assignments and action movement/ends, renders at the existing cast projection with its surface shader, and checks source integrity. Native action samples every second frame play at 12 fps; the comparison holds shorter takes after they finish. Root translation remains with the board. No production atlas or runtime change is included.

From the project root, with Blender, ImageMagick 7 and FFmpeg available:

```sh
art="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models"
out="$PWD/.lore/local/company-of-unlikely-heroes/non-hero-cast/xmy-oddkin/village_troll"
PYTHONDONTWRITEBYTECODE=1 timeout 450 blender -b "$art/village_troll/village_troll.blend" -t 2 --python-exit-code 1 \
  -P "$art/../model-tools/oddkin/review_oddkin.py" -- "$out" all
python "$art/../model-tools/oddkin/compose_oddkin.py" "$out"
```
