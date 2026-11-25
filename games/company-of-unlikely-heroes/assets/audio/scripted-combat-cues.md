# Scripted combat cues

The sound service maps the resolved ability ID and handler to a single stream at
the committed action beat. This also applies to trained abilities: the actor
does not change the sound of the borrowed action. Repeat Batch selects the
stream of the bottled potion, acid, or paste. Movement and planning retain the
approved footfall and pencil; forecasts remain silent.

`presentation/sound_recipes.gd` contains the reproducible recipe parameters.
Each layer specifies its start, duration, starting and ending frequency,
amplitude, decay, and noise filter. The synthesizer mixes swept decaying modes
and low-pass-filtered noise with attack and release ramps into mono 16-bit PCM
at 22,050 Hz. Each noise layer uses a locally seeded integer generator, not
Godot's gameplay RNG. The service generates each requested stream lazily and
caches it across service instances. The pre-existing Heal, Melody, Sonnet,
gesture, and Grave Bell synthesis is also cached lazily. Take the Stage extends
the Sonnet's three notes with a higher fourth note at the same note length.

## Stock mapping

| Action or family | Cue key |
|---|---|
| Shield Throw / Push / Reflecting Aura | `shield_throw` / `shunt` / `aura` |
| Bonk, including rival / Field Dressing / Heal | `bonk` / `dressing` / `heal` |
| Force Blast, including rival / Ring of Sparks / Pull and recoil | approved `blast` / `sparks` / `magic_pull` |
| Rescue Line and Hookhand pull | approved `rope` |
| Tripwire / Confusing Dodge / Wasn't Me | `tripwire` / `dodge` / `misdirect` |
| Inspiring Melody / Healing Sonnet / Take the Stage / War Drum | `melody` / `sonnet` / `stage` / approved `drum` |
| Summon Skeleton / Raise Dead / Grave Bell / nominate | approved `bones` / `raise` / `bell` / `nominate` |
| Skeleton Wave / Don't Go | `bone_wave` / `bone_hold` |
| Zombie Say Hello / Offer Flower | `zombie_hello` / `flower` |
| Healing Potion and Plain Tonic / Acid / Etching Paste | `dose` / approved `potion` / `paste` |
| Harpoon at close range / ranged harpoon and arrow | `shaft` / approved `bow` |
| Generic attack and Shield Bash | approved `shield` |
| Goblin and Trickster / Duelist | `point` / `foil` |
| Captain, Grunt and Bandit / Bruiser and Ogre | `leather_iron` / `maul` |
| Bomber ordinary strike / Wagon strike / Ogre swap | `bomber` / `wagon` / `ogre_swap` |
| Shepherd wave / enemy Field Dressing | `shepherd` / `enemy_heal` |

The Bomber cue is for its ordinary strike, not a death explosion. The existing
playback selects the Harpooner's close shaft using the action-time source and
target cells. Other handlers retain a generic fallback for custom catalog
abilities; unknown handlers remain silent rather than inventing a mapping.
Pull currently has one combined suction/recoil sound because the dispatch beat
does not carry recoil outcome or target material. Likewise, a strike's sound
identifies its action, not a separately detected surface. These mappings and
waveforms are reproducible technical candidates, not evidence of human auditory
approval. For audition, request the key through
`sound_recipes.gd.get_stream(key)` or dispatch the action through
`sound_effects.gd` and capture its player stream.
