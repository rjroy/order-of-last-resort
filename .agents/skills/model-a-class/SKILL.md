---
name: model-a-class
description: Build or revise one game character from a chosen class through concept review, an editable rigged Blender model, and a rendered pose sheet for approval. Use for “model the next class” and “work on the healer next,” not to design boards or integrate the roster into Godot.
---

# Model a class

One character at a time. The user chooses the target and judges two things: **the concept** and **the modeled character in pose**. The agent owns the work between those decisions. A request to document or discuss this workflow is not a request to make art.

1. **Pick the target.** Use the class the user named. If none is named, recommend one and let the user choose. Read the actual class abilities, the game's art direction, and the conventions of its existing models. Identify what the player needs to distinguish: for example, an outward heal, a self-heal, and a short staff bonk. Use concept art for tone and identity, not as a scene to reproduce.
2. **Show the concept.** Use `asset-workflow` and `concept-art` to make a character study that establishes silhouette, working kit and the most useful action contrast. Show the actual image. Revise if requested; record approval of the exact version before modeling. Reuse an already approved concept. A second turnaround approval is not routine: make working views yourself if needed and ask only if a consequential design choice remains. Once the concept is approved, proceed directly with the authorized model.
3. **Build and verify without intermediate reviews.** Use `blender-model` and `blender-visualize`. Produce a self-contained, editable `.blend` with a riggable neutral rest pose (normally a T-pose), appropriately attached props, and replayable poses or short actions based on the class's mechanics. Match the cast's scale and orientation. Reopen the saved file, inspect actual renders and correct material problems such as an obscured action, a slipping grip or armor cutting through the face. Do not turn individual bones, poses, diagnostic renders or routine fixes into approval requests.
4. **Present one pose sheet.** Render it from that exact `.blend`, not from the concept generator. Include a neutral view and the few poses that best distinguish this class at a consistent tactical angle and size. Link the editable file and, if timing matters, one short motion preview. State what reads, what remains uncertain, and ask for the user's model verdict. If they request changes, revise the candidate and present the updated sheet; don't restart concept exploration unless the design changed.
5. **On approval, continue.** Record the accepted model version and pose-sheet reference. Move to the next agreed target, or recommend one if none is queued. Do not silently start another class during a board or scheduling discussion.

Keep accepted concepts and editable sources in the game's established art package; for *Barnaby's Order of Last Resort* these live under `.lore/work/games/company-of-unlikely-heroes/art/`. Keep regenerable review renders under `.lore/local/` and document how to reproduce them. Do not overwrite accepted originals.

**Stop at model acceptance.** For this roster, defer Godot integration until the existing classes are modeled and integration is requested. Blender is the authoring source either way: live 3D actors and pre-rendered sprite animations are both open options. Pose-sheet approval does not decide the board camera, export pipeline, or whether an action reads in play.
