# What the seven guild heroes actually play

Audit for `mind-garage-2lw`, against `60d13b8`. Scope: the seven recruitable heroes, permanent guild training, adventure rewards that add commands, and what happens when heroes go down or stand idle. Summoned helpers are called out separately. This is an inventory of the shipped presentation, not approval of new animation or a change to combat rules.

## Reading the evidence

Paths below are relative to `games/company-of-unlikely-heroes/`. To trace a trained action, start with `content/guild_progression.json` (who learns it), `content/guild_training.json` or `content/common.json` (what resolves), then `presentation/cast_cues.gd` (which **performer's** clip is requested), `assets/cast/manifest.json` (what is packaged), and `bridge_art.gd` (what the board actually draws). An ability doing damage, moving its target, or printing a forecast does not prove the performer animated. Nor does finding the donor's action in the donor's atlas.

For state changes, check both the entry cue and the frame the board holds after the cue ends. A living hero knocked off their feet is not a defeated hero. For idles, count distinct **pictures** in the ready loop, not seconds in its manifest: a one-second hold of one pose is still a still.

## Idle: who moves when the player puts the controls down?

| Guild hero | Packaged `ready`: unique pictures / samples | At rest on the board |
|---|---:|---|
| Anxious Knight | 1/1 | Static; `shield_away` is a separate equipment pose. |
| Unimpressed Healer | 1/1 | Static. |
| Enthusiastic Caster | 1/1 | Static; the seated end of Pull is not an idle. |
| Daft Dodger | 1/1 | Static; ready uses one sample of the retreat take, not the retreat performance. |
| Bad Bard | 6/6 | Animated, 1-second loop. |
| Friendly Crypter | 4/4 | Animated, 1-second loop. |
| Mixologist | 1/1 | Static. |

`tools/cast/takes.py` requests only one ready sample for each static hero. `bridge_art.gd:166–199` already advances the ready clock and redraws eligible figures when the frame changes. This is an **art/bake gap**, not a request for another animation clock. `mind-garage-afz` covers all five. Keep preview stamps stationary.

The Crypter's helpers are not roster slots: Skeleton has 6 distinct pictures in 9 samples; Zombie has 1/1 (`mind-garage-9kt`). For comparison, Goblin has 7/7 and Bruiser 8/8. The Ferryman (5/5) and Harpooner (8/8) are not guild heroes. The frontier wagon has five samples but just one picture; a stationary vehicle is not evidence of a broken opponent idle.

To reproduce the pixel check: for each actor's `clips.ready.frames` in `assets/cast/manifest.json`, take each `rect` (`x,y,w,h`) from the matching actor PNG, run `magick ACTOR.png -crop WxH+X+Y +repage -depth 8 rgba:- | sha256sum`, and count distinct hashes within the clip. This detects repeated artwork, not whether the movement reads well at tactical scale. Judge new loops in a live battle beside an opponent, including the return from an action.

## Guild training: 13 ability grants, not 13 new performances

The 26 petitions comprise 13 ability grants, eight standing orders, four recruits and one passive. `guild_progression.gd` builds the equipped kit. The `CLIPS` table in `presentation/cast_cues.gd:9–27` is live for these seven heroes; `_start_cue` at `:446–478` returns no performer cue for an unbound actor/ability pair. The actor can still affect the board. The table below names **every** permanent ability grant and the recipient who can equip it. A dash means no performer clip is requested, not that the ability fails.

| Learner | Class training: trigger → actual clip | Borrowed ability: trigger → actual clip |
|---|---|---|
| Anxious Knight | Rescue Line: pull a friendly two tiles away one tile closer → — | Bonk: adjacent bonk/taunt → — |
| Unimpressed Healer | Field Dressing: heal chosen nearby ally → `ally_heal`; treat self → `self_heal` (intentional reuse, `_observe_heal`) | Blast: blast nearest eligible target → — |
| Enthusiastic Caster | Ring of Sparks: damage adjacent characters → — | Confusing Dodge: swap with furthest other character → — |
| Daft Dodger | Tripwire: restrain nearest eligible opponent within two tiles → — | Healing Potion: dose nearby friendly/self → — |
| Bad Bard | No class-specific action grant; see Song Weaving below. | Push: shove adjacent target, collision may damage → — |
| Friendly Crypter | Grave Bell: repel nearest other character → — | Inspiring Melody: make eligible opponent laugh → — |
| Mixologist | Etching Paste: apply acid at contact range → — | Pull: pull target in and suffer recoil → — |

**Follow-ups:** `mind-garage-c6r` covers the five missing class-training performances; `mind-garage-xza` covers the seven missing learner performances. The shipped clip inventory below distinguishes existing candidate art from absent wiring. No bespoke clip for those named actions is packaged on the learner. A thematically similar take might work, but blindly binding a donor's atlas changes the character, and a flying vial is not an application of paste. Check the actual gesture at board scale before authoring a new one.

**Song Weaving is already wired.** Switching between the two base songs on consecutive eligible rounds emits the previous song as an echo (`rules/actions.gd:354–372`, `rules/performances.gd`). The `song_echo` branch in `cast_cues.gd:178–185` starts a separate cue for that ability, so both `inspiring_melody` and `healing_sonnet` can play. No third “weaving” clip is missing. A new standing order changes who chooses an action, not which animation the action gets.

## Adventure rewards that grant commands

These five commands are awarded to their owner for one outing. They are not permanent cross-training. See the `ability` fields on the upgrades in `content/rewards.json`, the action table in `cast_cues.gd`, and its `repeat_batch` recipe dispatch.

| Owner / reward | Committed trigger | Actual playback and disposition |
|---|---|---|
| Knight / Shield Throw | Throw at enemy or damageable obstacle | `shield_away` is one shield-free image, appropriate as an equipment **hold**, not a release performance. `mind-garage-dug`. |
| Bard / House Lights | Take the Stage sings to a listener and nearby opponents | `healing_sonnet` is intentional reuse: it is an amplified Sonnet. |
| Crypter / Say Hello to That One | Nominate a living opponent for the undead to pursue | No performer cue; changing the minions' target/facing is not a gesture from the Crypter. `mind-garage-dug`. |
| Mixologist / Spare Vial | Use Plain Tonic on self or ally | `potion`, intentionally reused for a dose without side effects. |
| Mixologist / Keep the Culture | Repeat a bottled recipe and reaction | `potion` for a healing recipe or `acid` for an acid recipe. Existing recipe-specific playback, not a missing Repeat Batch take. |

## Fallen heroes: entry, hold and recovery

The clips below are the complete packaged keys on each guild hero in `assets/cast/manifest.json`; the corresponding [model records](models/) document their Blender takes. None lists a dedicated hero knockdown, recovery or defeat performance.

| Hero | Packaged clips | Living knockdown → hold → recovery | Lethal hit while party continues |
|---|---|---|---|
| Anxious Knight | `ready`, `guard`, `shield_away` | Generic turned pose; shield-away equipment remains authoritative; no stand-up take | Removed |
| Unimpressed Healer | `ready`, `ally_heal`, `self_heal`, `bonk` | Generic turned pose, then upright | Removed |
| Enthusiastic Caster | `ready`, `blast`, `pull` | Own Pull deliberately ends seated and holds its last frame; unrelated knockdown uses generic pose. No recovery take. | Removed |
| Daft Dodger | `ready`, `retreat`, `swap`, `misdirect` | Generic turned pose, then upright | Removed |
| Bad Bard | `ready`, `inspiring_melody`, `healing_sonnet` | Generic turned pose, then upright | Removed |
| Friendly Crypter | `ready`, `summon_skeleton`, `raise_dead` | Generic turned pose, then upright | Removed |
| Mixologist | `ready`, `potion`, `acid`, `acid_flask` | Earlier committed potion/acid can finish before the knocked-down pose; no separate fall or stand-up | Removed |

* **Alive:** `rules/statuses.gd` distinguishes knockdown recovery from other skipped actions such as laughter. The figure remains in `main.gd` and `bridge_art.gd:878–936` selects a pose. Generic rotation is a visible fallback, not a fall performance. `mind-garage-azn` covers the seven heroes' entry, hold and return to ready; preserve the Caster's authored seated finish.
* **Zero HP:** `main.gd:1972–2016` excludes ordinary zero-HP units before sending figures to the board. Objective subjects and enemy corpse markers have separate paths. Adding hero defeat art alone therefore cannot fix it. `mind-garage-rcd` covers art **and** presentation of the lethal transition and resulting state. Verify with one survivor and with a party wipe; do not make a fallen party member targetable, block a tile, or change debrief/carryover rules.

## Verification and limits

From the repository root, run `godot --path games/company-of-unlikely-heroes --script res://tests/NAME.gd` with each name below. All four checks exited 0 during this audit. Use a graphical renderer for the first two; the latter two ran headless. For the guild walkthrough use an isolated `XDG_DATA_HOME`, not a personal save.

* `cast_state_art_test`: actual rendered prone/KO poses, shield recovery, Caster Pull seating and Mixologist playback timing. The KO fixture passes a figure straight to the renderer; it does **not** bypass the production scene's filter in a real mission.
* `move_preview_scene_test`: all seven heroes; the board ready clock advances while destination stamps stay still.
* `cast_cues_test`: resolved cue mappings and recipients, including Mixologist recipes.
* `guild_petitions_walkthrough_test`: purchases and commits trained actions, including Knight Rescue Line and Healer Blast. A successful command does not assert a performer clip.

The per-grant dispatch inventory is source evidence, not a claim that all 13 grants were individually seen in a graphical run. Each linked follow-up specifies what to commit and what to look for in battle. No game code or artwork changed for this audit.
