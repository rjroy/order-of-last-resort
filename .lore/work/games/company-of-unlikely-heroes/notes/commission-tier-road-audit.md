---
title: Commission tier road audit and POC pool
date: 2026-11-27
status: draft
tags: [commission, road-missions, encounter-design, balance]
modules: [commission-system, mission-catalog]
related: [.lore/work/games/company-of-unlikely-heroes/experiments/005-encounter-catalog/record.md, .lore/work/games/company-of-unlikely-heroes/experiments/006-commission-routes/record.md]
---

# Commission tier road audit and POC pool

## Scope and evidence standard

This is a provisional design and catalog-feasibility proposal for tiering
commission **roads**, not a balance finding or authorization to implement it.
The short/long finale assignments and balance work remain with `olr-yfl`.
There are no tier-6 roads.

The slot bands under discussion are tier 1 at slots 1–2, tier 2 at 3–4, tier 3
at slot 5, tier 4 at 6–7, and tier 5 at 8–9. Slot 5 is a road in a long
commission; in a short commission the same slot is its finale and is out of this
road pool. Slot 10 is a finale. Do not interpret a mission's existing `tier`
field as proof of its commission difficulty; the live road catalog currently
labels only `bridge_patrol` tier 1 and the other ten roads tier 2.

The commission route code draws by mission **kind**, not by the mission `tier`
field. At a fork it selects two different kinds; a promised kind is required on
the next fork. Within a selected kind, an unvisited mission is preferred; a
repeat becomes unavoidable if that kind has no unvisited member. Therefore a
tiered implementation must filter candidates to the slot's tier before drawing,
and must promise only kinds eligible at the next tier. This note's pool is a
manifest-ready design roster, but production catalog/report changes and
tier-aware routing are separate work.

Authored HP below means placement maximum HP after class inheritance and any
mission-local override. Enemy attacks and behavior values are current authored
facts; tier and relative pressure judgments are conjecture. A useful rough
breakpoint is a 2-damage hit: 3 HP takes two such hits, 4 HP also takes two, and
5 HP takes three. This is not a universal damage model or a substitute for
round/command/carryover play evidence.

## All 11 current road missions

| Mission / ID | Kind | Authored enemy placements and HP | Provisional tier | Basis and limits |
|---|---|---|---:|---|
| Trouble on the Road / `bridge_patrol` | Skirmish | `raider_one`, `raider_two`: Harpooners inherit 6 HP each from `shared/common.json`'s `enemy` class. | 1 | Two opponents; the guide calls this an untimed patrol. Low-tier anchor by count and interaction, not proven easy: each has a long HP bar and ranged reach. |
| The Goblin Mob / `goblin_mob` | Skirmish | `northwest`, `southwest`, `northeast`, `southeast`, `east`: Goblins, 1 HP each. | 1 | Five enemies die to one 1-damage hit each, but can crowd for +1 damage and approach from both sides. More activations than the patrol; complexity does not itself establish higher overall pressure. |
| The Harpoon Squad / `harpoon_squad` | Ambush | `hookhand` 3; `harpooner` inherits 6; `bruiser` 3 HP. | 2 | Pull can set up the 3-damage adjacent Bruiser strike. Three threats and a legible opening response; likely a moderate step above the patrol, but not measured. |
| The Shield Wall / `shield_wall` | Formation | `shieldbearer_1`, `shieldbearer_2` 4 each; `archer_3` 3 HP. | 2 | Each adjacent Shieldbearer reduces damage to the Archer by 1. Fighting guards or breaking adjacency changes the target/command decision; high interaction does not automatically mean high attrition. |
| The Cowardly Captain / `cowardly_captain` | Formation | `grunt_1`, `grunt_2`, `captain_3`: 3 HP each. | 2 | Grunts gain +1 attack damage beside the retreating Captain. The player must address proximity and target selection; pressure versus other tier-2 options is unknown. |
| The Explosive Situation / `explosive_situation` | Ambush | `bomber_1`, `bomber_2`: 2 HP each; `harpooner_3`: inherited 6 HP. | 2 | Each Bomber's death deals 2 adjacent damage to every living character, friend or foe; Bombers can chain. Large swing potential, including a shortcut, makes HP count alone misleading. |
| The Unfortunate Healer / `unfortunate_healer` | Formation | `bruiser_1`, `bruiser_2`, `enemy_healer_3`: 3 HP each. | 2 | Two Bruisers plus a Healer with two 2-HP heals; sustained attacks and limited healing change target priority. Could cost more than some proposed tier-2 roads. |
| The Duelists / `duelists` | Skirmish | `duelist_1`, `duelist_2`: 4 HP each. | 2 | A surviving Duelist retaliates for 1 if its damaging attacker remains adjacent. Range and displacement are ordinary answers; two 4-HP targets make attrition relevant. |
| The Odd Couple / `odd_couple` | Ambush | `ogre_1` 6; `trickster_2` 3 HP. | 2 | The Trickster can swap with the heavy Ogre once. Spacing and swap timing create a single large threat-position change; exact carryover cost is unmeasured. |
| The Mirror Company / `mirror_company` | Rival band | `rival_knight_1` 5; `rival_wizard_2`, `rival_healer_3` 3 HP each. | 2 | Push, nearest-target blast, and two enemy heals combine recognizable rival roles. Plausibly among the hardest roads, but victory checks do not compare its pressure. |
| The Last One Standing / `last_one_standing` | Rival band | `bandit_damage_1`, `bandit_guard_2`, `bandit_swift_3`: 3 HP each. | 2 | Defeats strengthen survivors: Fierce gains damage, Swift gains movement, and Guard gets damage reduction. Kill order is a real decision; whether this exceeds tier 2 requires play evidence. |

