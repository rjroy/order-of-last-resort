# The Company of Unlikely Heroes

**Choose a company, not just a loadout.** Choose an outing and recruit a company at the guild. Your heroes carry their wounds, orders, and earned upgrades between its missions. This is a playtest build; its artwork and interface are provisional.

From the repository root, with Godot 4.7:

```sh
godot --path games/company-of-unlikely-heroes
```

### Choose an outing

At the guild, use **Adventure** to choose one of seven outings. Pick three distinct recruits and arrange their deployment order, then depart. After each victory with another mission ahead, review the debrief and choose one reward if offers are available. The final victory or a defeat ends the outing. Returning to the guild starts a fresh company.

The guild has **20 playable missions**: two in **The company's first outing**, three in **Village Troubles**, and three in each of the five outings below. The fixed test fixtures (`ferryman`, `necromancer_wave`, and `extra_knight`) are not part of that count and do not appear in guild itineraries.

**The company's first outing** (`first_outing`) starts with Trouble on the road (`bridge_patrol`) and ends with The last ferryman (`company_rescue`). **Village Troubles** (`village_troubles`) takes the same company through The Goblin Mob (`goblin_mob`), The Harpoon Squad (`harpoon_squad`), and The Unwelcome Guest (`unwelcome_guest`).

In **Unwelcome Guest**, get the troll outside the marked village square alive. If it dies or your party falls, you lose. There is no deadline. The troll follows the nearest living party hero one tile each time it acts, stopping when adjacent. Your heroes' damaging standing orders remain active, so check and change them as needed. In particular, a carried Bard **Healing Sonnet** can damage or kill the troll even after it crosses the square's edge if the song happens later that round. Read the forecast before committing to see the troll's intended step and any pulls or follow-up actions.

#### New guild outings

Missions are listed in play order within each outing.

| Outing | Mission | What to watch for |
|---|---|---|
| **Border Watch** (`border_watch`) | The Shield Wall (`shield_wall`) | Separate the Archer from the Shieldbearers or take out the guards first. |
| | The Wrong Side of the Door (`wrong_side_of_the_door`) | Get one hero to the exit while another living character, even an enemy, holds the gate open on the plate. |
| | The Cowardly Captain (`cowardly_captain`) | Grunts hit harder next to the Captain. Split them up or cut off the Captain's retreat. |
| **Powder Run** (`powder_run`) | The Explosive Situation (`explosive_situation`) | A dying Bomber hurts anyone adjacent. Set off a chain reaction without catching your own company in it. |
| | The Bridge Is Out (`bridge_is_out`) | Get one hero to the far bank. The spans collapse at the ends of rounds 4 and 6, defeating anyone still on them. |
| | The Last Wagon (`last_wagon`) | Raiders target the wagon. Clear adjacent enemies to keep it moving, or intercept the next attacker. |
| **Fairground Fracas** (`fairground_fracas`) | The Duelists (`duelists`) | A surviving Duelist retaliates if the attacker is still adjacent after the hit. Use range or end the attack out of reach. |
| | The Great Sheep Escape (`great_sheep_escape`) | Get all three living sheep into the east pen at once. Unpenned sheep flee nearby characters, including the opposing shepherd. |
| | The Odd Couple (`odd_couple`) | The Trickster can swap with the hard-hitting Ogre once. Watch where that leaves exposed heroes. |
| **Night Duty** (`night_duty`) | The Unfortunate Healer (`unfortunate_healer`) | The enemy Healer has two heals. Separate the Bruisers from their support or finish one before it can be healed. |
| | Don't Wake the Giant (`dont_wake_the_giant`) | Reach the treasure without exceeding 12 noise. Holding is silent; moves, other abilities, and songs cost 1, 2, and 3 respectively. |
| | Hold the Line (`hold_the_line`) | Keep one hero standing through round 6. Enemies close in from both sides, but you do not have to defeat them. |
| **Rival Claims** (`rival_claims`) | The Last One Standing (`last_one_standing`) | Kill order matters: surviving Bandits gain damage, movement, or damage reduction, depending on which Bandit remains. |
| | The Unfortunate Ritual (`unfortunate_ritual`) | Occupy all three circles at the end of two consecutive rounds. Foes and summons count; any gap at round's end resets progress. |
| | The Mirror Company (`mirror_company`) | Watch the rival Knight's pushes and the Wizard's nearest-target blast. Decide when to go after their Healer. |

