# Barnaby's Order of Last Resort: first art-direction review

**Current direction under `mind-garage-ddd`:** Crooked Storybook Fantasy, presented through a fixed three-quarter view. Model and animate in Blender; test those performances in Godot as painterly 2D sprites over an illustrated mission ground. The player still names their own guild. Barnaby's identity and appearance are not prerequisites for this study.

## How a mission is painted, and what stays movable

Ronald proposed Blender-rendered animation sheets for all heroes, civilians and opponents, rendered movable obstacles, and generated mission illustrations. The agreed first check is **one ferryman crossing before scaling the pipeline to the rest of the roster**. This supersedes the earlier open-ended 2D/3D comparison below. It's a choice to test this method, not approval of an unseen backdrop, final shader or production asset.

| Layer | Working direction |
|---|---|
| Actors | Keep editable Blender rigs and actions as masters. Bake consistent scale, lighting, facing and foot registration into transparent sheets. Pigment should travel with the surface; neither the ink nor an actor's boot should jitter from frame to frame. |
| Continuous ground | Generate a high-quality illustrated plate in OpenCode from a layout guide derived from the real board. Paint river, road and quiet playable ground continuously across square boundaries. Cracks and paving joints need not coincide with tiles. |
| Changing terrain and props | Leave the space underneath fully painted. Composite intact or broken spans, crates and anything that moves, changes or must occlude a figure separately. A moved crate takes its contact shadow with it. Use families of coherent images if modular ground is needed, not a fresh generated image for every square. |
| Tactical information | Godot owns cell coordinates, placement, depth order, selection, legal moves, danger and objectives. A thin, semitransparent dark outline shows every tile before selection, above the painted terrain and below the figures. It shows where a square is, not whether it is passable. Hover, selection and danger cues read more strongly than this base grid. None of these marks are baked into the illustration. |

**Pilot judgment:** look first at the running study at play size. Select each actor's cell; play a heal and a guard; move the crate off its starting square; remove the crossing over the river. Check that the feet stay planted, no shadow or span is left behind, and a threatened cell is legible without overwhelming the painting. Inspect the action in motion for flicker or a pasted-on silhouette. A pass buys us a camera and bake convention to try on the next class, not proof that every mission or facing will work. No changes to the shipped rescue, roster, or mission rules are part of this pilot.

## What to take from the references

- [Guild portrait: approved direction](../notes/a_richly_textured_hand_inked_watercolor_illustrat.webp). Look at the Knight's eyes checking one way while his shield covers the other. His shoulder is almost up to his ear. Against that hunch, the Wizard's raised hand and the Healer's burdened stance read as three different people even before you inspect their equipment. The distant aqueduct has real weight; it isn't in on the joke.
- [Comparison board: method exploration](../notes/a_detailed_art_direction_comparison_board_for_the.webp). Use the left panel as a control for line and shape, not as a production specification. The middle buys a clearer sense of volume but rounds off those nervous angles. The right suggests a promising compromise; the picture doesn't show whether it holds together through movement.
- [Original exploration brief](../notes/company-of-unlikely-heroes-art-direction.md). Preserve the reference and prior summon concept as design history. Neither the old painted sign nor the old title treatment dictates the new wordmark.

## First plate: The Knight at the guild steps

One chipped guild step, one Knight, one ally, one incoming threat. Keep the ally's silhouette simple; spend the detail on the Knight. Use the same fixed three-quarter camera, light, shield shape and ground marks across three beats:

1. **Idle:** He edges behind a shield he has plainly looked after better than his shoulder plate. Let us see both feet and that high shoulder. He should look wary before anyone draws a face.
2. **Guard:** His shoulders flinch but his front boot holds. The shield turns **toward the threat**, leaving a protected pocket for the ally. It should be possible to describe his choice with the effects switched off.
3. **Payoff:** The ally stays upright; the threat visibly redirects into an obstacle. The Knight is still braced for a blow that has already gone elsewhere. That's the joke, and he has done his job.

Review the action first at actual board size inside a 1280 × 820 gameplay frame, not enlarged on a white sheet. The current board uses 96 × 80 logical cells before scaling (`bridge_art.gd`). As a concrete stress test, a five-row board fitted by height at the current 315 px minimum leaves about **65 × 54 px per cell** (`315 / (5 × 80 + 2 × 34)` scale). That is a viewing condition, not an export size. Include the adjacent ally, obstacle, threatened cell and selected cell so a readable portrait cannot pass for a readable battle. Then inspect a close crop for broken ink contours, uneven planes of dented metal, blue cloth and mottled stone. Do not use a paper overlay as evidence for any of those.

## Decide the method on the same shot

**Animation constraint (Ronald):** Plan for a riggable cast. For a Blender candidate, separate the neutral modeling pose (likely a T-pose) from the acting poses: the Knight's wary hunch should come from his rig, not a bent rest mesh. Keep the shield detachable and leave shoulder and elbow clearance for the guard motion. Judge the shift of weight, shield contact and recovery in motion before accepting a production method; a beautiful still cannot establish that they work.

| Candidate | What it has to earn | What would rule it out |
|---|---|---|
| Drawn 2D poses | The shield turn and planted foot read with a few decisive contour changes. | Reversing direction or changing target makes the action ambiguous or requires a different character drawing rather than a reusable pose. |
| Illustrated 3D Knight, fixed camera | One rig changes pose and target while keeping the raised shoulder, shield edge and irregular contours. | A good close-up turns into a smooth toy in motion, or ink crawls across a held pose. |
| Drawn figure on a spatial set | Drawn character retains its personality while the step, contact shadow and occlusion explain position. | The shield floats off the step, covers the wrong square, or disappears behind scenery at the chosen angle. |

**Recommended order:** approve a single drawn pose strip first. Use it as the control for one illustrated-3D translation, not as a commitment to producing both pipelines. Try the drawn-figure/spatial-set alternative only if there is something concrete to gain. Keep the camera and action constant so a flattering angle cannot decide the comparison.

Ask Ronald, without captions: *Which figure is the Knight? Who is he protecting? Where did the threat land? Does he look frightened and good at this at the same time?* If the answers need a zoom, brighter effects, or a written explanation, revise the pose and values before detailing. Record the actual candidate and verdict here when they exist.

## What follows a successful plate

**Ronald's direction after the Knight blockout:** use the concept art for tone, not as a sequence to reconstruct. Set the Knight aside for now and move to the Healer. Her first study contrasts an open-handed heal with a compact staff bonk from the same tactical angle. A pose sheet can guide silhouette and rigging; only a later playable interaction can establish whether the player understands who acted, who received the action, and what changed.

Test a three-hero party against an enemy at board scale next: the Knight must not consume the visual space needed for the Wizard's reach, the Healer's staff, tile boundaries or forecasts. Carry the chosen shapes and materials into a commission posting and a recruitment portrait. Only then expand to the other heroes, enemies, summons, locations and the rest of the interface. A separate wordmark can follow once we know what sort of institution the name should evoke.
