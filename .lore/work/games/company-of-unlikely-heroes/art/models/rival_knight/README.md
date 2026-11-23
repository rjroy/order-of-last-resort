# Mirror Company: Rival Knight

[Native master](rival_knight.blend), SHA-256 `f7fa59f3fc0e5cb77885b4c93d48f85ab4a57340d93e7b20f086dd3be7c875b8`. `rival_knight` in stock `mirror_company`, xmy.16. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

The [approved encounter sheet](../../concepts/non-hero-cast/05-mirror-company.png) has SHA-256 `86f030f21d6e1a75945f14afd021ca22ecb526c318dad43eee08164030b91edb`. The three rigs share fabrication conventions from the Harpooner source (body skeleton, FK limb solver, boots, facial landmarks and procedural pigments). The armor, shield, company tailoring, proportions and native acting takes belong to this knight. The riveted heater shield is mounted to `regalia`, which follows his solved left grip. He draws his weight back at F6, drives his shoulder and shield forward at F10, then recovers. No target movement is baked.

Blender 5.2.2 LTS, −Y forward, +Z up, 32 bones, 161 editable rendered pieces, 22 assigned materials. Neutral T bounds including kit: 2.275 × 0.531 × 1.888 m. Choose `Rival Knight |` actions in the rig's Action Editor: Neutral T (1), Ready (33), Move (21), Shield Push (23, for `knight_push`), Hit (16), Defeat (26). Durations in native frames at 24 fps.

[Poses](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/rivals/refinement/rival_knight/pose-sheet.png) · [Motion](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/rivals/refinement/rival_knight/motion-preview.mp4) · [Trio comparison](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/rivals/refinement/group-comparison.png)

## Reviewing any or all three rivals

The `.blend` files are self-contained masters; no script or scratch input is required to play their actions. All three reopened from their maintained paths. Integer-frame checks confirmed identity Neutral T, keyed motion, exact Ready returns on nonterminal actions, rooted performances and clear soles, hems and working props. Grip-origin error on the shield and padded staff was below 0.002 mm in armature space. This is not an exhaustive surface collision test. The registered review uses the shipped camera angle and ink-light shader, not a Godot screenshot. The shield rim and lean survive the common scale; its nail heads do not.

To regenerate review evidence from the repository root:

```sh
models="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models"
out="$PWD/.lore/local/company-of-unlikely-heroes/non-hero-cast/rivals/new-review"
blender -b "$models/rival_knight/rival_knight.blend" -t 3 --python-exit-code 1 \
  --python "$models/../model-tools/rivals/review_mirror_company.py" -- "$out/rival_knight"
```

The review script also accepts `check` after the output directory to skip rendering. Once all three rival sources are available, run the script for each and use the composer to assemble their comparison. The composer uses ImageMagick and FFmpeg, renders no new art, and decodes each encoded MP4.