#### Launch a standalone mission

Launch without options for normal guild play. A direct launch instead opens one isolated battle with its authored starting party and a restart button. It does not offer guild rewards or carry wounds, orders, or upgrades into another mission. The two missions in the company's first outing require guild recruitment; the separate `ferryman` fixture is the fixed-party version of the rescue.

From the repository root:

```sh
# Village Troubles
godot --path games/company-of-unlikely-heroes -- --mission=goblin_mob
godot --path games/company-of-unlikely-heroes -- --mission=harpoon_squad
godot --path games/company-of-unlikely-heroes -- --mission=unwelcome_guest

# Border Watch
godot --path games/company-of-unlikely-heroes -- --mission=shield_wall
godot --path games/company-of-unlikely-heroes -- --mission=wrong_side_of_the_door
godot --path games/company-of-unlikely-heroes -- --mission=cowardly_captain

# Powder Run
godot --path games/company-of-unlikely-heroes -- --mission=explosive_situation
godot --path games/company-of-unlikely-heroes -- --mission=bridge_is_out
godot --path games/company-of-unlikely-heroes -- --mission=last_wagon

# Fairground Fracas
godot --path games/company-of-unlikely-heroes -- --mission=duelists
godot --path games/company-of-unlikely-heroes -- --mission=great_sheep_escape
godot --path games/company-of-unlikely-heroes -- --mission=odd_couple

# Night Duty
godot --path games/company-of-unlikely-heroes -- --mission=unfortunate_healer
godot --path games/company-of-unlikely-heroes -- --mission=dont_wake_the_giant
godot --path games/company-of-unlikely-heroes -- --mission=hold_the_line

# Rival Claims
godot --path games/company-of-unlikely-heroes -- --mission=last_one_standing
godot --path games/company-of-unlikely-heroes -- --mission=unfortunate_ritual
godot --path games/company-of-unlikely-heroes -- --mission=mirror_company
```

To explore the Village Troubles standalone openings, leave standing orders at their defaults:

- **The Goblin Mob:** Select Necromancer → **Summon Skeleton** → **C3**, then preview and commit. The skeleton joins the fight next round; its Wave can hit allies as well as goblins.
- **The Harpoon Squad:** Read the opening forecast: Hookhand pulls the Healer from **B3** to **C3**, setting up the Bruiser's strike. Preview Knight → **Push** → Bruiser at **C4**. The push moves the Bruiser to **D4** and removes that follow-up from the forecast. Compare before committing.
- **The Unwelcome Guest:** Preview Knight → **Push** → Village Troll at **C3**. The push takes the living troll out of the square for a victory. Alternatively, preview Knight → **Move one tile** → **E3** to see the troll's intended step in the forecast. Read the forecast and adjust damaging orders before committing.

These examples use the standalone missions' authored parties and fresh opening positions. A guild party and its carried wounds or orders can change the forecast.

### Your first outing

At the guild, pick **exactly three** of the seven recruits and arrange them in the order you want them to act. The order is fixed for the outing. The patrol fight has no round limit: defeat the opposition before it defeats your company. The second mission has a different objective: get the ferryman to the marked landing before the bridge fails. Clearing the bridge of enemies does not by itself win the rescue.

Give each hero a standing order. Each round you may queue **one** manual command instead: select a hero, action and target if needed, preview it, and read the ordered forecast. You can revise it, switch the hero you command, or clear it before committing the round. Everyone else follows their standing order. There is no full-manual or standing-only mode selector.

After winning the fight, inspect the debrief before continuing. Survivors carry their current HP and standing orders forward. Fallen heroes rejoin at **1 HP**; mission statuses clear. Failure ends the outing, as does a successful rescue.

