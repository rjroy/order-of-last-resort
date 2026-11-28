# Combat facts report

From the repository root, after importing the Godot project, use a new output
directory with an existing parent:

```sh
python3 games/company-of-unlikely-heroes/tools/combat_balance/report.py --out .lore/local/combat-facts/new-report
```

The command runs the Catalog exporter once in an isolated XDG environment and
saves its structured export and process log alongside four TSV files and an
offline `index.html`. To use an existing export without Godot, add
`--input path/to/export.json`. Existing output paths are refused.

Default HP comes from Catalog-resolved character profiles. Placement rows show
explicit mission maximum overrides and placement starting HP, even when equal
to defaults, and delayed reserves separately. Raised
zombies use half the corpse's maximum HP rounded up before expedition rewards.
Abilities include profile, starting guild kit, permanent petition and explicit
behavior references. Traits and permanent effect grants have separate rows.
Common direct effects, alchemy doses, conditional collision and recoil, aura,
performances, and movement or status actions have bounded descriptions.
Uninterpreted handlers and traits are marked as such, with their structured
parameters retained for inspection. Fitted forms are referenced, not computed.
Params and base damage are not guaranteed
final damage; conditional effects and mitigation can change results. The report
does not read ability help as numeric evidence or evaluate expedition upgrades.
House Lights is an expedition-only reward and is intentionally excluded.
Store generated reports and exports only under ignored `.lore/local/`; they
are not runtime inputs. The four tables are a bounded reference, not an
exhaustive simulation of combat.
