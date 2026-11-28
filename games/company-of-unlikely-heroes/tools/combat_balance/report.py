#!/usr/bin/env python3
"""Build factual combat tables from a Catalog export."""

import argparse
import csv
import html
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


PROJECT = Path(__file__).resolve().parents[2]
HP_FIELDS = ["actor_id", "actor", "context", "mission", "placement", "default_max_hp",
             "maximum_hp", "starting_hp", "notes"]
ABILITY_FIELDS = ["actor_id", "actor", "effect_id", "effect", "availability",
                  "handler", "base_effect", "conditions_and_data"]
TABLES = [
    ("heroes_hp.tsv", "Heroes: HP", HP_FIELDS),
    ("hero_abilities.tsv", "Heroes: abilities and effects", ABILITY_FIELDS),
    ("enemies_hp.tsv", "Enemies: HP", HP_FIELDS),
    ("enemy_abilities.tsv", "Enemies: abilities and effects", ABILITY_FIELDS),
]
TRAIT_MEANINGS = {
    "big_windup": "Marks an adjacent opponent's tile; smashes the marked tile next turn if occupied.",
    "death_blast": "On defeat, damages damageable occupants in range, including allies.",
    "retaliate": "After a hit, a surviving defender retaliates against a living attacker in range.",
    "adjacent_damage_bonus": "Adds attack damage to the specified adjacent ally.",
    "adjacent_guard": "Reduces damage to the specified adjacent ally.",
    "ally_death_bonus": "Conditional bonus scales with specified fallen allies.",
    "health_damage_bonus": "Conditional attack damage bonus depends on the actor's health.",
    "death_heal": "On defeat, heals living wounded allies up to their missing HP.",
    "last_damager_pursuit": "Can pursue the most recent attacker.",
    "borrowed_armor": "Uses a borrowed armor interaction; inspect the mission rules for conditions.",
}
INTERPRETED = {"attack": ("damage", "base attack damage"),
               "blast": ("damage", "base blast damage"),
               "bonk": ("damage", "base bonk damage"),
               "heal": ("amount", "healing amount"),
               "enemy_heal": ("amount", "healing amount")}
SIMPLE_EFFECTS = {
    "move": "Moves to a legal destination.",
    "hook": "Pulls a target toward the actor if movement is legal; does not apply pull recoil.",
    "misdirect": "Marks the target to redirect its next attack under the status conditions.",
    "summon": "Summons the configured character at a legal position; corpse summons depend on a suitable corpse.",
    "swap_furthest": "Swaps positions with a legal target.",
    "swap_ally": "Swaps positions with a legal ally.",
    "shield_wall": "Places a shield wall at a legal position.",
    "fit": "Fits an eligible ally's ability; the fitted form has separate effects.",
    "quick_release": "Releases a fitting and moves to a legal cell.",
    "nominate": "Nominates a target for the summoner's minion.",
    "repel": "Moves a target away if forced movement is allowed.",
    "stop_target": "Applies a movement-blocking status to the target.",
    "repeat_batch": "Repeats a stored alchemy dose and reaction when available.",
}