| Hero | Offensive action | Utility |
|---|---|---|
| Knight | Push a neighboring unit or obstacle. The push hurts only on collision. | His shield covers everyone in range, even an enemy. An incoming attack reflects to the nearest enemy or obstacle. |
| Healer | A staff bonk damages an adjacent enemy or obstacle and draws an enemy’s attention. | When wounded, heals self; otherwise heals the nearest eligible companion, even if they are at full health. |
| Wizard | The blast seeks the nearest thing, not the most convenient enemy. | Choose someone to pull. They land where the wizard stood; the wizard takes the recoil, including injury and knockdown. |
| Alchemist | A volatile splash hits the nearest thing, friend or foe, and can knock it down. | A ward redirects attacks. The alchemist can protect a wounded company, but cannot heal it or pull someone out of danger. |
| Rogue | Wasn't Me marks an enemy beside another living character; its next attack is redirected to an adjacent character, including an ally. | Retreat steps away from the nearest enemy. Confusing Dodge swaps with the furthest other living character, friend or foe. |
| Necromancer | Summon Skeleton puts a 1 HP skeleton on an open neighboring tile. | Raise Dead consumes an unoccupied enemy corpse and puts a zombie there with half the enemy's maximum HP, rounded up. The Necromancer holds unless directly commanded. |
| Bard | Healing Sonnet makes a random living opponent scream for 1 damage. It does not heal. | Inspiring Melody makes a random eligible opponent laugh away their next turn. The Bard starts on Hold and can take either song as a standing order. |

Rogue distance ties and redirect victim ties use the lowest character instance ID. When the marked enemy attacks, Wasn't Me looks for an adjacent living character other than the attacker and its original target. If nobody else is there, the original target takes the attack. Either way, the mark is spent. Movement before the attack can change who takes the blame, and a reflecting aura can still redirect the resulting attack.

The Necromancer can have one living skeleton and one living zombie at a time. They appear immediately but first act **next round**, right after their summoner (skeleton before zombie). Neither takes a company slot, prevents a wipe, or joins the next mission. They cannot be commanded, and their remains cannot be raised.

Both summons pursue opponents and, close enough, independently pick a legal greeting. Read the forecast before committing: an earlier hero can move out of the way. **Wave** hits every adjacent character except the skeleton for 1 damage. **Don't Go** blocks the nearest other character's next Move, not their other actions. **Say Hello** makes the nearest other character back up a tile if it is open. These three greetings can affect friends. **Offer Flower** deals 1 damage to an opponent up to two tiles away.

The Bard can Move or perform either song as a direct command. It interrupts that Bard's standing order for one round; directly commanding anyone else lets the song continue. Songs choose their own listener from living opponents anywhere on the board, never a crate, ally or corpse. The ordered forecast names the listener and shows whether they lose their turn; refreshing the same forecast never rerolls it. A listener who laughs is immune to more laughter through the entire following round, but the Sonnet still hurts them. With two opponents and no other interference, a standing Melody alternates between them. With one, the Bard sings without an eligible listener every other round.

To try it in the existing patrol, recruit Bard, Healer and Knight in that order. Leave the other two on their default orders and commit three rounds of **Inspiring Melody**, comparing the listeners. Switch to **Healing Sonnet** for round four to see damage against the raider who just laughed. Before committing, preview a Move for another hero to leave the song in place, then replace the command with a Bard Move to see the song drop out of the forecast. The Bard uses the existing Wizard drawing with a distinct gold name label.

The game collects no playtest telemetry. The question to take away: **Did you enjoy trusting two of these people while you took charge of the third?**

### Rewards between missions

After a victory with another mission ahead, the debrief shows **one offer per eligible deployed hero**. Each entry describes what changes, its rarity, and how many times you can take it during this outing. Choose **one reward total** using its **Take reward** button, or use Tab and Enter. The claimed reward stays on the debrief while you review the party and continue. Passing on an offer does not count against its cap. The splash-and-ward Alchemist does not have a reward pool yet. If there are no eligible offers, you can continue without choosing.

Rewards start in the next mission. Extra maximum HP comes with the same amount of current HP, but does not erase existing wounds. In combat, open **Outing upgrades** above the round controls to review what each hero gained. New actions and orders appear in the same pickers as the base kit. For example, **Shield Throw** shows an outlined shield where it will land in the forecast, then a filled marker while it is on the board. Point at the tile to inspect it; **Advance** heads toward it so the Knight can recover it. **Say Hello to That One** names the summons' directed target in the forecast and on tile inspection.

There is no reward after a final victory or a defeat, or in standalone missions. Returning to the guild clears all outing upgrades; there are no permanent guild perks.

### Author a variation

