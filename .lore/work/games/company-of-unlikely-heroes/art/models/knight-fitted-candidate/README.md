# The Knight, fitted

Four editable animations for the Hobby Smith’s Try This, approved for production. The scope is the fitted Anxious Knight only. The character, kit and appearance come from the exact [cast master](../knight/knight-guard-blockout.blend) pinned in `tools/cast/masters.json` (`0bdf470f4472f2ee269337e458b605bf53be0f36f700e9ebbf8156147e10b45b`). See the [art direction](../../direction.md), [cast bake guide](../../../../../../../games/company-of-unlikely-heroes/tools/cast/README.md) and [Try This conversion register](../../../notes/hobby-smith-design.md). The stock master is unchanged.

## Takes and cue proposals

All four are new takes on the accepted Knight rig. The shipped controls below were checked side by side at board scale, not inferred from their names. Times are measured from F1 at 24 fps.

| Fitted form | Use of existing work | Proposed key moment and resolved event |
|---|---|---|
| **Pull** (`fitted_pull`, from `knight_push`) | The shipped Rescue Line reaches and hauls, but the gesture is largely hidden by the shield and has little change in weight. The new take reaches low with the free hand and reels it back with a deep, planted brace. No recoil or fall. Render the same action with the shield hidden when it is away. | **F14 / 542 ms**: begin the recipient slide on the resolved `pull`. At most one recipient; read its actual origin and landing. |
| **Clear the Floor** (`clear_the_floor`, from `knight_aura`) | Guard closes the shield over the chest and braces against incoming force. The new take gathers low and opens shield and free arm in a broad sweep. The shield stays attached. | **F14 / 542 ms**: the spread accents the ordered group of resolved `push` events. One wearer take, not one per occupant. No fictitious movement for blocked or resisted targets, no impact damage and no Guard shimmer. |
| **Safety Distance** (`safety_distance`, from `knight_rescue_line`) | Rescue Line pulls inward. The new take raises and holds an upright stop palm and leans out toward the recipient. Same action with the shield hidden if it is away. | **F13 / 500 ms**: begin the friendly recipient's outward slide on the resolved `push`. Keep the palm out while they move; no weapon hit or fall implied. |
| **Lend a Shield** (`lend_a_shield`, from `knight_shield_throw`) | Shield Throw winds up and strikes with one arm. The new take brings both hands toward a low offer, tips the shield forward, then opens empty hands. Reuses the complete `Shield_L_Detachable` hierarchy and the exact Shield Away finish, not the hostile throw clip or its release drawing. | **F18 / 708 ms**: split off the shield at the authored mount and carry it to the resolved `shield_drop.position`. Last held drawing is F17. Pair the recipient’s `status` (`status_id: lend_a_shield`) with the drop; show cover on arrival instead of a hostile impact. The proof’s travel is illustrative, not a prescribed game duration. |

Use the committed `fitted_conversion.ability_id` to distinguish these takes from the original actions. It identifies the Knight, names the conversion, and may include the target, but does not prove a displacement or supply a resolved landing. Use the following committed effect events for the actual recipient, arrival and cover. Keep their resolution order; gameplay timing stays unchanged. An ordinary fallback, forecast or preview is not a converted performance.

## Edit and reproduce

`knight-fitted-actions.blend` contains only the four `Knight | Fitted | …` Actions (candidate SHA-256 `79626de03bee6b7074310de17212d4461b7b52663de600c17b19612d08b3f675`). It has no model, materials, scene or copy of the Guard action. Append the Actions into an **unsaved working copy** of the pinned donor with Blender 5.2.2 LTS. Select `Knight_Rig`, make an appended Action active in the Action Editor, and use its `Knight_Rig` slot. The Actions are open for direct FK editing: torso/arms are sparse, while leg keys pin the boots at each integer frame. Rig orientation and scale are unchanged: forward −Y, up +Z, metres. F1 and each terminal key (29, 30, 31, 32 respectively) match donor F8. Lend uses the same skeletal finish but leaves the shield off the wearer.

