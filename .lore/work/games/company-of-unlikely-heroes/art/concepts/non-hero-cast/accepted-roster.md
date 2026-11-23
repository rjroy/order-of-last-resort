# Accepted non-hero models

Ronald approved all 24 exact editable models and their common finish on **2026-11-22**, and authorized integration. The approved normalized review index was SHA-256 `822f6b7f1612cc72d0d5728af923e0e54b22f8d6af6ae957dde170bd823277e7`. This does not establish acceptance of their in-game appearance or performance.

[The accepted roster JSON](accepted-roster.json) is authoritative. It lists the chosen `.blend`, SHA-256, reference capture anchor and representative review poses for each ID. Paths resolve relative to the JSON file. Use only its `actors` entries as inputs to integration. The five `superseded` entries identify the old Archer and flat-pigment versions of Bomber, Enemy Healer, Duelist and War Drummer; their unchanged files are retained in the corresponding `superseded/` folders. Hookhand was promoted byte-for-byte from the original reviewed scratch source. No other accepted binary was renamed or resaved.

The [common art direction](../../direction.md) calls for attached pigment, steady ink and consistent registration. The accepted study reuses each model's saved colour, uses one Standard fixed-angle orthographic cast light, and places a two-pixel warm alpha-derived contour under each drawing. It compares the exact shipped hero/actor frames and stages neutral and painted board-size views. The finer details can legitimately disappear at tactical scale. No screen overlay or additional material filter was approved.

## Reopen or render the accepted poses

From the repository root with Blender 5.2.2 LTS. Leave actor IDs out to check or render the full roster. `--output` writes transparent raw and final 320 px PNGs in a new local directory; omit it for a read-only reopen, source hash and action check. Requires ImageMagick 7 for rendering. The artifact checksums identify the approval evidence, not a requirement for old local files to be present.

```sh
art="$PWD/.lore/work/games/company-of-unlikely-heroes/art"
out="$PWD/.lore/local/company-of-unlikely-heroes/accepted-pose-recheck"
PYTHONDONTWRITEBYTECODE=1 timeout 300 blender --disable-autoexec -b -t 4 --python-exit-code 1 \
  -P "$art/model-tools/review_accepted.py" -- archer hookhand --output "$out"
```

This regenerates the approved poses and finish, not the layout or bytes of the historical HTML gallery. See the [shared model tools](../../model-tools/README.md) and each package README for its rig, actions and development studies.