The built-in catalog starts at `content/catalog.json`. Shared definitions, adventure content and fixed regressions are authored separately and loaded as one catalog. An adventure references an ordered mission list and an eligible roster. Its missions provide deployment slots rather than prescribing the player's heroes. Placement IDs identify individual NPCs and objects; multiple placements can use the same definition. Character fields override class defaults as whole fields. New mechanics need code; new combinations of existing handlers need only data.

### Play the checked-in regressions

Launch **First Greetings** to see both summons and give the Healer a chance to escape a Wave:

```sh
godot --path games/company-of-unlikely-heroes -- --mission=necromancer_wave
```

1. **Round 1:** Select Necromancer → **Raise Dead** → corpse at **E4**. Preview and commit to raise a 3 HP zombie.
2. **Round 2:** Select Necromancer → **Summon Skeleton** → **C2**. Preview and commit. Both summons are now on the board.
3. **Round 3:** Scroll through the standing forecast: the skeleton's **Wave** will hit the Healer at B2, the Necromancer, and the practice raider. Select Healer → **Move one tile** → **A2**, then preview. The Healer's Move now precedes Wave; the forecast still shows the other hits. Commit to leave the Healer at A2 with full HP.

Leave standing orders unchanged. The fixture has no time limit and restarts from the same seed; the practice raider holds position.

From the repository root, launch the permanent four-hero, two-crate variation:

```sh
godot --path games/company-of-unlikely-heroes -- --mission=extra_knight
```

The Blast knight starts at A1, with crates at B1 and C3 and the exit at C1. The first forecast should hit the B1 crate. To run its automated real-boot regression (alongside the custom-catalog scene checks):

```sh
godot --headless --path games/company-of-unlikely-heroes --script res://tests/content_scene_test.gd
```

To launch the original fixed rescue:

```sh
godot --path games/company-of-unlikely-heroes -- --mission=ferryman
```

These are **fixed regression scenarios**, not guild outings. The `extra_knight` exit is `near_landing`; the original rescue uses `safe_bank`. The fixtures use the same hybrid resolver as the adventure. See the [catalog guide](content/README.md) for the authoring rules.

### Recheck the build

From this directory, run the suites with `godot --headless --script res://tests/<name>.gd`:

| Suite | What it checks |
|---|---|
| `catalog_test` | Invalid definitions, independent worlds, and interaction capabilities |
| `catalog_bundle_test` | Authored parts load into one catalog; duplicate IDs and invalid deployment slots are rejected |
| `content_test` | Extra crate, alternate knight kit and habit, relocated escort destination |
| `content_scene_test` | Loading a custom catalog and the permanent extra-knight mission through the game controls |
| `rules_test` | Ability interactions and command rules |
| `rescues_test` | Fixed-start rescues, loss, and restart |
| `adventure_test` | Party selection and formation, deployment, combat and mission transitions |
| `adventure_scene_test` | Party selection and formation through the controls, one reward choice on the debrief, wound carryover, and guild return |
| `rewards_test` | Authored hero pools, seeded offers, caps, selection, carryover, and outing reset |
| `hero_upgrade_effects_test` | Upgrade effects, learned actions and orders, and consistency between preview and commit |
| `three_mission_test` | Village Troubles mission rules and adventure boundaries |
| `village_outing_scene_test` | Direct launches and the Village Troubles guild-to-result flow through both reward debriefs |
| `hook_overlay_scene_test` | Hook landing and earlier movement appear as separate forecast paths |
| `rogue_test` | Rogue dodge, redirect, retreat, and hybrid forecast consistency |
| `necromancer_test` | Summons, corpse selection, greetings, round order and forecast consistency, and expedition boundaries |
| `bard_test` | Both persistent songs, seeded listeners, skipped turns and full-round laughter immunity, damage, and direct-command interactions |
| `laughter_presentation_test` | A laughing hero loses their turn without being shown as knocked down in the command editor or debrief |
| `scene_smoke` | Guild entry, battle controls, one-command forecasts, commit, and fixed-scenario restart |

In a graphical session, `godot --script res://tests/scene_smoke.gd -- --capture=/absolute/path.png` also saves the game viewport after the smoke run.

Run `godot --script res://tests/bridge_art_test.gd` from this game directory in a graphical session to check the **rendered** shore tint and exit flag. It compares the board before and after moving the objective; no reference screenshot is required.

Run `godot --script res://tests/outing_art_test.gd` in a graphical session to check the new figures and the marked objective zone with tactical overlays.