Placement IDs, HP, abilities, and mission-local overrides are in the linked
`content/missions/<id>.json`; shared inherited values and abilities are in
`content/shared/common.json` and `content/shared/encounters.json`. In particular,
the base enemy class has 6 HP, enemy harpoons deal 2 damage at range, Hookhand
pulls at range 2, and Bruiser Strike deals 3 adjacent damage.

## Provisional POC pool roster

The roster distinguishes mission IDs from **base encounter IDs**. `light_hook_pair`
is a light variant of the `harpoon_squad` base: it removes the Bruiser but keeps
the Hookhand/Harpooner interaction. Variants are unique reportable missions but
share their base's tactical identity for repeat accounting. Do not overwrite
accepted originals.

| Tier | Mission ID | Kind | Base encounter ID | Baseline → proposed authoring |
|---:|---|---|---|---|
| 1 | `bridge_patrol` | Skirmish | `bridge_patrol` | Existing; two Harpooners at 6 HP each. |
| 1 | `goblin_mob` | Skirmish | `goblin_mob` | Existing; five Goblins at 1 HP each. |
| 1 | `light_hook_pair` **(new)** | Ambush | `harpoon_squad` | Copy `village_lane` and its three party slots; `hookhand` 3 HP at `[3,2]`, `harpooner` 6 HP at `[4,1]`; omit `bruiser` at `[2,3]`. Light pull threat without the 3-damage follow-up. |
| 2 | `harpoon_squad` | Ambush | `harpoon_squad` | Existing; Hookhand/Harpooner/Bruiser at 3/6/3 HP. |
| 2 | `explosive_situation` | Ambush | `explosive_situation` | Existing; two 2-HP Bombers and a 6-HP Harpooner. |
| 2 | `duelists` | Skirmish | `duelists` | Existing; two 4-HP Duelists. |
| 2 | `cowardly_captain` | Formation | `cowardly_captain` | Existing; three 3-HP enemies. |
| 2 | `shield_wall` | Formation | `shield_wall` | Existing; 4/4/3 HP Shieldbearers/Archer. |
| 3 | `last_one_standing` | Rival band | `last_one_standing` | Existing; three 3-HP Bandits. Their survivor changes create a choice, not proven extra difficulty. |
| 3 | `veteran_shield_wall` **(new variant)** | Formation | `shield_wall` | Clone `frontier_field`; `shieldbearer_1` `[4,1]`, `shieldbearer_2` `[4,3]` max HP 4→**5**; `archer_3` `[4,2]` remains 3. Each guard takes three rather than two 2-damage hits; makes bypass/protection-breaking more costly. |
| 3 | `veteran_explosive_situation` **(new variant)** | Ambush | `explosive_situation` | Clone `frontier_field`; `bomber_1` `[4,1]`, `bomber_2` `[4,2]` max HP 2→**3**; `harpooner_3` `[5,3]` remains 6. A 2-damage hit no longer kills a Bomber in one hit, allowing reposition/finish decisions. |
| 4 | `unfortunate_healer` | Formation | `unfortunate_healer` | Existing; two 3-HP Bruisers and 3-HP Healer with two 2-HP heals. |
| 4 | `odd_couple` | Ambush | `odd_couple` | Existing; 6-HP Ogre, 3-HP Trickster with one swap. |
| 4 | `mirror_company` | Rival band | `mirror_company` | Existing; 5-HP Knight, 3-HP Wizard and Healer. |
| 5 | `veteran_mirror_company` **(new variant)** | Rival band | `mirror_company` | Clone `frontier_field`; `rival_wizard_2` `[2,4]` max HP 3→**5**; Knight `[4,2]` and Healer `[4,1]` unchanged. Wizard takes three rather than two 2-damage hits. |
| 5 | `veteran_unfortunate_healer` **(new variant)** | Formation | `unfortunate_healer` | Clone `frontier_field`; `enemy_healer_3` `[5,2]` max HP 3→**5**; Bruisers `[4,1]`, `[4,3]` remain 3. Direct support removal takes one extra 2-damage hit. |
| 5 | `veteran_odd_couple` **(new variant)** | Ambush | `odd_couple` | Clone `frontier_field`; `ogre_1` `[4,2]` max HP 6→**8**; `trickster_2` `[5,3]` remains 3. The one-use swap is not prolonged; the heavy 3-damage Ogre threat now survives one extra 2-damage hit. |
| 5 | `crossfire_blast_lane` **(new base)** | Ambush | `crossfire_blast_lane` | Distinct base described below; uses existing Hookhand, Bomber and Harpooner behavior. |

