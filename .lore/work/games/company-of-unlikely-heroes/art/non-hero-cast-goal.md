# Barnaby’s Order of Last Resort: non-hero cast delivery

Fulfill `mind-garage-xmy`: 25 distinct character identities plus the animated Supply Wagon across the 20 current missions. The deliverable is what the player sees moving on the board in the main game, not a folder of models or pose sheets.

## Scope and first delivery

Read `bd show mind-garage-xmy`, the 26 child beads, and the [cast inventory](non-hero-cast.md). It maps each runtime ID to its missions, performance brief, and bead. Check it against the current catalog and cast manifest, including reserves. Leave the seven heroes and the already-delivered Skeleton and Zombie alone. Do not redesign missions, change combat rules, or invent actions to showcase the art.

Start with the Harpooner and Ferryman in `company_rescue`. Take this pair all the way into the playable mission before scaling production: the Harpooner has two distinct attacks; the Ferryman is a civilian trying to reach safety. At normal camera size, both should read without labels. Then group the remaining cast by missions where they appear together. Design and review the rival trio, bandit siblings, Ogre and Trickster, and Sheep and Shepherd alongside one another. Repeated placements of one runtime ID reuse its asset.

## Art, production, and approval

Use the established Crooked Storybook Fantasy direction and shipped Blender → baked animation sheets → Godot battle pipeline. Share rigs, cameras, and tooling where useful; give each identity its own silhouette, posture, and characteristic motion. A Harpooner striking should not look like a Hookhand reeling someone in. The bandit siblings should read apart without color. Give the sheep a quadruped performance and the wagon wheels, weight, and a load that reacts to movement. Neither needs a humanoid rig.

The `/goal` invocation authorizes concept generation for the full cast. Present clearly labeled concepts in small groups so Ronald can approve individual members. Once a concept is approved, build its editable rigged model in a suitable rest pose, animate it, and present the pose sheet and a short motion preview. Model approval authorizes baking, integration, and testing for that actor without another permission stop. Never infer visual approval from silence. While waiting, continue useful work on already-authorized assets; do not build a backlog of unreviewed models. If approval is the only blocker, present the exact candidates and decision needed.

## What counts as done

- Verify each actor in a real stock mission through the main battle renderer. Check its runtime ID selects the right art, its actual gameplay events trigger the right animations, and it returns to ready where appropriate without a placeholder flash. Inspect at normal camera size with other roles present.
- Include reserve arrivals, all three rivals, all three siblings, the flock, and the wagon advancing, stalling, and being destroyed. Use focused automated checks for mappings and cues plus reproducible mission launches for visual evidence. A Blender render, manifest entry, or passing headless test alone does not establish in-game appearance.
- Work on a dedicated branch. Preserve approved concepts, editable sources, bake recipes, and runtime assets in the repository; keep disposable previews and logs in `.lore/local/`. A fresh checkout must not depend on scratch files. Watch disk usage during batch renders.
- Keep the inventory current. Close and checkpoint-commit each child only after its source is approved and its in-game appearance is verified. Leave unrelated changes alone; do not push.
- Close the epic only after all 26 children meet their acceptance criteria and all 20 missions have been checked against the inventory. Hand off the best missions to launch to see the finished cast.
