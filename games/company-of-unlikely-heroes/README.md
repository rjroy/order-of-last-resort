# Barnaby's Order of Last Resort

**Choose a company, not just a loadout.** Found a guild, take a commission, and lead your recruits to its destination. Your heroes carry wounds, orders, and earned upgrades between missions. This is a playtest build; its artwork and interface are provisional.

On first launch, from the repository root with Godot 4.7, import the packaged assets before starting the game:

```sh
godot --headless --editor --path games/company-of-unlikely-heroes --import
```

For subsequent launches, the normal command is:

```sh
godot --path games/company-of-unlikely-heroes
```

### Build the browser playtest

The Web release uses Godot 4.7.2 stable (`ed1daf0bf`) and matching 4.7.2
stable Web export templates. It uses the GL Compatibility renderer and the
single-threaded Web template, so the host does not need cross-origin isolation
headers. It is not a PWA. The HTML, JavaScript, WebAssembly and PCK files must
be served together over HTTP(S), with `.wasm` served as `application/wasm`.
Browser saves belong to that browser and origin, not the native save directory.

From the repository root, install the matching templates through Godot, then
export to a **new, empty** ignored staging directory:

```sh
bash tools/web/build.sh "$(command -v godot)" "$PWD/.lore/local/pages-build/order-of-last-resort"
python3 -m http.server 8000 --bind 127.0.0.1 --directory .lore/local/pages-build
```

Visit `http://127.0.0.1:8000/order-of-last-resort/`. The build script imports a
fresh project copy and refuses a nonempty output directory, so use another
empty directory for a subsequent build. The release includes runtime JSON and
dynamic assets, including music, while excluding tests, tools and source
masters. Generated staging files are disposable and are not runtime inputs to
the source project.

For the automated browser smoke, install Node 22 or newer, Chromium and
Tesseract with English language data. With the server above still running:

```sh
node tools/web/smoke.mjs http://127.0.0.1:8000/order-of-last-resort/
```

Set `CHROMIUM` to the browser executable if it is not named `chromium`. The
smoke uses a fresh browser profile, not the player's existing save. Also play
through a committed practice move, inspect art and audio after interaction,
and check persistence after reload in a clean browser; an automated check does
not establish enjoyment.

The **Web playtest** GitHub Actions workflow verifies official Godot 4.7.2
editor and template downloads against the SHA-256 digests published in the
[release](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable),
imports and exports from a clean checkout, and runs the browser smoke against
the project path. Pull requests only build and check; they cannot deploy.
The repository's Pages source is GitHub Actions, and every completed merge to
`master` builds, verifies and deploys the artifact that passed its own smoke
check to `https://rjroy.github.io/order-of-last-resort/`. The same happens for
a manual run on `master`. Confirm the live project path and that the account
homepage remains unchanged.

### Play a battle

Take a commission, recruit your party, and choose a route. Every built-in battle opens on the storybook board. No launch flag is needed. To skip directly to a standalone practice mission:

```sh
godot --path games/company-of-unlikely-heroes -- --mission=wrong_side_of_the_door
```

Click the Anxious Knight, then **B2**. That plans a step rather than spending the round. Commit it, then click the Anxious Knight and **C2**, the pressure plate. Before committing again, look for three things: the Anxious Knight is still on B2, his pencilled move would open the gate, and moving replaces Guard for this round. Clear the command to compare with Guard. The other heroes keep their standing orders.

The same book and controls support the eight built-in defeat-all encounters on the shared frontier field. Try these two from the repository root:

```sh
godot --path games/company-of-unlikely-heroes -- --mission=explosive_situation
godot --path games/company-of-unlikely-heroes -- --mission=mirror_company
```

In the first fight, inspect the forecast for who stands next to a dying Bomber. In the second, look at the rival company's actions in initiative order. Standalone launches do not use your guild save.

### Take a commission