There are **seven new mission IDs**: one light variant, two tier-3 variants,
three tier-5 variants, and one new base. Four different base IDs now cover the
four road slots in tiers 4–5 (`unfortunate_healer`, `odd_couple`,
`mirror_company`, `crossfire_blast_lane`), fixing the prior guaranteed repeat
caused by only three bases. This does not prevent a player from choosing the
same base on different roads.

### New base scenario: Crossfire at the fuse line

- **Mission/base ID:** `crossfire_blast_lane`; kind `ambush`; defeat-all.
- **Board and party slots:** reuse the 7×5 `road` board and party slots
  `[[1,1],[1,2],[1,3]]` from `bridge_patrol.json`.
- **Placements:** `crossfire_hookhand` (`hookhand`, 3 HP) at `[3,2]`;
  `crossfire_bomber` (`bomber`, 2 HP) at `[3,1]`;
  `crossfire_harpooner` (`harpooner`, inherited 6 HP) at `[5,3]`.
- **Bomber data:** copy the existing mission-local `bomber`,
  `bomber_strike`, and `frontier_bomber_strike` definitions and its 2-damage,
  range-1 `death_blast` trait from `explosive_situation.json`; retain its
  existing cast key/art. No new handler or art is needed.
- **Field report:** “The Hookhand can pull a hero toward a 2-HP Bomber. When the
  Bomber falls, its 2-damage blast hits everyone beside it, friend or foe. A
  Harpooner can strike from two tiles away. Check the pull landing and blast
  before closing.”
- **Decision:** keep a hero outside the pull lane and attack the Hookhand, or
  accept/induce the pull and exploit the Bomber blast against the enemy cluster.
  Ordinary movement/ranged attack is one answer; an early direct push or chosen
  ranged hit on the Bomber is another. Forecast must expose pull landing,
  Bomber approach/attack, and death blast before commitment.
- **Reason and limit:** this is a genuinely distinct base combination of
  existing rules and actors, and supplies the fourth base needed across slots
  6–9. Tier 5 is only a pool-coverage hypothesis; the pressure has not been
  tested against fresh or wounded companies.

The 3→5 variants add one hit at the 2-damage breakpoint; the 4→5 Shieldbearer
change does the same; Bomber 2→3 changes one-hit defeat to two hits; Ogre 6→8
adds one 2-damage hit. The HP changes have explicit response consequences but
remain conjectures and may over-tax wounded companies.

### Tier-aware fork and full-path coverage

Adjacent tiers do **not** need kind overlap. A road's clue is selected from the
next tier after considering traversed base IDs plus the hypothetical base ID
on that report. Proposed draw rules:

