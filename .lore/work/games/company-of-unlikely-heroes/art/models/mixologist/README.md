# The Mixologist

`mixologist-blockout.blend` is the accepted editable Blender 5.2.2 LTS Mixologist for *Barnaby’s Order of Last Resort*. Ronald approved the [exact concept](../../concepts/mixologist/README.md), with one instruction: leave out the recipient. On 2026-11-21 he accepted the exact model set after seeing its pose sheet and motion preview: “animations look great”. This is model acceptance, not runtime approval.

The model and renders contain only the Mixologist. Both her hands cradle the amber bottle for the close offer. The throw uses the other silhouette: a wide stance, one arm releasing a green faceted flask, and the free hand steadying her hip rack.

## Play and edit

The file opens on frame 1 of **Ready** with `Mixologist_Rig` selected. Choose an action in **Dope Sheet → Action Editor**, return to frame 1, and set the timeline end to that action’s last frame. Enable overlays to see the armature in Pose Mode.

| Action | Frames at 24 fps |
| --- | --- |
| `Mixologist \| Neutral T` | **1** matches the real armature rest with both arms out. |
| `Mixologist \| Ready` | **1** kit stowed at the hip. |
| `Mixologist \| Healing Potion` | **7** begins lifting the potion; **13** left palm supports the base; **17–23** two-handed offer; **24** potion gone; **36** closes at Ready. |
| `Mixologist \| Acid Toss` | **6** grip; **13** load; **16** final held frame; **18** clear release; **21** flask no longer shown; **32** closes at Ready. |

Each take is independent and has no NLA tracks. A rig supplies baked FK keys at half-frame intervals, with no live IK controls. Sleeves, cuffs, finger segments and breeches are weighted across joints. Smaller costume and facial parts are mesh or curves attached to bones. Show the `Fingers` and `Props and cloth` bone collections for detailed edits. `Hip_Rack_Detachable`, `Amber_Potion_Detachable` and `Acid_Flask_Detachable` are separate assembly roots. Select a root in Object Mode and use **Clear Parent → Keep Transformation** to detach it without breaking up the assembly. The acid switches from a grip-matched path to independent flight within the same editable action. The handoff ends without a recipient animation.

The model matches the cast’s metres, forward −Y, and up +Z. The acting views use the cast’s fixed three-quarter rotation and 2.47 m orthographic scale. Neutral T uses a straight front camera. There are no linked files, external textures or external rig dependencies.

## Reopen and review

From the repository root:

```bash
model="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/mixologist"
out="$PWD/.lore/local/company-of-unlikely-heroes/mixologist-blockout"
blender --background "$model/mixologist-blockout.blend" --threads 8 \
  --python-exit-code 1 --python "$model/review_mixologist.py" -- "$out/renders"
bash "$model/make_pose_sheet.sh" "$out"
```

Use `--check-only` after Blender’s `--` for grip, rest and structure checks without rendering. Use `--motion` in place of `--check-only` to render numbered review PNGs for each action at 12 fps. The scripts do not save the `.blend`. The sheet uses ImageMagick and Fontconfig, neither of which is a model dependency.

To regenerate the optional silent comparison, use `"$out/motion" --motion` as the script arguments after Blender’s `--`, then run:

```bash
ffmpeg -hide_banner -loglevel error -y \
  -framerate 12 -i "$out/motion/handoff/%03d.png" -framerate 12 -i "$out/motion/toss/%03d.png" \
  -filter_complex 'hstack=inputs=2,format=yuv420p' -c:v libwebp_anim -loop 0 -quality 84 "$out/offer-and-toss.webp"
```

- [Pose sheet and 65 × 54 px samples](../../../../../../local/company-of-unlikely-heroes/mixologist-blockout/pose-sheet.png)
- [Silent offer and toss comparison](../../../../../../local/company-of-unlikely-heroes/mixologist-blockout/offer-and-toss.webp)
- [Potion offer close-up](../../../../../../local/company-of-unlikely-heroes/mixologist-blockout/renders/handoff-detail.png)
- [Acid release close-up](../../../../../../local/company-of-unlikely-heroes/mixologist-blockout/renders/release-detail.png)

## Verification and limits

The reviewed files are identified by SHA-256. The sheet and motion preview are local evidence; the commands above regenerate the views from the accepted Blender source.

| File | SHA-256 |
| --- | --- |
| `mixologist-blockout.blend` | `8458bf889a27b57fc99698964c5dcceb981c9b60bf54ac3db3aff29cea48033f` |
| `pose-sheet.png` | `cb505728bba1aa13d87855c8eac0c7db8d218af020d2ac49c859e2fd9a7592cc` |
| `offer-and-toss.webp` | `e953afeffffd864cef62658d421862bff0cb75458c76158c876985716fafa391` |

Reopening confirmed one armature, 41 bones, four saved actions and 236 editable actor mesh or curve objects. The neutral figure and worn rack measure 1.838 × 0.447 × 2.118 m (width × depth × height), including the high bun. Both animated takes begin and end in Ready. All three detachable roots preserved their transform and a child’s transform in the read-only detach check.

At the offer frame, the base landmark is 4.8 mm from the left palm and the neck center is 10.7 mm from the right hand surface. At half-frame samples, the acid neck landmark stayed fixed relative to the throwing hand to within 0.001 mm while held; at release frame 18 it is 20.3 cm clear of that hand. The other hand is 5.6 mm from its rack bracing landmark. At release the front sole is 3.2 mm above the studio floor, the rear toe 6.0 mm above it, and the rear heel 68 mm above the toe. These are landmark and pose checks, not full mesh collision or cloth tests. The read-only review checks also cover the camera frame for key prop and shoe silhouettes.

The 65 × 54 samples are isolated from the board. The handoff reads mainly through two low arms and a compact stance; the toss reads through the high diagonal, rear heel pivot and detached projectile. At that size, bottle shape and grip detail are harder to distinguish. This is a model and pose study, not production skinning, full mesh collision validation, a recipient-effect study or a Godot integration. The next useful check, if separately authorized, would compare the two gestures on the board without labels.
