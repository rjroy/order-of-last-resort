# Ferryman crossing: art decision

**Question:** Can animated sprites made from the existing Blender rigs look at home on one painted mission board without hiding the information needed to take a turn?

Judge the **small view first**, then use the larger view to diagnose what you saw. A still can show the composition but cannot answer the motion question.

| Try it | Evidence for keeping the approach | A reason to revise |
|---|---|---|
| Find each hero's square, then select it. | The selection falls under the feet you predicted, not under the middle of the torso. | The angle or contact shadow makes a neighboring cell look occupied. |
| Watch a heal and a guard without reading their names. | You can distinguish the actions and identify the intended ally. Ink and highlights stay attached to the moving equipment. | Only a label tells you what happened; an edge shimmers or the figure seems to skate. |
| Move the crate and remove the span. | The crate's old square becomes ordinary ground; the river continues through the empty crossing. | A duplicate shadow, painted span or patch of mismatched paving gives away the layers. |
| Toggle the threat cue, then turn it off. | You can count the threatened cells. Turn the overlay off and the board reads as a place again. | Background marks look like danger indicators, or the cue obscures the actors. |

The stock board and rescue placements are in `games/company-of-unlikely-heroes/content/common.json` (`boards.bridge`) and `content/first_outing.json` (`encounters.company_crossing`). **D3** is the movable span's registration cell, **C3** is the crate's authored start, and **G3** is the safe bank. The pilot is a visual study with two actors, not a playable or rebalanced rescue.

**Plate provenance:** [Crossing ground](assets/crossing-plate.png), candidate generated on 2026-11-21 with `openai/gpt-image-2` using the [registered layout guide](authoring/layout-guide.md) as the composition reference and the guild portrait linked in [art direction](../../direction.md) for ink and watercolor treatment. Original 1536 × 1024 PNG SHA-256 `4f82c2e88167e11f9cf95813dd756805254e4c3dc5d343440e6f079a20a20e91`. It depicts the empty riverbed and two stone approaches, not the bridge deck. Use this exact file for reproduction; regenerating from the same guide need not reproduce the shoreline pixel for pixel.

**Decision boundary:** a successful pilot establishes one working camera, footprint and bake convention. It does not establish that all facings work, that the production roster is integrated, or that other missions can share this plate. Ronald's visual verdict is separate from technical checks.

**Player feedback:** Ronald endorsed the art and asked to see every tile before selecting one. Keep the ground plate unchanged; draw a quiet dark grid under the models so the stronger selection and threat marks still have distinct jobs.