The normal launch opens the illustrated guild book as the game, not a separate mockup. Name your guild and select **Create guild** on first launch. A new stock guild starts with a practice lesson using the Knight, Healer and Caster. Complete it or select **Skip** to reach the commission board; either way, practice has no payout or effect on guild progress. You can replay it from the board. Existing guilds go straight to the board, including after leaving during practice. The board offers three commissions: two of **5 missions** and one of **10 missions**, each counting its named finale. Use **Choose commission**, then **Recruit** three distinct heroes from the available roster. Use **Earlier** and **Later** to set deployment order: the top hero acts first, and the order also determines starting positions. Select **Read field reports** once your company is ready.

Hints are on by default. The shared **Show hints** switch in Options persists in and out of combat; turning hints off leaves practice instructions and the indexed **?** help book available. The book covers the game controls and includes engine credits.

At each fork, choose between two field reports using **Take Route A** or **Take Route B**. Each describes the immediate mission and hints at the type of mission beyond it, not its exact identity. At the next fork, exactly one report matches the type hinted at by your previous choice. The commission's destination is visible from the start and both choices at the last fork lead there. After each nonfinal victory, choose one temporary hero reward if offered, then continue to the next reports or the finale.

**Guild pay:** Each road victory earns 1 point; winning the destination earns 5 instead. Collect the total on returning to the guild. A defeat or forfeit earns nothing for that mission but keeps earlier wins. Four roads followed by a lost destination pay 4; the same commission completed pays 9. Standalone missions do not pay guild points.

**Guild unlocks:** A new guild starts with the Knight, Healer and Caster. Open **Guild petitions** on the commission board to browse or filter the 29 stock petitions. Selecting a petition previews it; only the purchase button spends points. Recruit the Bad Bard or Daft Dodger for 4 points apiece, the Mixologist or Hobby Smith for 5 apiece, or the Friendly Crypter for 6. The party still has three places. The [original petition register](../../.lore/work/games/company-of-unlikely-heroes/notes/guild-perk-catalog.md) records the earlier set. For example:

- The **Bad Bard** starts with both songs as standing orders. His separate **Song Weaving** petition costs 5 points. Play Melody, then Sonnet on the next round: Sonnet plays first and Melody echoes. Repeat Sonnet and no echo plays. A skipped performance breaks the chain, echoes never start another echo, and laughter immunity still applies.
- **Teach the Healer: Blast** adds an offense option. It does not replace Bonk until you equip Blast during recruitment. Heal and Support remain available. Pursue and Bonk requires Bonk, and Blast can hit an ally or an obstacle. The Caster keeps his spell.

Use **Edit loadout** during recruitment to choose an offense, utility and compatible starting order. Buying an ability never silently equips it or teaches the donor's standing orders. For example, a Knight equipped with **Rescue Line** can pull an ally toward him instead of guarding. A new Mixologist can throw Acid directly from her first mission; **Throw Samples** teaches her to do it while you command someone else.

**Bring the Hobby Smith:** Buy **Recruit the Hobby Smith** in **Guild petitions**, then choose a commission and recruit the Smith with two other heroes. Use **Earlier** to put the Smith first and leave his starting order on **Try This** to give a later hero a chance to use the fitting in the same round. The Smith starts with **Hammer Time**, **Try This**, and the standing orders **Try This**, **Pursue**, and **Hold**. **Learn Bonk and Taunt** costs 4 points; **Learn Acid** costs 5 and also requires the Mixologist to be recruited. Equip either in **Edit loadout** to replace Hammer Time without losing Try This. **Pursue** uses the equipped offense against the nearest opponent if it can; otherwise the Smith takes one step toward attack range or holds.

Returning clears outing upgrades and refreshes the commission board. Guild points, permanent purchases and preferred loadouts survive. Existing guild profiles retain access to their previous recruits. There is no mid-run save.

### Guild save location

