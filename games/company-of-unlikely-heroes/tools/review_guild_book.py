#!/usr/bin/env python3
"""Make disposable, captioned review sheets from packaged guild-book art."""

import argparse
import json
import re
import subprocess
import sys
import tempfile
import textwrap
import unittest
from dataclasses import dataclass, replace
from pathlib import Path

GAME = Path(__file__).resolve().parents[1]
REPO = GAME.parents[1]
KINDS = ("classes", "destinations", "reports", "upgrades")
# These original report illustrations are accepted assets, not optional art
# for later additions to the catalog.
ORIGINAL_REPORTS = frozenset({
    "bridge_is_out", "bridge_patrol", "company_rescue", "cowardly_captain",
    "dont_wake_the_giant", "duelists", "explosive_situation", "goblin_mob",
    "great_sheep_escape", "harpoon_squad", "hold_the_line", "last_one_standing",
    "last_wagon", "mirror_company", "odd_couple", "shield_wall",
    "unfortunate_healer", "unfortunate_ritual", "unwelcome_guest", "wrong_side_of_the_door",
})


@dataclass(frozen=True)
class Entry:
    id: str
    name: str
    hero: str = ""
    fallback: str = ""
    required: bool = True
    image_id: str = ""


def inventory(content_dir: Path, mapping_path: Path) -> dict[str, list[Entry]]:
    catalog = json.loads((content_dir / "catalog.json").read_text())
    tables: dict[str, dict] = {}
    for part in catalog["parts"]:
        data = json.loads((content_dir / part).read_text())
        for table in ("characters", "missions", "mission_reports", "upgrades"):
            tables.setdefault(table, {}).update(data.get(table, {}))

    # Presentation includes the non-recruitable smith, which is not a character.
    mapping = mapping_path.read_text().split("const CLASS_LABELS := {", 1)[1].split("}", 1)[0]
    labels = dict(re.findall(r'"(\w+)"\s*:\s*"([^"]+)"', mapping))
    for character in tables["characters"].values():
        if "guild_portrait" in character:
            labels[character["guild_portrait"]] = character["label"]

    reports = tables["mission_reports"]
    destinations = {key for key, value in reports.items() if "destination_descriptors" in value}
    # Retain the packaged paintings made for the retired practice finales.
    # They remain reviewable even though those missions are no longer finales.
    destinations.update({"cowardly_captain", "mirror_company", "odd_couple"} & tables["missions"].keys())
    missions = tables["missions"]
    report_entries = []
    for key in sorted(reports):
        mission = missions[key]
        base = mission.get("base_mission_id", "")
        encounter = mission.get("encounter", "")
        fallback = base if encounter and encounter == missions.get(base, {}).get("encounter") else ""
        report_entries.append(Entry(key, mission["title"], fallback=fallback,
                                    required=key in ORIGINAL_REPORTS))
    return {
        "classes": [Entry(key, value) for key, value in sorted(labels.items())],
        "destinations": [Entry(key, missions[key]["title"]) for key in sorted(destinations)],
        "reports": report_entries,
        "upgrades": [
            Entry(key, value["label"], value["hero_id"])
            for key, value in sorted(tables["upgrades"].items())
        ],
    }


def coverage(entries: list[Entry], art_dir: Path) -> tuple[list[str], list[str]]:
    expected = {entry.id for entry in entries}
    required = {entry.id for entry in entries if entry.required}
    actual = {path.stem for path in art_dir.glob("*.png")}
    return sorted(required - actual), sorted(actual - expected)


def available_images(entries: list[Entry], art_dir: Path) -> tuple[list[Entry], list[str]]:
    actual = {path.stem for path in art_dir.glob("*.png")}
    present = []
    text_only = []
    for entry in entries:
        image_id = entry.id if entry.id in actual else entry.fallback
        if image_id in actual:
            present.append(replace(entry, image_id=image_id))
        elif not entry.required:
            text_only.append(entry.id)
    return present, text_only


def checked_output(raw: str, repo: Path = REPO, temp: Path | None = None) -> Path:
    output = Path(raw).expanduser().resolve()
    allowed = [(repo / ".lore" / "local").resolve(), (temp or Path(tempfile.gettempdir())).resolve()]
    if not any(output != root and output.is_relative_to(root) for root in allowed):
        raise ValueError("output must be a subdirectory of .lore/local or the system temporary directory")
    # A temporary directory may itself contain a checkout, so protect the repository
    # separately, including the input art, even if that checkout is under /tmp.
    repo = repo.resolve()
    if output.is_relative_to(repo) and not output.is_relative_to((repo / ".lore" / "local").resolve()):
        raise ValueError("output may not be inside the source tree")
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError("output directory must be empty or not exist")
    return output


def font_path() -> str:
    listing = subprocess.run(["magick", "-list", "font"], check=True, capture_output=True, text=True)
    for line in listing.stdout.splitlines():
        if line.strip().startswith("glyphs:"):
            path = Path(line.split(":", 1)[1].strip())
            if path.is_file():
                return str(path)
    raise ValueError("ImageMagick has no usable installed font")


def caption(entry: Entry, prefix: str = "") -> str:
    # Montage does not wrap labels: long IDs otherwise spill into adjacent tiles
    # or get clipped at the sheet edge.
    identifier = prefix + entry.id
    return "\n".join(textwrap.wrap(identifier, width=25) + textwrap.wrap(entry.name, width=25)).replace("%", "%%")