1. Filter missions to the current slot's tier. Offer two distinct kinds; include
   the promised kind, then prefer another kind with a fresh base if available.
2. Within each kind, prefer a mission with an unvisited base ID, then an
   unvisited mission ID, then allow a repeat only if no fresh option remains.
3. For each report candidate, choose its onward clue from the next tier using
   `visited_base_ids + [candidate_base_id]`; prefer a kind with two fresh bases,
   otherwise a kind with one or more, otherwise any eligible kind. The chosen
   report's promise is guaranteed to be present at the next fork.
4. Prefer two fresh-base options at every fork; require at least one fresh-base
   option for every reachable route history. A second card can repeat a base
   only where no fresh base in a distinct kind is available.

The checker below uses memoized state `(road position, visited mission IDs,
visited base IDs, promised kind)`, so histories with identical future-relevant
state are checked once. It covers both the short road sequence
`T1,T1,T2,T2` and the long sequence `T1,T1,T2,T2,T3,T4,T4,T5,T5`; finales are
not road tiers. It explores distinct offer kinds, every eligible mission choice,
both route choices, and every preferred next-tier clue. It asserts each
reachable fork has a fresh-base offer and every clue kind exists in the next
slot. A 10,000-seed simulation then reports how often a repeated-base card is
shown under these preferences. This validates pool feasibility, not balance,
wording, or player experience.

Exact command:

```sh
python3 - <<'PY'
from functools import lru_cache
import random

# Each tuple is (mission ID, base encounter ID).
P={
 1:{'skirmish':[('bridge_patrol','bridge_patrol'),('goblin_mob','goblin_mob')],
    'ambush':[('light_hook_pair','harpoon_squad')]},
 2:{'ambush':[('harpoon_squad','harpoon_squad'),('explosive_situation','explosive_situation')],
    'skirmish':[('duelists','duelists')],
    'formation':[('cowardly_captain','cowardly_captain'),('shield_wall','shield_wall')]},
 3:{'rival_band':[('last_one_standing','last_one_standing')],
    'formation':[('veteran_shield_wall','shield_wall')],
    'ambush':[('veteran_explosive_situation','explosive_situation')]},
 4:{'formation':[('unfortunate_healer','unfortunate_healer')],
    'ambush':[('odd_couple','odd_couple')],
    'rival_band':[('mirror_company','mirror_company')]},
 5:{'rival_band':[('veteran_mirror_company','mirror_company')],
    'formation':[('veteran_unfortunate_healer','unfortunate_healer')],
    'ambush':[('veteran_odd_couple','odd_couple'),
              ('crossfire_blast_lane','crossfire_blast_lane')]}}
PATHS={'short':(1,1,2,2),'long':(1,1,2,2,3,4,4,5,5)}

def check(path):
    stats={'forks':0,'fresh2':0,'fresh1':0,'repeat_cards':0,'promise_edges':0}
    def missions(tier,kind,ids,bases):
        xs=P[tier][kind]
        fresh=[x for x in xs if x[1] not in bases]
        if fresh:return fresh
        fresh=[x for x in xs if x[0] not in ids]
        return fresh or xs
    def hints(nexttier,bases):
        counts={k:sum(b not in bases for _,b in xs) for k,xs in P[nexttier].items()}
        spare=tuple(sorted(k for k,n in counts.items() if n>=2))
        fresh=tuple(sorted(k for k,n in counts.items() if n>=1))
        return spare or fresh or tuple(sorted(P[nexttier]))
    @lru_cache(None)
    def walk(pos,ids_t,bases_t,promised):
        if pos==len(path):return
        tier=path[pos]; nxt=path[pos+1] if pos+1<len(path) else None
        ids,bases=set(ids_t),set(bases_t); kinds=tuple(sorted(P[tier]))
        firsts=(promised,) if promised else kinds
        for first in firsts:
            assert first in P[tier]
            fresh_other=[k for k in kinds if k!=first and
                         any(b not in bases for _,b in P[tier][k])]
            for second in (fresh_other or [k for k in kinds if k!=first]):
                assert first!=second
                for a in missions(tier,first,ids,bases):
                    for b in missions(tier,second,ids,bases):
                        offers=(a,b)
                        fresh=sum(base not in bases for _,base in offers)
                        assert fresh>=1,(pos,tier,bases,offers)
                        stats['forks']+=1
                        stats['fresh2' if fresh==2 else 'fresh1']+=1
                        stats['repeat_cards']+=2-fresh
                        for mission,base in offers:
                            ids2=tuple(sorted(ids|{mission}))
                            bases2=tuple(sorted(bases|{base}))
                            if nxt is not None:
                                for hint in hints(nxt,set(bases2)):
                                    assert hint in P[nxt]
                                    stats['promise_edges']+=1
                                    walk(pos+1,ids2,bases2,hint)
    walk(0,(),(),None)
    stats['states']=walk.cache_info().currsize
    return stats

for name,path in PATHS.items():
    print(name, path, check(path))

def sample(seed,path):
    r=random.Random(seed); ids=set(); bases=set(); promise=None
    repeats=cards=onefresh=0
    for pos,tier in enumerate(path):
        kinds=tuple(sorted(P[tier]))
        first=promise or r.choice(kinds)
        other=[k for k in kinds if k!=first and
               any(b not in bases for _,b in P[tier][k])]
        second=r.choice(other or [k for k in kinds if k!=first])
        def pick(kind):
            xs=P[tier][kind]
            return r.choice([x for x in xs if x[1] not in bases] or
                            [x for x in xs if x[0] not in ids] or xs)
        offered=[(first,pick(first)),(second,pick(second))]
        fresh=sum(item[1][1] not in bases for item in offered)
        assert fresh>=1
        repeats+=2-fresh; cards+=2; onefresh+=(fresh==1)
        _,(mission,base)=r.choice(offered)
        ids.add(mission); bases.add(base)
        if pos+1<len(path):
            counts={k:sum(b not in bases for _,b in xs)
                    for k,xs in P[path[pos+1]].items()}
            promise=r.choice([k for k,n in counts.items() if n>=2] or
                             [k for k,n in counts.items() if n>=1] or
                             list(P[path[pos+1]]))
    return repeats,cards,onefresh

N=10000
for name,path in PATHS.items():
    runs=[sample(seed,path) for seed in range(N)]
    repeats=sum(x[0] for x in runs); cards=sum(x[1] for x in runs)
    one=sum(x[2] for x in runs)
    print(f'{name}: repeat-base cards={repeats}/{cards} ({repeats/cards:.1%}); '
          f'one-fresh forks={one}/{N*len(path)} ({one/(N*len(path)):.1%})')
print('PASS: memoized full-path tier/base coverage')
PY
```

