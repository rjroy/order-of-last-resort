# Road enemy cast (`olr-2wt`)

Ronald approved all 11 exact concept panels for modeling, then approved the exact models and staged atlases for integration on November 28, 2026. The selected models include the Lender V4 free-arm correction and the Twins/Giant right-arm revision. The other seven are unchanged from their initial review. These files record visual and source approval, not a claim about which events trigger a clip in the running game.

| Panel | Exact approved concept | Editable master, recipe and atlas |
|---|---|---|
| A1 | [Hired Hammer / Mercenary](road_hired_mercenary.png) | [Source package](../../models/road_hired_mercenary/README.md) |
| A2 | [Long Spearman](road_long_spearman.png) | [Source package](../../models/road_long_spearman/README.md) |
| A3 | [Friar](road_friar.png) | [Source package](../../models/road_friar/README.md) |
| A4 | [Armor Lender](road_armor_lender.png) | [Source package](../../models/road_armor_lender/README.md) |
| B1 | [Fresh Twin](road_fresh_twin.png) | [Source package](../../models/road_fresh_twin/README.md) |
| B2 | [Wounded Twin](road_wounded_twin.png) | [Source package](../../models/road_wounded_twin/README.md) |
| B3 | [Giant](road_swing_giant.png) | [Source package](../../models/road_swing_giant/README.md) |
| C1 | [Road Archer](road_crate_archer.png) | [Source package](../../models/road_crate_archer/README.md) |
| C2 | [Longbow](road_longbow_archer.png) | [Source package](../../models/road_longbow_archer/README.md) |
| C3 | [Windup Bruiser](road_windup_bruiser.png) | [Source package](../../models/road_windup_bruiser/README.md) |
| C4 | [Risen Soldier](road_bell_soldier.png) | [Source package](../../models/road_bell_soldier/README.md) |

The PNGs here are the exact lossless review crops. [Provenance](provenance.json) identifies each crop by panel and half-open rectangle `[x, y, width, height]` in its native sheet, and records the native and labeled sheet hashes. Each cohort came from one native OpenAI `image_gen` attempt via ChatGPT-authenticated Codex CLI 0.172.0; the rendering model was not reported. Approved stock sheets supplied art direction. The native Blender and packaged atlas files are also byte-identical to the approved candidates. No prior draft or review composite is a production input.

## Recheck or bake

Run from the repository root. The registered stock cast recipe for each role pins its exact native master. Bake to a fresh ignored directory; do not overwrite the runtime atlases to make a check.

```bash
cast=games/company-of-unlikely-heroes/tools/cast
role=road_armor_lender
out=.lore/local/road-enemy-cast-check/"$role"
python "$cast/bake_subset.py" "$out" "$role" --threads 2
python "$cast/verify_cast.py" --assets "$out" "$role"
python "$cast/verify_cast.py" \
  road_hired_mercenary road_long_spearman road_friar road_armor_lender \
  road_fresh_twin road_wounded_twin road_swing_giant \
  road_crate_archer road_longbow_archer road_windup_bruiser road_bell_soldier
```

Tools verified for packaging: Blender 5.2.2 LTS (`d13f752e3b9c`), ImageMagick 7.1.2-34, and Godot 4.7.2 (`ed1daf0bf`). Each role uses the stock registered orthographic camera and display scale; larger capture sizes where specified preserve the camera's pixels per metre. The 11 new manifest entries were added without changing the 36 prior entries or their model and PNG files.