def render(entries: list[Entry], art: Path, output: Path, columns: int = 4) -> None:
    command = ["magick", "montage", "-font", font_path(), "-pointsize", "16",
               "-background", "#f3ead8", "-fill", "#241b16"]
    for entry in entries:
        command.extend(["-label", caption(entry),
                        str(art / f"{entry.image_id or entry.id}.png")])
    command.extend(["-geometry", "280x210+8+8", "-tile", f"{columns}x", str(output)])
    subprocess.run(command, check=True)


def write_review(output: Path, art_root: Path, items: dict[str, list[Entry]], overview: bool) -> bool:
    output.mkdir(parents=True, exist_ok=True)
    lines = ["# Guild book art review", "",
             "Packaged images only. Inclusion does not imply approval.", ""]
    complete = True
    overview_entries: list[tuple[Entry, Path]] = []
    for kind in KINDS:
        entries = items[kind]
        art = art_root / kind
        missing, extra = coverage(entries, art)
        complete &= not missing and not extra
        present, text_only = available_images(entries, art)
        lines += [f"## {kind.title()}", "",
                  f"{len(present)} of {len(entries)} entries illustrated; "
                  f"{len(extra)} unexpected PNGs.", ""]
        groups: dict[str, list[Entry]] = {}
        for entry in present:
            groups.setdefault(entry.hero if kind == "upgrades" else kind, []).append(entry)
            overview_entries.append((entry, art))
        for group, group_entries in sorted(groups.items()):
            filename = f"{kind}-{group}.png" if kind == "upgrades" else f"{kind}.png"
            render(group_entries, art, output / filename)
            lines.append(f"- [{group.title()} ({len(group_entries)})]({filename})")
        if missing:
            lines.append("- Missing: " + ", ".join(f"`{key}`" for key in missing))
        if text_only:
            lines.append("- Text only: " + ", ".join(f"`{key}`" for key in text_only))
        inherited = [f"`{entry.id}` from `{entry.image_id}`" for entry in present
                     if entry.image_id != entry.id]
        if inherited:
            lines.append("- Shared sketches: " + ", ".join(inherited))
        if extra:
            lines.append("- Unexpected: " + ", ".join(f"`{key}`" for key in extra))
        lines.append("")
    if overview and overview_entries:
        command = ["magick", "montage", "-font", font_path(), "-pointsize", "14",
                   "-background", "#f3ead8", "-fill", "#241b16"]
        for entry, art in overview_entries:
            command += ["-label", caption(entry, art.name + "/"),
                         str(art / f"{entry.image_id or entry.id}.png")]
        command += ["-geometry", "240x180+6+6", "-tile", "6x", str(output / "overview.png")]
        subprocess.run(command, check=True)
        lines[3:3] = ["[Overview sheet](overview.png)", ""]
    (output / "index.md").write_text("\n".join(lines) + "\n")
    return complete


class ToolTests(unittest.TestCase):
    def test_long_caption_wraps_without_losing_identifier(self):
        entry = Entry("necromancer_say_hello_to_that_one", "Say Hello to That One")
        lines = caption(entry).splitlines()
        self.assertEqual("".join(lines[:-1]), entry.id)
        self.assertTrue(all(len(line) <= 25 for line in lines))

    def test_inventory_and_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "catalog.json").write_text('{"parts":["data.json"]}')
            (root / "data.json").write_text(json.dumps({
                "characters": {"hero": {"guild_portrait": "hero", "label": "Hero"}},
                "missions": {"a": {"title": "A"}, "b": {"title": "B"},
                             "odd_couple": {"title": "The Odd Couple"}},
                "mission_reports": {"a": {}, "b": {"destination_descriptors": []}},
                "upgrades": {"hero_u": {"label": "Upgrade", "hero_id": "hero"}},
            }))
            mapping = root / "mapping.gd"
            mapping.write_text('const CLASS_LABELS := {"smith": "Smith"}')
            items = inventory(root, mapping)
            self.assertEqual([entry.id for entry in items["classes"]], ["hero", "smith"])
            self.assertEqual([entry.id for entry in items["destinations"]], ["b", "odd_couple"])
            self.assertEqual(len(items["reports"]), 2)
            self.assertEqual(items["upgrades"][0].hero, "hero")
            (root / "hero.png").touch()
            (root / "extra.png").touch()
            self.assertEqual(coverage(items["classes"], root), (["smith"], ["extra"]))

    def test_output_protects_source_and_existing_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "repo"
            repo.mkdir()
            self.assertEqual(checked_output(str(repo / ".lore/local/review"), repo, root),
                             repo / ".lore/local/review")
            with self.assertRaises(ValueError):
                checked_output(str(repo / "assets"), repo, root)
            (root / "occupied").mkdir()
            (root / "occupied/file").touch()
            with self.assertRaises(ValueError):
                checked_output(str(root / "occupied"), repo, root)

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", help="new or empty directory under .lore/local or the system temp directory")
    parser.add_argument("--overview", action="store_true", help="also render one large overview image")
    parser.add_argument("--self-test", action="store_true", help="run controlled tool tests")
    args = parser.parse_args()
    if args.self_test:
        return 0 if unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(ToolTests)).wasSuccessful() else 1
    if not args.output:
        parser.error("--output is required unless running --self-test")
    try:
        output = checked_output(args.output)
        items = inventory(GAME / "content", GAME / "presentation/book/guild_book_art.gd")
        complete = write_review(output, GAME / "assets/guild-book", items, args.overview)
    except (OSError, ValueError, KeyError, IndexError, subprocess.CalledProcessError) as exc:
        print(f"Review failed: {exc}", file=sys.stderr)
        return 2
    print(f"Review index: {output / 'index.md'}")
    if not complete:
        print("Coverage incomplete or unexpected PNGs found; see index.", file=sys.stderr)
    return 0 if complete else 1


if __name__ == "__main__":
    sys.exit(main())
