# Guild book reward illustrations: Knight and Healer

The 17 reward definitions below were inventoried from `content/expedition/rewards.json` before illustration. These are adventure rewards, not guild perks. Artwork shows the reward's change; the interface supplies the class identity, rule text, rarity, and remaining availability.

Visual references: the approved Knight turnaround and guard study (`.lore/work/games/company-of-unlikely-heroes/art/concepts/knight/`), Healer field-medic study (`art/concepts/healer/`), model reference poses under `art/models/`, and the framed Marked-Up Illustration (`art/concepts/storybook-ux/marked-up-illustration-framed.png`). The Knight's shield is tapered oak with a riveted rim and an ochre griffin, held on the left; his tabard is weathered blue. The Healer's tools are a blunt wooden crook and heavy offset satchel; the hands are wrapped. Her model establishes the short, downward Bonk, rather than the concept's broad horizontal stance.

## Inventory and visual brief

| Reward ID | Label | Implemented change | Visual cue |
|---|---|---|---|
| `knight_hp_1` | +1 HP | 1 maximum and current HP on next deployment | One broad canvas repair on the blue griffin tabard |
| `knight_hp_2` | +2 HP | 2 maximum and current HP on next deployment | Two clearly separate repairs on the same tabard |
| `knight_hp_5` | +5 HP | 5 maximum and current HP on next deployment | The same tabard fully lined and reinforced, with five bold patches |
| `knight_shield_damage_1` | +1 shield damage | Reflected damage and Shield Throw deal 1 more damage | One strong riveted striking boss on the shield rim |
| `knight_shield_damage_3` | +3 shield damage | Reflected damage and Shield Throw deal 3 more damage | Three striking bosses on the same rim, reinforced by a broad iron strip |
| `knight_dig_in` | Dig In | While guarding, reverse an enemy pull against the Knight | Knight's planted boots, shield and taut hook line pulling its caster forward |
| `knight_shield_throw` | Shield Throw | Range 3, damage 3; must retrieve to throw or guard again; Advance heads toward it | Detached shield tumbling toward a straw practice target |
| `knight_wide_guard` | Wide Guard | Guard covers one extra tile of range | Guarding Knight and a protection arc extending to an additional ally tile |
| `healer_hp_1` | +1 HP | 1 maximum and current HP on next deployment | Heavy, offset field satchel with one spare roll fastened to its exterior |
| `healer_hp_2` | +2 HP | 2 maximum and current HP on next deployment | Same field satchel with two separately readable spare rolls |
| `healer_bonk_damage_1` | +1 Bonk damage | Bonk deals 1 more damage | Wooden crook knocking one deep dent in a practice helmet |
| `healer_bonk_damage_2` | +2 Bonk damage | Bonk deals 2 more damage | The same downward crook knocks the practice helmet farther down with a bigger dent |
| `healer_heal_1` | +1 heal | Heal restores 1 more HP | Wrapped hand placing one broad herbal dressing on an ally's forearm |
| `healer_heal_2` | +2 heal | Heal restores 2 more HP | Wrapped hand placing a second distinct dressing on the same ally's forearm |
| `healer_long_staff` | Long Staff | Bonk reaches one tile farther | Visible splinted wood extension on familiar crook |
| `healer_strong_swing` | Strong Swing | Bonk also hits other opponents within range | One crooked staff sweeps multiple enemy practice helmets off their pegs |
| `healer_me_or_you` | Me or You | Full heal to wounded Healer; otherwise split evenly across all other living deployed heroes, even those already full; remainders in party order, unused healing lost | Healer's palm across her own chest on one side, measured dressings handed to several other heroes on the other |

## Source provenance and reproduction

These are candidates, not player-approved artwork. The connected study review released generation of the full set, not visual acceptance of the files below.

| Native source | Dimensions | Built-in image job, `openai/gpt-image-2` |
|---|---:|---|
| `kh-gear-native.png` | 1448 × 1086 | `image_201b9b980001klL1MHIq8WfK3L` |
| `kh-action-native.png` | 1448 × 1086 | `image_201b9f2d00014XPwOvNPrlCG5k` |
| `kh-heal-native.png` | 1774 × 887 | `image_201ba2751001MT4KErAijiCMQK` |
| [`../study/connected-study.png`](../study/README.md) | 1536 × 1024 | Shared study; the Shield Throw crop uses its reward plate |

Built-in jobs ran in the November 21–22, 2026 session. They used the connected study's reward plate and prop/action crops from the references above. The gear atlas pairs the patched tabards with the bandage satchels and crook extension; the action atlas pairs the shield boss and helmet impact changes with the guard variations; the healing atlas pairs the dressings with the target-count changes. The durable sheets are byte-for-byte copies of the original generated outputs. `crops.json` records their SHA-256 checksums and explicit pixel rectangles. The study is referenced in place, not duplicated.

From the repository root, extract the derivative candidates using Python 3 and ImageMagick (`7.1.2-34` used here):

```sh
python games/company-of-unlikely-heroes/assets-source/guild-book/upgrades-knight-healer/crop.py
```

Use `--out <directory>` to build elsewhere for a byte comparison without overwriting the packaged files. The script checks the sheet hashes, crop bounds, output sizes and exact ID coverage against `content/expedition/rewards.json`. It writes 636 × 308 opaque RGB PNGs in sRGB, using uniform Lanczos resampling with a center trim to match the 318 × 154 art slot at 2× size. The cream is intentional page color, not a substitute for transparency. No lettering, UI furniture or rarity is embedded.
