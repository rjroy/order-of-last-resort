# The Zombie

Accepted editable Zombie model for *Barnaby’s Order of Last Resort* (`mind-garage-ddd.11`). Ronald approved the [revised throw](../../../../../../local/company-of-unlikely-heroes/zombie-blockout/throw-v2/action-comparison-throw-v2.mp4) and its [pose sheet](../../../../../../local/company-of-unlikely-heroes/zombie-blockout/throw-v2/contact-sheet-throw-v2.png). Accepted `.blend` SHA-256: `b4b9bb6bca976144125f8f684fcccd774dda178ab83f920c3617ca9674a4ca0d`. The hand stays empty through the follow-through; the flower-tied rock may pop straight back into the hand upon entering Ready. No retrieval or reload animation is needed. This model does not replace the static summon or its board sprite.

## Source and silhouette

The approved direction is [First Greetings](../../concepts/necromancer/first-greetings.png), SHA-256 `fed436ee36ed767e9eecd232e55d74b8cf1f75ea6e994d3243b977164463f96f`. The actual starting point is the [accepted static Zombie](../../../../../../../games/company-of-unlikely-heroes/assets/summons/source/zombie.blend), SHA-256 `46df5e2444ac3b96fa875aa9d5546d1c8c9dfa52e3adfa610abcaaa1d57a6b4f`. The [static source package](../../../../../../../games/company-of-unlikely-heroes/assets/summons/README.md) describes its board sprite.

The new model keeps the original 372 body and costume pieces and 106 prop pieces, including the cloudy eye, dry split cheek, apron, gardening tools and daisy lashed to slate. The head and clothes were straightened and the gesture-built arms were reshaped into a true T rest. The slouch is now in the rig. The woven edges, tool pocket, knots, patches and rolled cuffs are still separate pieces. Weighted meshes preserve the continuous wrist, soft joints, shirt and apron; rigid details follow their bones. The shoulder seams tuck into the shirt to stay seated during the action. The front trouser volume is eased beneath the apron, which tips with the crouch. Moving meshes sample the original procedural pigment in bind coordinates so the main mottling moves with the character. An inventory comparison found the original mesh counts and face material indices intact on all 204 native meshes, with 59 bendable curves converted to skin-ready meshes. The remaining 215 curves are still editable. There are no external textures or linked libraries.

The original 32-bone rig now has one non-deforming preview flight bone. It uses metres, +Z up, −Y forward, and wearer’s right at −X. Bare neutral geometry (without the prop) measures 1.780 × 0.448 × 1.852 m; Ready is 1.804 m tall. The accepted Skeleton is taller (1.913 m at rest). The acting views use its exact tactical camera transform and 2.47 m orthographic scale. The 65 × 54 views use the same rotation and horizontal scale (about 26 px/m), with a vertically shifted crop to hold the shorter frame.

## Play and edit

The scene opens at Ready. Select `Zombie_Rig`, then choose a take in **Dope Sheet → Action Editor** and set the timeline end to match. Turn on overlays to see the color-coded bones; the `Fingers` bone collection is hidden by default for clarity. The legs use FK curves baked at half-frame intervals. Say Hello keeps both boots planted. During the throw, the far boot rocks onto its toe while the near boot stays flat. Spine, arms, head and hands use sparse keys. Neutral, Ready and Say Hello keep their original poses. Offer Flower begins at Ready and ends empty-handed. It is a one-shot take; returning to Ready or replaying it resets the gift outside that performance.

| Action | Beats at 24 fps |
| --- | --- |
| `Zombie \| Neutral T` | **1** is the actual armature rest. The review hides the prop in neutral views so the hand bind shapes are visible. |
| `Zombie \| Ready` | **1–25** holds a soft slouch with the gift low. |
| `Zombie \| Say Hello` | **7** notices someone; **19–25** the smile and head get too close, with the free hand up and the gift held low; **36–45** gives space again. The nearest other character, friend or foe, backs one tile if it is open. The Zombie does not strike or shove them. |
| `Zombie \| Offer Flower` | **14** hefts the gift back high; **19–22** puts his weight into a lopsided overhand sling; **22** releases; **26** the empty palm and tumbling flower-rock are both visible; **32** the gift is on its way down while he catches his balance; **47–57** he settles empty-handed. The game targets an opponent up to two cells away for 1 damage. The authored arc previews the throw only. |