Expected exit `0`; exhaustive coverage ends with
`PASS: memoized full-path tier/base coverage`. The seeded estimate is specific
to these declared preferences, not production probability. A repeat card can
still be offered; the gate ensures a fresh-base alternative remains available.
Observed output:

```text
short (1, 1, 2, 2) {'forks': 106, 'fresh2': 104, 'fresh1': 2, 'repeat_cards': 2, 'promise_edges': 104, 'states': 41}
long (1, 1, 2, 2, 3, 4, 4, 5, 5) {'forks': 2826, 'fresh2': 1232, 'fresh1': 1594, 'repeat_cards': 1594, 'promise_edges': 4844, 'states': 1551}
short: repeat-base cards=5098/80000 (6.4%); one-fresh forks=5098/40000 (12.7%)
long: repeat-base cards=19729/180000 (11.0%); one-fresh forks=19729/90000 (21.9%)
PASS: memoized full-path tier/base coverage
```

## Material gaps and validation gate

The coverage gap is **base-encounter monotony**, not a missing objective
handler. `crossfire_blast_lane` is the one new tactical concept scoped here under
`olr-6r4`; it combines existing Hookhand, Bomber, and Harpooner rules, retaining
defeat-all. No new objective rule, asset, or actor art is required. The material
runtime integration gap is tier/base-aware route selection and report promises;
the checker proves the proposed roster can satisfy those constraints, not that
production currently applies them.

Before treating tiers as balanced, play different legal companies both fresh
and plausibly wounded. Compare rounds, direct commands, HP remaining, fallen
heroes, and resulting next-leg condition. Include ordinary movement and an
ability/order-based answer; check for an unadvertised shortcut, report clarity,
forecast/commit agreement, and whether a costly route is a real choice. Existing
experiment 005 replayed authored routes mechanically but explicitly left human
difficulty, enjoyment, and voluntary replay unmeasured; experiment 006's
controlled wins used 1-HP opponents and were not encounter balance evidence.