The standard profile is `guild_profile_v1.json` in Godot's default user-data directory for **Barnaby's Order of Last Resort**. Custom catalog launches use the separate `custom_guild_profile_v1.json` in the same directory. Typical locations are:

- Linux: `${XDG_DATA_HOME:-~/.local/share}/godot/app_userdata/Barnaby's Order of Last Resort/`
- Windows: `%APPDATA%\Godot\app_userdata\Barnaby's Order of Last Resort\`
- macOS: `~/Library/Application Support/Godot/app_userdata/Barnaby's Order of Last Resort/`

When a profile is first needed and its new file does not exist, the game copies its corresponding old file from the sibling `The Company of Unlikely Heroes/company_of_unlikely_heroes/` directory. It leaves the original in place and never intentionally replaces a profile already at the new location. If the old profile cannot be read or copied, the game shows an error instead of offering a blank guild; correct the problem and reload. Explicitly configured profile paths are isolated and do not trigger migration.

Migration and all profile updates use an adjacent `<profile filename>.migration-lock` directory to prevent two game processes from publishing at once. An interruption can leave this directory behind. If no game process is running, remove the empty lock directory named in the error and reload; do not remove the profile or legacy save. A profile already present at the new location can be read even if a lock remains, but updates require the lock to be cleared.

Before replacing a profile, the game saves and verifies its previous committed bytes as `<profile filename>.backup`. The canonical profile takes precedence when present. If it is missing but a backup exists, the game stops rather than importing an older legacy save or creating a blank guild. Close all game processes, retain copies of both the backup and any other save files, inspect the backup, and copy it to the canonical filename before retrying. The backup represents the state before the most recent update, not necessarily the newest canonical state. This also applies to explicitly configured profile paths.

### Explore the missions

All 20 built-in missions remain available for standalone play. The earlier fixed practice routes have been retired; commissions are the multi-mission mode.

In **Unwelcome Guest**, get the troll outside the marked village square alive. If it dies or your party falls, you lose. There is no deadline. The troll follows the nearest living party hero one tile each time it acts, stopping when adjacent. Your heroes' damaging standing orders remain active, so check and change them as needed. In particular, a carried Bad Bard **Healing Sonnet** can damage or kill the troll even after it crosses the square's edge if the song happens later that round. Read the forecast before committing to see the troll's intended step and any pulls or follow-up actions.

The groupings below identify missions by their former practice outings; they are not playable routes.

| Former grouping | Mission | What to watch for |
|---|---|---|
| **The company's first outing** | Trouble on the Road (`bridge_patrol`) | The patrol has no round limit. |
| | The Last Ferryman (`company_rescue`) | Get the ferryman to the landing before the bridge fails. |
| **Village Troubles** | The Goblin Mob (`goblin_mob`) | Watch for the skeleton's friendly fire. |
| | The Harpoon Squad (`harpoon_squad`) | Prevent Hookhand from setting up a Bruiser's strike. |
| | The Unwelcome Guest (`unwelcome_guest`) | Get the troll outside the village square alive. |
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

A `--mission` launch opens an isolated battle with a restart button. It uses the authored starting party unless you supply `--party`, and does not read or change a guild profile, award guild rewards, or carry anything into another mission. Missions without an authored party, including the company's first outing, require `--party`. Supply exactly one distinct commandable hero per encounter slot, in deployment order.

Add repeatable `--loadout=hero:field=id,...` options to change selected heroes' `offense`, `utility`, and/or starting `order`. Omitted fields retain their catalog defaults. Choices include the catalog's available ability and order unlocks, without buying them in a guild; the selected order must be compatible with the equipped abilities. Other passive techniques, such as Song Weaving, are not granted. Invalid heroes, choices, duplicate fields or duplicate hero loadouts stop the launch with an error. Both options require an explicit `--mission`. Custom content uses its own authored party slots and guild kit choices.

