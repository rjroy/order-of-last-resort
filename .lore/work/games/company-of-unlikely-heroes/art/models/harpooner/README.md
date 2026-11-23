# Harpooner: approved model and bake

For Barnaby’s Order of Last Resort, `harpooner` (`mind-garage-xmy.1`). Ronald approved the exact [revised Harpooner concept](../../concepts/harpooner/README.md) for modeling. He then approved the editable model shown in the pose sheet and motion preview below. Model approval is separate from acceptance in the running game.

## Editable source

[Accepted `.blend`](harpooner.blend), SHA-256 `e097b3aa7697ef09b02aa8713e12a32746c29c323c77c5b8b089ad5cd66b003a`, is a byte-for-byte promotion of the reviewed candidate, not a resave. It was authored with Blender 5.2.2 LTS (`d13f752e3b9c`). The `.blend` opens self-contained, with the actor facing −Y, +Z up, and the wearer’s right at −X. It includes procedural materials, a real T-rest armature, weighted main torso and mantle, articulated finger pieces, and supported rigid segment pieces as in the cast’s earlier blockouts. Neutral body bounds excluding the harpoon: 1.808 × 0.693 × 2.037 m. There are 32 bones, 173 body mesh and curve pieces, and 11 prop pieces.

The file opens on frame 1 of Ready. Select `Harpooner_Rig` and choose an action in **Dope Sheet → Action Editor**. Set the timeline end to the action’s final frame to review it alone. The acting keys are editable FK sampled every half frame from the source poses. Cape, scarf, satchel, coat tail, and fingers have separate controls. Select `Harpoon_Detachable` and use **Clear Parent → Keep Transformation** to inspect or detach the whole shaft in one piece. The prop mount is controlled separately from the casting hand. The source camera uses the production cast’s rotation; the wide review crop retains the full shaft after release without changing the actors’ registration.

| Action, all prefixed `Harpooner \|` | Frames at 24 fps | Intent |
| --- | --- | --- |
| Neutral T | 1 | Actual rest transforms, arms level. |
| Ready | 1–41 | Diagonal carry, small breath, matching ends. |
| Pursue | 1–21 | In-place lift, step, and plant for the existing `move`. The board owns cell displacement. |
| Close Thrust | 1–23 | Load at 5, low two-hand jab at 8, retract without releasing. Existing `enemy_attack`. |
| Ranged Cast | 1–29 | Shaft loads in front, leaves the open hand at 11, then exits. Frame 24 resets Ready. Existing `enemy_harpoon`; no haul, pull, or invented effect. |
| Hit | 1–17 | Flinch at 4, settle to Ready. |
| Defeat | 1–25 | Buckles to a knee and lets the harpoon drop; holds the terminal pose from 22. |

In the motion study a single prop briefly continues forward, then is hidden until the Ready reset. The atlas captures the actor and detached prop separately at release; the brief Blender flight is not the board path.

## Review

These review outputs are generated local evidence:

- [Pose sheet](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/harpooner/pose-sheet.png), 936 × 1085 PNG, SHA-256 `e759b74d0866d8c14a3635492ea0f46235b65b553aa6dc753ae6049ed3cc1eca`.
- [Motion comparison](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/harpooner/motion-preview.mp4), 900 × 600, 26 frames at 12 fps, SHA-256 `c0a4650500180b905716566de61d4c806f8fb402505962498e1247deb8d6969b`.
- [Tactical size proof](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/harpooner/tactical-scale.png), 660 × 160 PNG, SHA-256 `75af93e6d98ac3ac2cb41251f5760e3c6bc3faf49c888b3ef680a9473f48f83a`. Unenlarged figures at 26.55 px/m on a diagram of a cell, not an in-game capture.

Reopen and render the exact source from the repository root. If recreating the model rather than viewing the saved candidate, pass a new, nonexistent absolute path to the authoring script. Generation inputs are only these two Harpooner scripts and Blender; byte-identical Blender saves are not promised.

```bash
tools="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/harpooner"
out="$PWD/.lore/local/company-of-unlikely-heroes/non-hero-cast/harpooner"
model="$tools/harpooner.blend"
export PYTHONDONTWRITEBYTECODE=1

# Optional reconstruction, not needed for review:
# blender -b -t 5 --factory-startup --python-exit-code 1 \
#   --python "$tools/build_harpooner.py" -- "$out/reconstructed-harpooner.blend"

blender -b "$model" -t 4 --python-exit-code 1 --python "$tools/review_harpooner.py" -- check
blender -b "$model" -t 4 --python-exit-code 1 --python "$tools/review_harpooner.py" -- poses "$out/final-poses"
blender -b "$model" -t 6 --python-exit-code 1 --python "$tools/review_harpooner.py" -- motion "$out/final-motion"
bash "$tools/make_review_previews.sh" "$out"
```

The read-only verification reopened the model and checked the rest, detachable mount and all six acting takes at 306 half-frame samples. The rig root stayed fixed and all nonterminal takes returned to the exact Ready pose. Soles stayed at least 3.9 mm above the floor. The visible ranged shaft stayed at least 112.4 mm forward within the head-and-neck height band. During the loading and release samples the entire shaft stayed at least 22.1 mm forward of the head and neck bounds. At release, the gap from the casting fingers projected to 71.8 mm on the camera’s horizontal axis. Source checksum was unchanged; PNGs decoded and the MP4 fully decoded. Selected encoded video frames, poses, back view, and small proofs were inspected visually.

The lean stance, diagonal prop, and ochre shoulder shape survive the small preview. The low jab and upright release differ without an impact effect or caption. At that scale the open fingers and individual rips do not resolve, and the shaft crosses toward the next cell by design. These are model checks, not a deformation or per-surface collision review for arbitrary retargeting, and not a runtime test. Test both attacks and the detached shaft beside an actual target on the normal `company_rescue` board.

## Atlas

The [cast bake](../../../../../../../games/company-of-unlikely-heroes/tools/cast/README.md) produced `assets/cast/harpooner.png`, 1488 × 1750, SHA-256 `b445df064181b9dcf4c6b41ccf70a5be231edc52746869335b898b6ee6e71e99`. Seven clips share 53 rectangles across 56 timed samples. The adjacent `.import` was produced by Godot 4.7.2 with lossless texture compression, no mipmaps, and alpha-border repair. The target scene was not used to produce or verify that sidecar.

The generated `ranged_cast.release` detaches `harpoon_projectile` at F11 (417 ms), at `[64.481, -142.061]` atlas pixels relative to the ground anchor. For a left-facing cast, mirror the horizontal component around the ground anchor. The actor is empty-handed on F11 through F23. The PNG proof showed the held shaft at F10, the open hand and separate straight projectile at F11, and the dropped shaft in the held Defeat drawing. The verifier checked file identity, sample timing, rectangle bounds, clear padding, and the release contract. [Local atlas proof](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/harpooner/bake-proof.png) · [Registered proof in both facings](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/harpooner/bake-registered-proof.png).