**Host cue:** `Zombie | Offer Flower` has an Action marker named `Gift Release` at **F22, 24 fps** (0.875 s after F1), also stored as `Release frame` and `Release bone` action properties. `gift_socket.R` gives the release transform; the prop root `Daisy & fieldstone` sits at the stone with a fixed offset from that socket. The root follows the hand through the windup, then a stepped `gift_airborne` channel switches to the `gift_flight` bone at the same world transform. The stone, binding, stem, leaves and petals move together without snapping back during the take. For a free Blender prop, mute the preview flight constraint and clear the root’s parent with **Keep Transform**. The flight curve is for review, not a two-cell calibration or gameplay projectile. No target, collision, impact or damage is authored.

## Reopen and review

From the repository root:

```bash
model="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/zombie"
out="$PWD/.lore/local/company-of-unlikely-heroes/zombie-blockout/throw-v2"
blender --background --disable-autoexec --threads 8 "$model/zombie-blockout.blend" \
  --python-exit-code 1 --python "$model/review_zombie.py" -- "$out/renders"
bash "$model/make_review_previews.sh" "$out"

# Optional silent comparison
blender --background --disable-autoexec --threads 8 "$model/zombie-blockout.blend" \
  --python-exit-code 1 --python "$model/review_zombie.py" -- "$out/motion" --render-only --motion
bash "$model/make_review_previews.sh" "$out" --motion
```

`--check-only` skips rendering. These helpers reproduce the validation and previews from the saved `.blend`; they do not rebuild the model. Review uses Blender 5.2.2 LTS, Cycles CPU, ImageMagick and Fontconfig. The optional MP4 also uses FFmpeg with `libx264`.

- [Revised pose sheet with six unscaled 65 × 54 samples](../../../../../../local/company-of-unlikely-heroes/zombie-blockout/throw-v2/contact-sheet-throw-v2.png)
- [Revised silent action comparison](../../../../../../local/company-of-unlikely-heroes/zombie-blockout/throw-v2/action-comparison-throw-v2.mp4)
- [Dry cheek](../../../../../../local/company-of-unlikely-heroes/zombie-blockout/throw-v2/renders/face.png), [held gift](../../../../../../local/company-of-unlikely-heroes/zombie-blockout/throw-v2/renders/grip.png), [empty hand](../../../../../../local/company-of-unlikely-heroes/zombie-blockout/throw-v2/renders/empty-hand.png), [side release](../../../../../../local/company-of-unlikely-heroes/zombie-blockout/throw-v2/renders/release-side.png)

## Verification

Accepted throw model SHA-256: `b4b9bb6bca976144125f8f684fcccd774dda178ab83f920c3617ca9674a4ca0d`. The superseded careful-lift draft (`42e4f209a5170a6fb44ae26dae69708953f5bd4caddf25bb8d8ba63ca4b1538f`) was used for comparison, not as a build input. Before retirement, direct comparison found all 478 modeled pieces and the 32 rest bones unchanged, and matched the three protected actions at every whole frame.

The reopened checks cover the T rest, four actions, planted contact, gripped and airborne prop states, continuous release, no snap-back before the take ends, and tactical framing through F32. At F26, the measured hand and gift silhouettes have at least a 4.5 px gap on the 65 × 54 view. No overlaps were found among the significant surfaces checked at whole frames. The cloth is posed, not simulated. The side wraps and waist still intersect the trousers outside the visible loose front panel. The checks are for these authored actions, not a guarantee for arbitrary poses.

## What to judge

The small views should distinguish a head-first greeting from a high, awkward throw with a visible gap between the empty hand and the gift. The twine and individual fingers need the close views. The preview has no neighboring character, board overlays or target response. If the model is accepted, the useful next check is whether this still feels like an overeager gift when a real target steps or reacts in play.
