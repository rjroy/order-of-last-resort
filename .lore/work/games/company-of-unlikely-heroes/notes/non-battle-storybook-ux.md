# Barnaby’s Order of Last Resort: non-battle storybook UX brief

Use this brief with `/goal` to carry out `mind-garage-tkt.7`. This is a redesign of the **actual main game**, not a mockup or a separate launch mode. The player likes the current flow and mechanics. Change how the choices look and read, not what they mean.

## The player’s journey

Start with a normal launch and follow guild creation → commissions → recruitment and deployment order → field reports and route choice → battle → debrief and upgrade choice → next mission or return to guild. Include practice adventure selection. Preserve the one existing battle UX. Don’t redesign it again or introduce a second interface. Apply the new names to relevant battle labels so that a character recruited under one name doesn’t appear to be someone else when deployed.

Use the approved Gate and Frontier battles for the visual standard: *Crooked Storybook Fantasy*, with an illustrated world inside a modest physical book edge. See the [art direction](company-of-unlikely-heroes-art-direction.md) and [framed Marked-Up Illustration](../art/concepts/storybook-ux/marked-up-illustration-framed.png). Don’t simply put parchment behind the old panels. Each kind of illustration has a job: a portrait shows **who** you’re taking, a destination painting shows **where** you’re going, a report sketch shows **what someone noticed**, and a reward illustration shows **what changes**.

## Recruitment: guild portraits

Create one distinctive guild portrait for each of the eight classes below. Use approved cast concepts and models as references where they exist. Test each portrait at actual recruitment size and as a small crop beside a reward. Show capable, eccentric people, not incompetent punchlines. For example, the Knight can look anxious and still hold the shield like a professional.

| Existing class | Exact player-facing name |
|---|---|
| Bard | Bad Bard |
| Wizard | Enthusiastic Caster |
| Healer | Unimpressed Healer |
| Rogue | Daft Dodger |
| Knight | Anxious Knight |
| Necromancer | Friendly Crypter |
| Alchemist | Mixologist |
| Blacksmith | Hobby Smith |

Use these names consistently wherever the game displays the class. Preserve internal IDs, save compatibility, and the distinction between a character’s own name and their class. Make all eight portraits, but don’t invent or unlock mechanics, make Hobby Smith recruitable, promote the Mixologist placeholder, or disguise an existing mix-in as a finished class.

## Commissions and practice adventures: destination paintings

Give every actual destination its own painting. Show the place as an adventurer might first see it, not a screenshot of its tactical grid. On arrival, the player should recognize a landmark from the commission without having been told the solution. Reuse a destination’s painting wherever that destination recurs. Make the destination and the difference between a five-mission and a ten-mission job immediately apparent. Preserve the existing commission mix, routing, and lack of payouts.

## Field reports: a child drew these

Use crooked lines, peculiar proportions, and one emphatic detail. These should look like a child’s observations, not professional fantasy art with a crayon filter. Let the picture be funny about scale; keep the accompanying report text legible and trustworthy. A bridge could be magnificent in the commission painting and just two wobbly lines and a falling plank in the scout’s drawing.

Show the immediate encounter and **at most the onward clue already disclosed by the rules**. Never reveal the other branch or turn a hint about an encounter type into a spoiler for an exact mission. Key the art to information the player is allowed to see, not hidden route state. Reuse sketches when the disclosed clue is the same.

## Rewards: illustrate the change

Every implemented adventure upgrade definition gets its own identifiable image. Related upgrades can share a visual family, and repeated copies of one upgrade reuse its image. Show a changed action or object, not a generic glow or rarity badge. For example, *Long Staff* might show a second length of wood splinted onto the staff; *Strong Swing* might show the staff sweeping three helmets off their pegs.

Use the class portrait to identify who benefits. Keep the hero, effect, rarity, and remaining availability clear when comparing unlike offers. Keep the existing choice of **one reward total**, as well as tables, caps, probabilities, and adventure reset rules. Guild perks are out of scope.

## Execution and visual review

The accompanying `/goal` authorizes artwork generation and implementation. Inventory the actual classes, destinations, report clues, and upgrade definitions **before generating**. Begin with one connected visual study using real content: a destination painting, a recruitment portrait, a child’s report sketch, and an upgrade choice. Inspect them together at game size, correct the direction if needed, then carry it across the full inventory. **Don’t stop at the sample.**

Continue through implementation, testing, visual review, and corrections without stopping for routine decisions. Where exact artwork requires player acceptance, identify the candidate version and make it reviewable in context. Batch those visual decisions for morning; don’t claim approval for anything the player hasn’t seen. Preserve accepted assets and source provenance.

Keep art mappings with their content or in a small presentation manifest. Don’t scatter per-ID branches through UI code. A fresh game copy must not depend on `.lore/local`, `/tmp`, a generator, or an external service. Don’t use a paid external art service or install dependencies. Use `mind-garage-tkt.7` for the work. Leave unrelated issues alone. **Do not commit or push.**

## Verification and morning handoff

- Play the normal game in Godot at **1280 × 820**. Check mouse and keyboard, long names, recruitment and deployment order, both field reports, reward comparison, victory, defeat, and return to guild. Inspect the actual screens, not just the source artwork.
- Verify fresh-copy loading and full content-ID coverage. Check that changing an undisclosed future encounter cannot change the sketch for an otherwise identical disclosed clue. Run relevant regressions and fix failures.
- Provide the normal launch command, a short route showing strong examples, a contact sheet, and a few actual in-game screenshots. Report exact coverage for portraits, destinations, report illustrations, and upgrade definitions; distinguish distinct images from reused mappings. State what remains provisional or missing, and which visual decision would most benefit from the player’s eye.