The Action marker and `prop_release_frame` field define the Lend split. The prop’s bones remain evaluable in the rig so the renderer can get its exact departure pose. The review script shows the shield through F17, hides the complete hierarchy from F18 in the actor render, and renders the separate prop at F18. The Action alone does not draw flight or choose a recipient. Its F18 release offset from the registered ground anchor is `[63.731, -99.813]` in full-size cast pixels before display scaling; obtain it from the renderer after any edit. Mirror X with the actor if used later. The final board marker belongs on the resolved drop tile, not at an inferred position.

From the repository root, rebuild to a **fresh** local path, then reopen and compare:

```sh
model="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/knight-fitted-candidate"
out="$PWD/.lore/local/knight-fitted-rebuild"
mkdir -p "$out"
blender -b "$model/../knight/knight-guard-blockout.blend" -t 4 \
  --python-exit-code 1 --python "$model/knight_fitted.py" -- "$out/knight-fitted-actions.blend"
blender -b "$model/../knight/knight-guard-blockout.blend" -t 6 \
  --python-exit-code 1 --python "$model/review_knight_fitted.py" -- \
  "$out/knight-fitted-actions.blend" --output "$out/renders"
python "$model/compose_review.py" "$out/renders" "$out"
```

The build script does not replace an existing file. For a check of the exact delivered file instead of a rebuild, pass `$model/knight-fitted-actions.blend` to the review script. Omit `--output` for saved-file checks without rendering. The review scripts use the existing cast ink renderer, ImageMagick 7.1.2-34 and Fontconfig (Noto fonts for labels). No Godot, atlas update or runtime test is involved.

## Evidence

- [At-size shipped/candidate pose comparison](../../../../../../local/knight-fitted/knight-fitted-board-proof.png)
- [At-size motion with illustrative neighboring figures](../../../../../../local/knight-fitted/knight-fitted-board-motion.gif)

## Production shelf and protective tap

The authorized borrowed-Bonk variant is in the separate editable [cover Action](knight-cover-actions.blend), SHA-256 `3128a8e40d6619be5dca7d12580aa9edd91864bc13648a0dd21efeeb0daa06f6`. The free hand dips into a low tap as the Knight bows into a short planted brace. It is not the stock overhead Bonk. Start and end match Ready; F13 (500 ms) is the cover beat and F28 is Ready. `keep_your_head_down_unshielded` uses the same pose with the complete shield hierarchy absent. The brace does not injure, taunt, or move anyone. Rebuild this separate library with the command above, replacing `knight_fitted.py` with `knight_cover.py` and using a fresh output path. The authoring script checks the hand and shield fit, planted boots and Ready seams against the pinned stock rig.

The [wearer recipe](../../../../../../../games/company-of-unlikely-heroes/tools/cast/supplements/knight.json) adds nine clips including shield-away variants and a separately registered Lend shield. The Lend release stays at F18 (708 ms), `[63.731, -99.813]` atlas pixels before display scale and facing; its prop clip is `lend_a_shield_prop`. The standard [supplemental build](../../../../../../../games/company-of-unlikely-heroes/tools/cast/README.md#supplemental-wearer-performances) produces one 1792 × 3655 `knight.png`. Its SHA-256 is `1b973af08975ee5eadf9bfe8b28be7cdd0d77e0e5d5b3ea29b8254ba050be7ec`. Verification preserved the entire shipped top-left RGBA and all 105 stock samples, then checked alpha padding, bounds, frame timing and release metadata on the finished atlas. See the [65 × 54 tile proof](../../../../../../local/cast-bake/knight-wearer.7iYCMNQL/board-proof.png) for the shield states, low tap and detached release.

The palette, camera and registration use the cast recipe; actor scale is matched to the 65 × 54 px small-board cell. Full captures are 320 × 320 px, at 104.918 px/m with the anchor at `[160, 248]`. The exact package reopened on the donor without writing either file. It passed the Ready seams, integer-frame foot drift (under 0.01 mm) and sole heights (4.00 mm throughout), base-mesh contact at the upper pauldron/head and shield face near the actor’s torso, arms and fingertips, and crop integrity on the rendered samples. These are sampled fit checks, not a full physics or cloth test. At small size the direction of motion is clearest together with the corresponding recipient movement; finger and eye detail is not a reliable cue.