```sh
# The authored default party and kits
godot --path games/company-of-unlikely-heroes -- --mission=wrong_side_of_the_door
# An ordered party for a mission without a default party
godot --path games/company-of-unlikely-heroes -- --mission=bridge_patrol --party=bard,healer,knight
# An authored default party with a partial kit and learned order
godot --path games/company-of-unlikely-heroes -- --mission=wrong_side_of_the_door --loadout=knight:utility=knight_rescue_line,order=order_knight_escort
# Combine a custom party with an explicit loadout
godot --path games/company-of-unlikely-heroes -- --mission=bridge_patrol --party=wizard,knight,healer --loadout=knight:utility=knight_rescue_line,order=order_knight_escort
```

From the repository root:

```sh
# Village Troubles
godot --path games/company-of-unlikely-heroes -- --mission=goblin_mob
godot --path games/company-of-unlikely-heroes -- --mission=harpoon_squad
godot --path games/company-of-unlikely-heroes -- --mission=unwelcome_guest

# The company's first outing (these missions require an explicit party)
godot --path games/company-of-unlikely-heroes -- --mission=bridge_patrol --party=knight,healer,wizard
godot --path games/company-of-unlikely-heroes -- --mission=company_rescue --party=knight,healer,wizard

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

- **The Goblin Mob:** Select Friendly Crypter → **Summon Skeleton** → **C3**, then preview and commit. The skeleton joins the fight next round; its Wave can hit allies as well as goblins.
- **The Harpoon Squad:** Read the opening forecast: Hookhand pulls the Unimpressed Healer from **B3** to **C3**, setting up the Bruiser's strike. Preview Anxious Knight → **Push** → Bruiser at **C4**. The push moves the Bruiser to **D4** and removes that follow-up from the forecast. Compare before committing.
- **The Unwelcome Guest:** Preview Anxious Knight → **Push** → Village Troll at **C3**. The push takes the living troll out of the square for a victory. Alternatively, select the Anxious Knight and click **E3** to preview a Move and see the troll's intended step in the forecast. Read the forecast and adjust damaging orders before committing.

These examples use the standalone missions' authored parties and fresh opening positions. A guild party and its carried wounds or orders can change the forecast.

### Company and combat

Your deployment order stays fixed for the commission. In Trouble on the Road, the patrol has no round limit. In The Last Ferryman, get the ferryman to the marked landing before the bridge fails. Clearing the bridge of enemies does not by itself win the rescue.

Give each hero a standing order. Each round you may replace **one** hero's order with a direct command. Select a hero to see their named equipped abilities, including unavailable abilities and their reasons. For a quick Move, click a legal destination without choosing an ability. To use a targeted ability, choose its button, then click a marked legal target; if several valid occupants share a cell, choose the intended occupant. Other abilities, such as the Caster's automatic Blast, stage immediately.

Outside targeting, clicking a hero selects or retains that hero rather than using an ability. You can also switch heroes while targeting; switching or choosing **Cancel targeting** preserves any staged command. **Escape** backs out of the current step without discarding that command. With no command staged, **Clear selection** returns to neutral; with a command staged, **Clear command** discards it and returns to neutral. Open **Forecast** to see everyone's actions in order. Complete or cancel targeting before committing: only **Commit** resolves the round. Everyone else keeps their standing order.

After a victory with another mission ahead, inspect the debrief before continuing. Survivors carry their current HP and standing orders forward. Fallen heroes rejoin at **1 HP**; mission statuses clear. A defeat or final victory ends the run.

| Hero | Offensive action | Utility |
|---|---|---|
| Anxious Knight | Push a neighboring unit or obstacle. The push hurts only on collision. | His shield covers everyone in range, even an enemy. An incoming attack reflects to the nearest enemy or obstacle. |
| Unimpressed Healer | A staff bonk damages an adjacent enemy or obstacle and draws an enemy’s attention. | When wounded, heals self; otherwise heals the nearest eligible companion, even if they are at full health. |
| Enthusiastic Caster | The blast seeks the nearest thing, not the most convenient enemy. | Choose someone to pull. They land where the caster stood; the caster takes the recoil, including injury and knockdown. |
| Mixologist | **Acid:** Deal 1 damage to a chosen hostile character up to three tiles away, plus a forecast reaction. | **Healing Potion:** Heal yourself or a chosen adjacent friendly character for 1 HP, including civilians and summons, plus a forecast reaction. |
| Daft Dodger | Wasn't Me marks an enemy beside another living character; its next attack is redirected to an adjacent character, including an ally. | Retreat steps away from the nearest enemy. Confusing Dodge swaps with the furthest other living character, friend or foe. |
| Friendly Crypter | Summon Skeleton puts a 1 HP skeleton on an open neighboring tile. | Raise Dead consumes an unoccupied enemy corpse and puts a zombie there with half the enemy's maximum HP, rounded up. The Friendly Crypter holds unless directly commanded. |
| Bad Bard | Healing Sonnet makes a random living opponent scream for 1 damage. It does not heal. | Inspiring Melody makes a random eligible opponent laugh away their next turn. The Bad Bard starts on Hold and can take either song as a standing order. |
| Hobby Smith | **Hammer Time** deals 2 damage to an adjacent opponent or damageable obstacle without shoving or taunting. | **Try This** fits another hero so they can use an alternate form of an ability once. |

Daft Dodger distance ties and redirect victim ties use the lowest character instance ID. When the marked enemy attacks, Wasn't Me looks for an adjacent living character other than the attacker and its original target. If nobody else is there, the original target takes the attack. Either way, the mark is spent. Movement before the attack can change who takes the blame, and a reflecting aura can still redirect the resulting attack.

The Mixologist normally follows the nearest other ally and stops when adjacent. **Make Rounds** gives a potion to the character missing the most HP among legal recipients; **Throw Samples** uses Acid on the nearest legal hostile, or waits if none are in range. These orders break ties in encounter order. You can replace any of them with a direct Move or a dose of your choosing. A full-health recipient can still react to a directly commanded potion.

The reaction is good for the recipient 70% of the time with a potion and 20% with Acid; the chances of a bad reaction are reversed. Both have a 10% chance of a purely cosmetic reaction. Check the exact dose while aiming, before you choose who gets it. Changing recipients does not reroll the dose. The round forecast shows the recipient, reaction and any later events it triggers. Unless marked for this round's end or the next turn, an unused reaction expires at the end of the following round.

The Friendly Crypter can have one living skeleton and one living zombie at a time. They appear immediately but first act **next round**, right after their summoner (skeleton before zombie). Neither takes a company slot, prevents a wipe, or joins the next mission. They cannot be commanded, and their remains cannot be raised.

Both summons pursue opponents and, close enough, independently pick a legal greeting. Read the forecast before committing: an earlier hero can move out of the way. **Wave** hits every adjacent character except the skeleton for 1 damage. **Don't Go** blocks the nearest other character's next Move, not their other actions. **Say Hello** makes the nearest other character back up a tile if it is open. These three greetings can affect friends. **Offer Flower** deals 1 damage to an opponent up to two tiles away.

The Bad Bard can Move or perform either song as a direct command. It interrupts that Bad Bard's standing order for one round; directly commanding anyone else lets the song continue. Songs choose their own listener from living opponents anywhere on the board, never a crate, ally or corpse. The ordered forecast names the listener and shows whether they lose their turn; refreshing the same forecast never rerolls it. A listener who laughs is immune to more laughter through the entire following round, but the Sonnet still hurts them. With two opponents and no other interference, a standing Melody alternates between them. With one, the Bad Bard sings without an eligible listener every other round.

To try it in the standalone patrol, launch `godot --path games/company-of-unlikely-heroes -- --mission=bridge_patrol --party=bard,healer,knight`. Set the Bad Bard's standing order to **Inspiring Melody**, leave the other two on their default orders, and commit three rounds, comparing the listeners. Switch to **Healing Sonnet** for round four to see damage against the raider who just laughed. Before committing, preview a Move for another hero to leave the song in place, then replace the command with a Bad Bard Move to see the song drop out of the forecast.

#### Try the Hobby Smith

The standing order **Try This** fits the nearest other living deployed hero, with ties going to the earlier hero in deployment order. If that hero is already **Fitted**, the Smith waits instead of choosing someone else. A direct **Try This** lets you choose another living deployed hero anywhere on the board. It uses your one command for the round; the wearer still follows their standing order. Normally the Smith can keep only one teammate fitted, so fitting a different hero replaces the old fitting.

On the wearer's turn, the fitting changes the next eligible ability they actually use, whether it comes from a direct command or a standing order. The alternate replaces the ordinary action; it is not a second action. If the alternate has no legal use but the ordinary ability can still run, the **Forecast** shows the ordinary action and the fitting stays. For example, with no wounded hero for **Mending Blast** to heal, the Caster can still use ordinary **Blast**, which can hit an ally or obstacle. Check the forecast for the actual target. If neither form is legal, the hero can wait or move as their order allows. Move, Hold and skipped turns also keep the fitting; the wearer falling or the mission ending clears it.

From the repository root, try this stock opening without a guild purchase:

```sh
godot --path games/company-of-unlikely-heroes -- --mission=hold_the_line --party=blacksmith,knight,healer
```

Leave the default orders alone. Select the Anxious Knight, choose the visible **Push → Pull** ability, and target the Bruiser at **G3**. The forecast shows the Smith fitting the Knight first, then the Knight pulling the Bruiser one tile closer to **F3**. Before committing, clear the command and compare: the Knight's standing **Guard** now becomes **Clear the Floor**, which shoves nearby allies as well as enemies instead of shielding them.

The game collects no playtest telemetry. The question to take away: **Did you enjoy trusting two of these people while you took charge of the third?**

### Cast sprites in battle

Stock battles use Blender-rendered sprites for the heroes, the undead summons, and the field cast. The Hobby Smith and the Supply Wagon have their own sprite sheets. A flock shares one Sheep model; the three bandit siblings and the three rival heroes each have their own. The [cast inventory](../../.lore/work/games/company-of-unlikely-heroes/art/non-hero-cast.md) links models to missions. The [runtime manifest](assets/cast/manifest.json) maps performances to packaged sprite sheets; playing them needs neither Blender nor historical renders. The packaged audio assets need the first-launch import described above.

From the repository root, try `godot --path games/company-of-unlikely-heroes -- --mission=hold_the_line` and commit through round four to see the reserve Archer and War Drummer. Other showcases are `mirror_company` for the rival trio, `great_sheep_escape` for the flock and shepherd, and `last_wagon` for the loaded wagon advancing, stalling, and breaking down. For the Ferryman, launch `--mission=company_rescue --party=knight,healer,wizard`.

The [stock scene verification guide](tools/cast/verify_stock_scenes.md) describes how to run checks for stock openings and supported committed-action cases. The earlier heroes and summons retain their prior battle artwork; the original [static summon sources](assets/summons/README.md) are also preserved.

Preview updates the forecast without resolving the round or starting action playback. Commit resolves the round, then plays supported actions from that committed round in order of their key moments; recoveries can overlap later actions. Playback is cosmetic, and not every ability has its own clip.

**Options** includes persistent **Master**, **Music**, and **Sound effects** volume controls. In battle, open **Options → Volume**. Master scales both categories; setting any control to zero mutes it without changing the other settings. Music continues playing while muted. Staging an authored move makes a quiet pencil sound; forecasts stay silent. Supported moves and actions play their sounds during committed playback. To try the Friendly Crypter, launch `goblin_mob` and follow the opening above.

Use **Forfeit** during an ongoing battle to concede without playing the next round. Confirm to end the mission as a defeat, or cancel to keep your plans. In a commission, defeat ends the run without a reward; returning to the guild clears its upgrades. In a standalone mission, use **Restart** to try again.

### Rewards between missions

After a victory with another mission ahead, the debrief shows **one offer per eligible deployed hero**. Each entry describes what changes, its rarity, and how many times you can take it during this outing. Choose **one reward total** using its **Take reward** button, or use Tab and Enter. The claimed reward stays on the debrief while you review the party and continue. Passing on an offer does not count against its cap. If there are no eligible offers, you can continue without choosing.

Rewards start in the next mission. Extra maximum HP comes with the same amount of current HP, but does not erase existing wounds. In combat, open **Outing upgrades** above the round controls to review what each hero gained. New abilities and orders appear alongside those from the base kit. For example, **Shield Throw** shows an outlined shield where it will land in the forecast, then a filled marker while it is on the board. Point at the tile to inspect it; **Advance** heads toward it so the Anxious Knight can recover it. **Say Hello to That One** names the summons' directed target in the forecast and on tile inspection.

The Mixologist’s seven rewards include **Plain Tonic**, a heal without a random reaction, and **Keep the Culture**, which lets you repeat the last recipe and its exact reaction on a different recipient. The bottle is spent on use and is empty at the start of a new mission.

The Hobby Smith's **Leather Apron** adds maximum HP. **Heavier Hammer** adds Hammer Time damage, and **Follow Through** lets the Smith step onto a defeated target's tile if the Smith survives the defeat effects and can still enter it. Both hammer rewards require Hammer Time to be equipped. **Reinforced Rivets** reduce the wearer's next hit by 1 per copy while fitted. **Fine Adjustment** adds 1 to the alternate's main damage, healing or protection, or grants **Steady Hands** to reduce the wearer's next hit by 1 before their next turn. It does not boost an ordinary fallback or stack with Inspiration. **Quick Release** lets the wearer spend their direct command to remove the fitting and step one tile; ordinary Move keeps it. **Double Shift** lets two teammates hold fittings at once, but standing Try This still checks only the nearest.

There is no **hero upgrade offer** after a final victory or defeat, or in standalone missions. Returning to the guild clears all outing upgrades. Commission pay and permanent guild petitions are separate from these temporary rewards.

### Author a variation

The built-in catalog starts at `content/catalog.json`. Shared definitions and adventure content are authored separately and loaded as one catalog. Commission settings provide the eligible recruitment roster. Reported missions provide deployment slots rather than prescribing the player's heroes. Placement IDs identify individual NPCs and objects; multiple placements can use the same definition. Character fields override class defaults as whole fields. New mechanics need code; new combinations of existing handlers need only data. Stock and custom standalone missions use the same storybook controls. See the [catalog guide](content/README.md) for custom catalog loading and authoring rules.

### Recheck the build

The [guild book art review instructions](assets-source/guild-book/README.md) describe how to regenerate captioned sheets and run the review tool's self-test. For a graphical capture of the actual game flow with an isolated profile, use the command and output requirements in [capture_guild_book.gd](tools/capture_guild_book.gd). Its battle driver uses a mixture of input and menu signals, and its commission defeat is controlled; captures are disposable local evidence. The [help screenshot recipe](assets/help/README.md) describes how to reproduce the book's game captures.

From the repository root, check the default commission flow through the game controls with an isolated test profile:

```sh
godot --headless --path games/company-of-unlikely-heroes --script res://tests/journeys/commission_scene_test.gd
```

From the game directory, run the suites with `godot --headless --script res://tests/<area>/<name>.gd`:

| Suite | What it checks |
|---|---|
| `content/catalog_test` | Invalid definitions, independent worlds, and interaction capabilities |
| `content/catalog_bundle_test` | Authored parts load into one catalog; duplicate IDs and invalid deployment slots are rejected |
| `content/commission_catalog_test` | Validation of commission settings, reports, and mission pools |
| `expedition/commission_routes_test` | Seeded boards, both commission lengths, clue matching, rewards, and destination transitions |
| `journeys/commission_scene_test` | Guild creation and reload, recruitment before reports, reward gating, carryover, and board renewal |
| `presentation/practice_scene_test` | Founding practice, relaunch, skip, replay, lesson controls, and unchanged guild progress |
| `presentation/help_book_scene_test` | Help navigation and screen state, hints preference, practice access, and battle help |
| `guild/guild_profile_test` | Local profile creation, reload, seed renewal, and invalid data |
| `content/content_test` | Extra crate, alternate knight kit and habit, relocated escort destination |
| `battle/single_battle_ui_test` | Stock and custom standalone missions through the same battle controls |
| `journeys/standalone_victory_test` | Independent winning routes for all 15 frontier missions through public standalone launches, with forecast and commit checked through the scene |
| `journeys/village_outing_scene_test` | Standalone village mission openings and three wins using a bounded forecast-driven scene player |
| `battle/rules_test` | Ability interactions and command rules |
| `expedition/rescues_test` | Fixed-start rescues, loss, and restart |
| `expedition/rewards_test` | Authored hero pools, seeded offers, caps, selection, carryover, and outing reset |
| `battle/hero_upgrade_effects_test` | Upgrade effects, learned actions and orders, and consistency between preview and commit |
| `presentation/hook_overlay_scene_test` | Hook landing and earlier movement appear as separate forecast paths |
| `battle/rogue_test` | Rogue dodge, redirect, retreat, and hybrid forecast consistency |
| `battle/necromancer_test` | Summons, corpse selection, greetings, round order and forecast consistency, and expedition boundaries |
| `battle/bard_test` | Both persistent songs, seeded listeners, skipped turns and full-round laughter immunity, damage, and direct-command interactions |
| `presentation/laughter_presentation_test` | A laughing hero loses their turn without being shown as knocked down in the command editor or debrief |
| `presentation/storybook_gate_scene_test` | Board clicks, keyboard movement, automatic and aimed actions, and standing orders |
| `journeys/commission_storybook_scene_test` | Normal launch through commission, recruitment, route selection, board input, and round commitment |
| `presentation/storybook_gate_outcome_scene_test` | Forecast-vacated movement, tile inspection, and a legal eight-round victory followed by restart |

