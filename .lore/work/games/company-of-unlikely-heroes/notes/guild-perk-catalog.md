# The guild petition register

Production brief for `mind-garage-8cf.4`. The following prices are playtest values, not new earnings rules. A road victory pays 1 point; a destination victory pays 5. A four-road loss therefore buys a first recruit or teaching, while a five-mission success (9 points) buys a recruit and a technique. Points and training persist; wounds, song history, summons, and outing upgrades do not. No road or destination is locked by this register.

New guilds start with Knight, Healer and Caster. Each class has two interchangeable slots (offense and utility), plus direct Move. A teaching adds a choice, not a third slot. A new order delegates a specific equipped action; knowing a spell does not automatically grant its donor's habits. A purchased recruit arrives with both native direct actions and their starting orders. Keep Practice and standalone missions unscoped. Established guilds keep their roster and trained options; do not invalidate a saved preference or charge twice for an already owned benefit.

## Permanent purchases

Recipient recruitment is implicit for every training petition. Where a teacher is not a founder, their recruit petition is also required for cross-training. Multiple prerequisites are cumulative. One row is one purchase; short IDs below are durable petition IDs.

| Recipient | ID | Cost | Grant, prerequisite and tactical decision |
|---|---|---:|---|
| Bad Bard | `recruit_bard` | 4 | Recruit with Hold and both musical orders; keep three party places. |
| Daft Dodger | `recruit_rogue` | 4 | Recruit with Retreat and Pass the Blame. The latter marks the nearest legal opponent not already misdirected; ties use initiative order. |
| Friendly Crypter | `recruit_necromancer` | 6 | Recruit with Hold and Make a Friend. If no living skeleton of hers, summon in the legal adjacent square nearest an opponent (stable board-direction tie); otherwise wait. Corpse choice stays manual. |
| Mixologist | `recruit_alchemist` | 5 | Recruit with Follow closest ally, Make Rounds, Hold, and both bottles for direct use. Throw Samples is separate training. |
| Anxious Knight | `knight_rescue_line` | 4 | **Rescue Line** (utility instead of aura): choose a pullable friendly character exactly two tiles away and draw them one open tile toward the Knight. No recoil; too close or blocked doesn't work. |
| Anxious Knight | `knight_escort_order` | 3 | **Stay Close**: follow the closest other ally and stop adjacent. Give up automatic Guard to keep pace with a moving patient or companion. |
| Anxious Knight | `knight_learn_bonk` | 4 | Learn the Healer's **Bonk and taunt** as offense instead of Push. Draw attention to the shield bearer without pushing the attacker away. |
| Unimpressed Healer | `teach_healer_blast` | 4 | Learn the Caster's **Blast nearest** in place of Bonk. Hits nearest damageable unit or obstacle, including allies. Neither auto-Blast nor Wizard rewards included. |
| Unimpressed Healer | `healer_blast_order` | 3 | **Blast on Standing Orders**, after `teach_healer_blast`: delegate the learned Blast while another hero gets the direct command. Requires Blast equipped. |
| Unimpressed Healer | `healer_field_dressing` | 4 | **Field Dressing** (utility): directly choose a healable friendly hero within one tile, including herself, to restore 2 HP. Less reach and healing, but no forced self-priority when an ally needs it more. |
| Unimpressed Healer | `healer_triage_order` | 3 | **Triage**, after `healer_field_dressing`: apply the equipped dressing to the most injured legal patient. Unlike Support it will not waste the direct command on choosing a patient. |
| Enthusiastic Caster | `wizard_ring_sparks` | 5 | **Ring of Sparks** (offense): hit *all* adjacent living characters for 2, allies included, without knockdown. Trade a strong single nearest hit for an area effect with a positioning cost. |
| Enthusiastic Caster | `wizard_stand_back` | 3 | **Stand Back**: retreat from the nearest opponent. This orders movement, not an automatic Pull. |
| Enthusiastic Caster | `wizard_learn_dodge` | 5 | After recruiting the Dodger, borrow **Confusing Dodge** as utility. Swap with the farthest character rather than hauling a chosen target and taking recoil. |
| Bad Bard | `song_weaving` | 5 | After `recruit_bard`, learn the passive **Song Weaving**. Switching between the two base songs on consecutive rounds plays the current song then echoes the previous one once. Same song, Hold, skipped turns, or another action yields no echo. Applies equally to direct and standing-order songs. No extra command; echoes keep normal listener rules and do not seed further echoes. |
| Bad Bard | `bard_learn_push` | 4 | Borrow the Knight's **Push** as offense. Make space instead of singing Sonnet, at the cost of losing the two-song combination while it is unequipped. |
| Bad Bard | `bard_follow_company` | 3 | **Follow the Ensemble**: follow the nearest other ally; reposition between performances instead of continuing to sing. |
| Daft Dodger | `rogue_tripwire` | 4 | **Tripwire** (utility): hold the nearest eligible opponent within two tiles against its next voluntary movement, instead of swapping positions. Does not prevent forced displacement. |
| Daft Dodger | `rogue_tripwire_order` | 3 | **Mind the Step**, after `rogue_tripwire`: automatically use equipped Tripwire rather than retreating or passing blame. |
| Daft Dodger | `rogue_learn_potion` | 5 | After recruiting the Mixologist, borrow **Healing Potion** as utility: a small reliable heal plus its forecasted, weighted side effect. Not a safe generic heal. |
| Friendly Crypter | `necro_grave_bell` | 4 | **Grave Bell** (utility): repel the nearest other character one tile if clear, friend or foe. Trade raising zombies for spacing; skeletons remain available. |
| Friendly Crypter | `necro_bell_order` | 3 | **Keep Your Distance**, after `necro_grave_bell`: delegate the equipped bell, accepting its nearest-character quirk while directing someone else. |
| Friendly Crypter | `necro_learn_melody` | 5 | After recruiting the Bard, learn **Inspiring Melody** as utility. Give up raising zombies for a random eligible enemy skip; normal laughter immunity still applies. Does not confer Song Weaving. |
| Mixologist | `alchemist_throw_samples` | 3 | **Throw Samples**: delegate base Acid against the nearest hostile in reach; buying the order neither grants a new bottle nor rerolls its reaction. |
| Mixologist | `alchemist_etching_paste` | 4 | **Etching Paste** (offense): apply 2 damage and the normal acid-biased reaction at range 1, instead of throwing a weaker dose from range 3. The stronger mixture costs positioning. |
| Mixologist | `alchemist_learn_pull` | 5 | Borrow the Caster's **Pull and recoil** as utility; replace Healing Potion to reposition a chosen target, including the full recoil and knockdown drawback. Direct command only. |

**Song resolution detail:** A live song with no eligible listener is still a performance; it does not roll a listener. The echo checks the board *after* the live song. If retaliation or a death blast took the performer out, the Bard cannot perform the echo. Echoes are visible in Forecast and do not add a second hero activation or a second action's objective noise.

**Release bar:** all 26 entries can be earned on one guild without duplicate purchases or dead-end prerequisites. A locked recruit must not leak through normal deployment. Verify at least one actual use per new native ability and order; verify teaching a donor ability does not grant donor habits or rewards. Check a seven-hero guild, a fresh guild, a migrated guild, insufficient funds, off-slot prerequisites, save/reload, and the existing receipt and Forfeit paths. Preserve combat mechanics for ordinary actors without a relevant perk, particularly Bard RNG and immunity.