def compact(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def hp_row(actor_id, profile, context="default", mission="", placement="",
           maximum=None, starting=None, notes=""):
    default = profile["max_hp"]
    maximum = default if maximum is None else maximum
    starting = maximum if starting is None else starting
    return {"actor_id": actor_id, "actor": profile.get("label", actor_id), "context": context,
            "mission": mission, "placement": placement, "default_max_hp": default,
            "maximum_hp": maximum, "starting_hp": starting, "notes": notes}


def hp_tables(defs, profiles):
    tables = {"heroes": [], "enemies": []}
    for actor, profile in sorted(profiles.items()):
        team = profile.get("team")
        if team not in tables:
            continue
        note = ""
        if actor == "zombie":
            note = "Raised from a corpse: starting HP is half the corpse's maximum HP, rounded up; default shown separately."
        tables[team].append(hp_row(actor, profile, notes=note))
    for mission_id, mission in sorted(defs.get("missions", {}).items()):
        encounter = defs.get("encounters", {}).get(mission.get("encounter"), {})
        objective = mission.get("objective", {})
        reserve_ids = objective.get("reserve_placements", []) if objective.get("handler") == "survive" else []
        for placement in encounter.get("placements", []):
            actor = placement.get("character")
            if actor not in profiles or profiles[actor].get("team") not in tables:
                continue
            profile = profiles[actor]
            overrides = mission.get("enemy_max_hp", {})
            explicit_max = placement["id"] in overrides
            explicit_start = "hp" in placement
            maximum = overrides.get(placement["id"], profile["max_hp"])
            starting = placement.get("hp", maximum)
            reserve = placement["id"] in reserve_ids
            if not explicit_max and not explicit_start and not reserve:
                continue
            notes = []
            if explicit_max:
                notes.append("Explicit mission maximum HP override.")
            if explicit_start:
                notes.append("Explicit placement starting HP.")
            if reserve:
                notes.append("Reserve: enters later, when the placement is clear; configured round "
                             + str(objective.get("reserve_round", "unknown")))
            if starting == 0:
                notes.append("Starts at zero HP (corpse).")
            tables[profile["team"]].append(hp_row(actor, profile, "placement", mission_id,
                                                   placement["id"], maximum, starting, " ".join(notes)))
    return tables


def referenced_abilities(profile, defs, actor):
    refs = {}

    def add(ability, availability):
        if ability:
            refs.setdefault(ability, set()).add(availability)

    for ability in profile.get("abilities", []):
        add(ability, "profile")
    guild = defs.get("guild_progression", {})
    for ability in guild.get("kits", {}).get(actor, {}).values():
        add(ability, "starting guild kit")
    for petition_id, petition in guild.get("petitions", {}).items():
        grant = petition.get("grant", {})
        if grant.get("kind") == "ability" and grant.get("hero_id") == actor:
            add(grant.get("ability_id"), "permanent petition " + petition_id)
    behavior_id = profile.get("behavior")
    behavior = defs.get("behaviors", {}).get(behavior_id, {})
    for key in ("ability", "heal_ability", "move_ability", "swap_ability", "wall_ability"):
        add(behavior.get("params", {}).get(key), "behavior " + str(behavior_id))
    return refs


def describe_status(status_id, defs):
    spec = defs.get("statuses", {}).get(status_id)
    if not isinstance(spec, dict):
        return f"Status {status_id}: unknown definition."
    handler, params = spec.get("handler"), spec.get("params", {})
    if handler == "reflect":
        reach = params.get("range")
        cap = params.get("max_reflect_damage_per_round")
        coverage = f"range {reach}" if reach is not None else "range unspecified"
        limit = f"up to {cap} damage per round" if cap is not None and cap >= 0 else "uncapped per round"
        return f"Reflect aura covers {coverage}; redirects or absorbs {limit}, with overflow reaching the ward."
    if handler == "skip_action":
        return f"Applies {status_id}, which can cause the target to skip an action."
    return f"Applies status {status_id} (handler {handler or 'unknown'}); inspect status rules."


def describe_effect(ability_id, ability, defs):
    handler, params = ability.get("handler", "unknown"), ability.get("params", {})
    if ability_id == "wizard_through_shot" and "damage" in params:
        return (f"Base blast damage: {params['damage']} to the primary target. If aligned in a row or column, "
                "the first eligible target behind it within range takes 1 damage, before mitigation.")
    if ability_id == "blacksmith_sweep" and "damage" in params:
        return (f"Base damage: {params['damage']} to the primary target and one other eligible adjacent "
                "target if present, before mitigation.")
    if handler in INTERPRETED:
        key, label = INTERPRETED[handler]
        effect = (f"{label}: {params[key]} (before conditions and mitigation)."
                  if key in params else "Amount not explicitly specified; inspect handler.")
        if params.get("spear_followthrough"):
            effect += (" On an adjacent hit, damageable objects directly behind the target also receive "
                       "the attack, before mitigation.")
        return effect
    if handler == "sweep":
        return "Not interpreted; inspect sweep handler."
    if handler == "acid":
        if params.get("shared_reaction"):
            return "Shares an acid reaction with the target and adjacent living characters; no guaranteed base damage."
        return (f"Base acid damage {params['damage']} to an eligible target, plus a separate reaction; "
                "outcome and mitigation can change HP lost." if "damage" in params
                else "Acid damage unspecified; inspect handler.")
    if handler == "healing_potion":
        return (f"Base healing {params['amount']} to an eligible target, plus a separate reaction; "
                "actual healing is limited by missing HP and conditions." if "amount" in params
                else "Potion healing unspecified; inspect handler.")
    if handler == "plain_tonic":
        return (f"Base healing {params['amount']} to an eligible target without an ordinary alchemy reaction; "
                "actual healing is limited by missing HP and conditions." if "amount" in params
                else "Tonic healing unspecified; inspect handler.")
    if handler == "padding":
        return (f"Grants a {params['amount']}-point buffer that absorbs damage."
                if "amount" in params else "Padding buffer unspecified; inspect handler.")
    if handler == "apply_status":
        return describe_status(params.get("status", "unknown"), defs)
    if handler == "push":
        return (f"Pushes a target if the destination is open; otherwise deals {params['collision_damage']} "
                "base collision damage to a damageable target." if "collision_damage" in params
                else "Pushes a target if possible; collision damage unspecified.")
    if handler == "pull":
        status = f" and status {params['status']}" if params.get("status") else ""
        return (f"Pulls a target and recoils; the actor takes {params['recoil_damage']} base recoil damage{status} "
                "when the normal pull resolves. Forced movement resistance can cancel it; destinations can be blocked or reversed."
                if "recoil_damage" in params else "Pulls a target with recoil; recoil damage unspecified.")
    if handler == "perform":
        if "status" in params:
            return "With an eligible listener: " + describe_status(params["status"], defs)
        source = params.get("damage_ability")
        reference = defs.get("abilities", {}).get(source, {}).get("params", {}) if source else {}
        damage = reference.get("damage") if "damage" in reference else params.get("damage")
        if damage is None:
            return "Performance effect unspecified; inspect handler and referenced ability."
        origin = f" (from {source})" if "damage" in reference else ""
        return f"With an eligible listener, deals {damage} base damage{origin}; no listener means no hit."
    return SIMPLE_EFFECTS.get(handler, "Not interpreted; inspect handler.")


def describe_trait(trait):
    kind = trait.get("kind", "unknown")
    text = TRAIT_MEANINGS.get(kind, "Unknown trait semantics; inspect rules.")
    labels = {"damage": "damage", "range": "range", "reduction": "damage reduction",
              "max_reduction": "maximum reduction", "movement": "movement bonus",
              "amount": "healing", "condition": "health condition",
              "protects": "protected character", "benefits": "benefiting character",
              "allies": "counted ally characters"}
    values = [f"{label}: {compact(trait[key])}" for key, label in labels.items() if key in trait]
    return text + (" " + "; ".join(values) + "." if values else "")


def ability_row(actor, profile, ability_id, availability, defs):
    ability = defs.get("abilities", {}).get(ability_id)
    if not isinstance(ability, dict):
        return {"actor_id": actor, "actor": profile.get("label", actor), "effect_id": ability_id,
                "effect": ability_id, "availability": "; ".join(sorted(availability)),
                "handler": "unknown", "base_effect": "Unknown: missing ability definition",
                "conditions_and_data": ""}
    handler = ability.get("handler", "unknown")
    params = ability.get("params", {})
    effect = describe_effect(ability_id, ability, defs)
    if "range" in ability.get("targeting", {}):
        effect += f" Configured targeting range: {ability['targeting']['range']}."
    details = {"parameters": params, "targeting": {
        k: v for k, v in ability.get("targeting", {}).items() if k not in ("help", "direct")
    }}
    if ability.get("fitted_form"):
        details["fitted_form"] = ability["fitted_form"]
    status = params.get("status")
    if status:
        spec = defs.get("statuses", {}).get(status)
        if isinstance(spec, dict):
            details["status"] = {"id": status, "handler": spec.get("handler"),
                                 "params": spec.get("params", {})}
        else:
            details["status"] = {"id": status, "definition": "unknown"}
    return {"actor_id": actor, "actor": profile.get("label", actor), "effect_id": ability_id,
            "effect": ability.get("label", ability_id), "availability": "; ".join(sorted(availability)),
            "handler": handler, "base_effect": effect, "conditions_and_data": compact(details)}


def ability_tables(defs, profiles):
    tables = {"heroes": [], "enemies": []}
    for actor, profile in sorted(profiles.items()):
        team = profile.get("team")
        if team not in tables:
            continue
        rows = tables[team]
        for ability, availability in sorted(referenced_abilities(profile, defs, actor).items()):
            rows.append(ability_row(actor, profile, ability, availability, defs))
        for index, trait in enumerate(profile.get("traits", [])):
            kind = trait.get("kind", "unknown")
            meaning = describe_trait(trait)
            rows.append({"actor_id": actor, "actor": profile.get("label", actor),
                         "effect_id": f"trait:{kind}:{index}", "effect": kind,
                         "availability": "profile trait", "handler": kind,
                         "base_effect": meaning, "conditions_and_data": compact(trait)})
        for petition_id, petition in sorted(defs.get("guild_progression", {}).get("petitions", {}).items()):
            grant = petition.get("grant", {})
            if grant.get("kind") == "effect" and grant.get("hero_id") == actor:
                rows.append({"actor_id": actor, "actor": profile.get("label", actor),
                             "effect_id": "guild_effect:" + str(grant.get("effect_id", "unknown")),
                             "effect": petition.get("label", petition_id),
                             "availability": "permanent petition " + petition_id,
                             "handler": "guild effect", "base_effect": "Not interpreted; inspect rules",
                             "conditions_and_data": compact(grant)})
    return tables


def page(tables):
    sections = []
    for filename, title, fields in TABLES:
        header = "".join("<th scope=\"col\">" + html.escape(field) + "</th>" for field in fields)
        rows = "".join("<tr>" + "".join("<td>" + html.escape(str(row[field])) + "</td>"
                                        for field in fields) + "</tr>" for row in tables[filename])
        sections.append(f'<section><h2>{html.escape(title)}</h2><p><a href="{filename}">TSV</a></p>'
                        f'<div class="scroll"><table><thead><tr>{header}</tr></thead>'
                        f'<tbody>{rows}</tbody></table></div></section>')
    return """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Combat facts</title><style>
body { font-family: system-ui, sans-serif; color: #202a32; background: #f5f6f5; margin: 1.5rem; }
main { max-width: 100rem; margin: auto; } p { max-width: 85ch; line-height: 1.5; }
section { margin-top: 2rem; } .scroll { overflow-x: auto; background: white; }
table { border-collapse: collapse; font-size: .88rem; width: 100%; }
th, td { border: 1px solid #aab6bb; padding: .5rem; text-align: left; vertical-align: top; }
th { background: #e7edef; } td { overflow-wrap: anywhere; }
</style></head><body><main><h1>Combat facts</h1>
<p>Values are configured base facts, not guaranteed final damage or a balance judgment.
Conditions and raw parameters are retained where interpretation is incomplete. HP placement
rows are contextual; a reserve is not present at battle start.</p>""" + "".join(sections) + "</main></body></html>\n"


def export_catalog(output):
    godot = shutil.which("godot")
    if not godot:
        raise ValueError("godot executable not found on PATH")
    command = [godot, "--headless", "--path", str(PROJECT), "--script",
               "res://tools/combat_balance/export_catalog.gd", "--",
               f"--out={output / 'export.json'}"]
    with tempfile.TemporaryDirectory(prefix="olr-combat-xdg-") as temp:
        env = os.environ.copy()
        for name, subdir in (("XDG_CONFIG_HOME", "config"), ("XDG_DATA_HOME", "data"),
                             ("XDG_CACHE_HOME", "cache")):
            env[name] = str(Path(temp) / subdir)
        with (output / "run.log").open("x", encoding="utf-8") as log:
            log.write("Command: " + compact(command) + "\n")
            log.flush()
            result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            raise ValueError(f"exporter exited {result.returncode}; see {output / 'run.log'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, help="existing structured Catalog export")
    parser.add_argument("--out", required=True, type=Path, help="new output directory")
    args = parser.parse_args()
    try:
        output = args.out.parent.resolve(strict=True) / args.out.name
        output.mkdir()
        if args.input:
            source = args.input.resolve(strict=True)
        else:
            export_catalog(output)
            source = output / "export.json"
        with source.open(encoding="utf-8") as stream:
            data = json.load(stream)
        defs, profiles = data["definitions"], data["profiles"]
        hp, abilities = hp_tables(defs, profiles), ability_tables(defs, profiles)
        tables = {"heroes_hp.tsv": hp["heroes"], "enemies_hp.tsv": hp["enemies"],
                  "hero_abilities.tsv": abilities["heroes"], "enemy_abilities.tsv": abilities["enemies"]}
        for filename, _, fields in TABLES:
            with (output / filename).open("x", encoding="utf-8", newline="") as stream:
                writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
                writer.writeheader()
                writer.writerows(tables[filename])
        (output / "index.html").write_text(page(tables), encoding="utf-8")
        print(f"Wrote combat tables to {output}")
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"report: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