These two scene tests should use fresh isolated player data; the help test requires `OLR_TEST_SANDBOX` and `XDG_DATA_HOME` to be the same fresh absolute directory. From the repository root:

For OS-delivered F1, rerun `help_book_scene_test` on graphical X11 with XTEST and Python 3, a fresh matching sandbox and `XDG_DATA_HOME`, and no `--headless`; headless skips this assertion, and the game runtime needs neither Python nor X11 test dependencies.

```sh
(
  set -e
  sandbox=$(mktemp -d /tmp/opencode/olr-scene-tests.XXXXXX)
  export OLR_TEST_SANDBOX="$sandbox" XDG_DATA_HOME="$sandbox"
  godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/help_book_scene_test.gd
  sandbox=$(mktemp -d /tmp/opencode/olr-scene-tests.XXXXXX)
  export OLR_TEST_SANDBOX="$sandbox" XDG_DATA_HOME="$sandbox"
  godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/practice_scene_test.gd
)
```

Run `godot --script res://tests/presentation/bridge_art_test.gd` from this game directory in a graphical session to check the **rendered** shore tint and exit flag. It compares the board before and after moving the objective; no reference screenshot is required.

Run `godot --script res://tests/presentation/outing_art_test.gd` in a graphical session to check the new figures and the marked objective zone with tactical overlays.
