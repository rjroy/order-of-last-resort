# Designing balanced road missions

Use this guide for encounters offered at commission forks. It is a companion to
[Adding a playable class](adding-a-playable-class.md). For named destinations, see
[Designing balanced commission finales](designing-commission-finales.md).
The class guide asks why you would bring a hero and when you would spend the
company's one direct command on them. A road mission should ask a question worth
spending that command on, with different companies able to answer it in
different ways.

Use [Designing commission tiers](designing-commission-tiers.md) for slot
eligibility, variants, and checks across successive road missions.

A **balanced road mission** gives the company a fair chance to read the danger,
make a consequential choice, and win by understanding its heroes. It can favor
one company over another. It should not require the right hero, a lucky reward,
or prior knowledge of a rule it never shows you. A costly win can be fair; a
mission also has to make sense as one leg of a longer outing.

## The original road baseline

Before tiering, the [commission catalog](../games/company-of-unlikely-heroes/content/expedition/commissions.json)
offered 11 road missions across four kinds: skirmish, ambush, formation,
and rival band. All 11 require defeating every opponent. In the
[route draw](../games/company-of-unlikely-heroes/expedition/commissions.gd),
entries with destination descriptions are excluded from the road pool. The
wagon escort, quiet retrieval, ritual, and other specialized objectives in the
[game's mission list](../games/company-of-unlikely-heroes/README.md#explore-the-missions)
are useful comparisons, not examples from that road pool.

What varies on the road is the decision inside the fight:

| Existing mission | What to carry forward |
|---|---|
| **The Shield Wall** | The Archer gets protection from adjacent Shieldbearers. You can change the formation or go after the guards. A particular hero can make one answer easier without being the answer. |
| **The Harpoon Squad** | Hookhand's pull can put a hero in reach of the Bruiser. Judge the danger after the pull, not just from the opening positions. |
| **The Explosive Situation** | A dying Bomber hurts nearby friends and foes. The same danger can ruin an attack or set off a chain reaction in the company's favor. |
| **The Last One Standing** | Defeating a Bandit strengthens the survivors in different ways. The question isn't merely who you can defeat first, but which stronger survivor your company wants to face. |

These are design examples, not proof of balance. The
[encounter catalog](../.lore/work/games/company-of-unlikely-heroes/experiments/005-encounter-catalog/record.md)
and [commission route](../.lore/work/games/company-of-unlikely-heroes/experiments/006-commission-routes/record.md)
experiments verified behavior, not human enjoyment or difficulty.

## Rules for a balanced mission

1. **Start with one tactical question.** Name the tradeoff before choosing
   enemies or building a board. Write two concrete rounds: one where spending
   the direct command to answer that question pays off, and one where leaving
   the standing orders alone or commanding someone else is better. If the player
   would make the same choice in both rounds, change the pressure. A new
   objective should change what the player tries to accomplish, not just rename
   the fight.
2. **Keep the rules dependable so the heroes can be complicated.** Spell out
   what wins, what loses, and when each is checked. Say who or what counts:
   heroes, enemies, summons, civilians, or forced movement, where relevant. Say
   which outcome takes priority if both would happen in the same round. Use
   standing orders to create friction the player can anticipate, work around,
   or turn to their advantage. The board shows the relevant state; Forecast
   shows what the staged round would do; the committed round follows those
   same rules.
3. **Offer different answers, not a hidden roster check.** Show an answer with
   ordinary movement and a plausible starting company, and another that leans
   on a different company's abilities or orders. The fallback can be riskier or
   slower. Don't assume a specific learned ability, standing order, or outing
   reward. Conversely, check whether a common ability bypasses the entire
   decision at negligible cost. Reward a clever shortcut, but don't make it the
   routine answer.
4. **Budget pressure in commands, not just HP or rounds.** Count the commands
   needed to make progress, which actions standing orders can cover, and when
   threats require intervention. Compare that with a shipped road encounter
   that asks for a similar kind of attention. Leave room for an understandable
   setback and a changed plan. A serious mistake can still cost the mission if
   the forecast made the stakes clear. Prefer threats the player can slow,
   divert, or accept. If there is a deadline, show the command budget on a
   plausible route and explain the slack. Avoid clocks that require perfect
   movement or leave nothing to do after reaching safety.
5. **Balance the win the company carries forward.** Survivors keep their HP;
   fallen heroes return at 1 HP. Check the same mission with an unupgraded
   company and with a plausibly wounded company, then check the cost it leaves
   for the next leg. Benchmarks are rounds, commands spent on progress versus
   recovery, HP remaining, and heroes fallen. Compare those with existing
   encounters, not a single target win rate. A harder route can be a real
   choice if the report signals the risk; it shouldn't quietly tax every
   company more for the same progress.
6. **Make the fork a choice before combat starts.** The immediate report names
   the objective, any unusual loss or timing condition, and the tactical
   constraint that could change which road a player picks. Every wording
   variant must disclose those facts. Leave room to discover the best answer,
   not the rules. The onward clue describes what may follow and isn't a
   substitute for the immediate brief. Check the mission against plausible
   alternatives at a fork: each road should give some company or plan a reason
   to prefer it. Reuse an existing rule or mission kind when it honestly
    describes the encounter; distinguish what can be authored in data from what
    needs a new rule.

## Road balance rubric

Compare the exact mission or variant with its base or a shipped road that asks
for similar attention. Hold the company, deployment order, standing orders,
loadout, upgrades, and entry HP fixed to isolate the change. Then check
plausible arrivals at the intended tier.

| Check | Evidence to bring to review |
|---|---|
| **Tactical pressure** | Save a Forecast where the threat changes the best target, tile, or timing. Name what would happen if the company left its orders alone. Extra enemies count as pressure when their actions compete for attention, not just when there are more bodies to clear. |
| **Usable counterplay** | Stage two legal responses and note what each gives up. Commit at least one and check what remains possible after a plausible mistake. Revise if both responses need the same specialist, or if a routine opening lets the company ignore the threat at no meaningful cost. |
| **Command and HP cost** | Mark the round when the main threat stops mattering. Before and after that point, tally direct commands spent on progress versus avoiding damage or recovering. Record entry HP, next-leg HP before rewards, and falls by hero. Check whether a wounded company can still make progress without spending every command on survival. |
| **Incremental tier change** | Name the smallest change that adds a decision or keeps a live threat in play for another consequential turn. For an HP change, show which hit sequence now leaves the enemy alive and what it gets to do. If the opening, best response, and danger are unchanged and only cleanup gets longer, don't count that as evidence for a higher tier. |

The road rebalance (`d585c01`) and the stock Borrowed Armor pair give concrete
comparisons to try. Use the authored changes to form testable hypotheses, not
as proof that a road or its tier is balanced.

- **The Friar's Last Favor:** The pass moved the Friar into line with his
  crew and added a Grunt. Compare killing him before spreading damage with
  saving him for last. What can the extra Grunt do while you wait, and who
  actually benefits from the heal when the Friar falls?
- **The Cowardly Captain:** The third Grunt starts beside the Captain. Compare
  breaking that formation with cutting off the Captain's retreat. Check which
  Grunts still get the adjacency bonus when they attack.
- **Crossfire at the Fuse Line:** A second Hookhand and Harpooner add another
  pull and another ranged threat. Check where each pull leaves a hero and who
  would be beside the Bomber when it falls. Can one command manage both
  threats, or must the company choose which risk to accept?
- **The Unfortunate Healer and The Mirror Company:** Stock enemy heals no
  longer run out. Compare spreading damage with finishing one target before
  the next heal, separating a patient from support, or taking out the healer.
  In Mirror Company, check what that focus fire gives up against the rival
  Wizard's nearest-target blast.
- **Borrowed Armor / Veteran Crew:** Use this stock HP-only pair as a
  comparison. It shares placements and the armor rule. Check whether the
  tougher Lender gets another round of protecting an ally, changing when to
  focus on the Lender, or whether the extra HP mostly costs hits once the
  company has already broken the formation.

## Design the field report image with the mission

**A finished road report needs one truthful child-scout crayon sketch of the
immediate encounter.** At a fork it should give players a quick visual reason
to read one report differently from the other. Pick **one thing a child scout
would notice**: two enormous shields hiding an archer, for example. Draw it in
shaky pencil and uneven wax crayon on cream school paper. Exaggerate what
caught the child's eye rather than drawing a precise map. The text still
carries the exact objective, rules, and stakes. The drawing must be true of
every wording variant and must not reveal the onward mission or the other
branch. See the [field report sketch map](../games/company-of-unlikely-heroes/assets-source/guild-book/reports/motifs.md)
for the established style and examples.

Plan the sketch when drafting the report. Stock reports look up art by exact
mission ID first and can fall back to base art only when the variant and base
share the same encounter ID. Even then, reuse only if the motif is still true
of the variant. A different encounter ID needs its own exact-ID sketch.
The Light Hook Pair, for example, can't inherit the Harpoon Squad sketch:
it shows a Bruiser the Pair doesn't have.

Review the text and sketch together at a real fork in the running game. At
the intended projection size and viewing distance, check that the motif is
recognizable after cropping, the immediate text is readable, and neither
suggests a threat or solution that isn't there. Check every wording variant
against the same sketch. A text-only report is fine for a prototype, not a
finished choice. This is an authoring and review requirement, not an engine
validation rule.

## Review before adding a mission to the road pool

- **Design:** Keep the tactical question, the two example rounds, the
  win/loss checks, the rubric comparison, and the draft report with its sketch
  brief together.
- **Rules:** Check a complete win, each distinct loss, and the meaningful edge
  cases, using controlled inputs for new behavior. Check that the forecast
  agrees with the committed round. For catalog integration, see the
  [content guide](../games/company-of-unlikely-heroes/content/README.md).
- **Play:** Try different legal companies with normal rules, including a
  wounded arrival, and try the real fork and a follow-on mission. Record where
  players changed plans, whether the report prepared them for the fight, and
  what condition the company left in. A scripted win proves a route exists.
  It doesn't establish that players understood the choice, found the pressure
  fair, or wanted to play it again.
