#!/usr/bin/env python3
"""Build a local comparison page from complete capture runs and approved plates."""

import argparse
import hashlib
import html
import os
from pathlib import Path
import struct
import sys
from urllib.parse import quote
import zlib


ROOT = Path(__file__).resolve().parents[3]
LOCAL = ROOT / ".lore/local"
CONCEPTS = ROOT / ".lore/work/games/company-of-unlikely-heroes/art/concepts/release-polish"

# A state may appear under more than one bead when it informs both screens.
PAGES = (
    ("14", "Commission board", "14-commission-board.png",
     "e3a09c7ad27f760d8e5457fef1abba5c89399cd930c6a2d4634e4105d2d493f7", (
         ("Commission board", "ordinary/02-commissions.png"),
         ("Long guild name", "gaps/05-long-name-commissions.png"),
         ("Return after defeat", "ordinary/09-return-after-defeat.png"),
         ("Return after victory", "ordinary/14-return-after-victory.png"))),
    ("15", "Guild creation", "15-guild-creation.png",
     "70291b3641dae7e2b17f0e2a24c8fc50f880d26804fa8cde6605bd1468301ec9", (
         ("Initial form", "ordinary/01-guild-creation.png"),
         ("Empty name", "gaps/03-empty-name.png"),
         ("Long name", "gaps/04-long-name.png"))),
    ("16", "Recruitment and deployment", "16-recruitment-deployment.png",
     "fb59c4189b70aa0e8d24bdba8c0cf401a513c904e690f4fb5c1de055a8f93b22", (
         ("Commission selected", "ordinary/03-commission-selected.png"),
         ("Empty recruitment", "gaps/06-empty-recruitment.png"),
         ("Full recruitment", "gaps/07-full-recruitment.png"),
         ("Reordered deployment", "ordinary/05-deployment-reordered.png"),
         ("Recruitment return", "ordinary/04-recruitment.png"),
         ("Seeded commission selected", "ordinary/10-commission-selected.png"))),
    ("17", "Field reports and route choice", "17-field-reports.png",
     "bf44e9d95e8ad78827462266da628a12839c4844431251d7a599611e5d97c55a", (
         ("Field reports", "ordinary/06-field-reports.png"),)),
    ("18", "Battle and controls", "18-battle-controls.png",
     "e1a416812d8717b31b565c0fb09e90235d6b387ec507f2f38e2f8a02dc3277f9", (
         ("Battle entry", "ordinary/07-battle-entry.png"),
         ("Move targeting", "gaps/08-targeting.png"),
         ("Move forecast", "gaps/09-forecast.png"),
         ("Committed resolution", "gaps/10-resolution.png"))),
    ("19", "Mission debrief and rewards", "19-mission-debrief-rewards.png",
     "0142c4cca15e2e47abfcde3f027bf80f5acb0609a02ec8d567ef08e1cd7c4a36", (
         ("Reward choices", "ordinary/11-debrief-reward-choices.png"),
         ("Reward selected, road 1", "ordinary/12-reward-selected-0.png"),
         ("Reward selected, road 2", "ordinary/12-reward-selected-1.png"),
         ("Reward selected, road 3", "ordinary/12-reward-selected-2.png"),
         ("Reward selected, road 4", "ordinary/12-reward-selected-3.png"))),
    ("20", "Run result and return", "20-run-result-return.png",
     "1d4ce06bcf43ef3d4e477f368f95104c3012a5cb95d7acf96b99de2ce8a60b30", (
         ("Played victory", "ordinary/13-played-victory.png"),
         ("Controlled defeat (party HP set to zero)", "ordinary/08-controlled-defeat.png"),
         ("Forfeit result", "gaps/12-forfeit-result.png"),
         ("Return after defeat", "ordinary/09-return-after-defeat.png"),
         ("Return after victory", "ordinary/14-return-after-victory.png"))),
    ("21", "Forfeit confirmation", "21-forfeit-confirmation.png",
     "b84605ff8708a7d84436eddc0f0284ba377c8b801c4715197e68533938f6c66d", (
         ("Confirmation", "gaps/11-forfeit-confirmation.png"),
         ("Forfeit result", "gaps/12-forfeit-result.png"))),
    ("22", "Guild-profile recovery", "22-guild-profile-recovery.png",
     "8350904be7991095b9b26efa56185720a67b290d581b363fcfce9d0af98310f2", (
         ("Corrupt profile recovery", "gaps/01-profile-recovery.png"),)),
    ("23", "Launch error", "23-launch-error.png",
     "9b5f42128b4c1d96b1f7e968333ac9c30c56b95a6a4f7dcf421a1db805afa151", (
         ("Invalid mission launch", "gaps/02-invalid-launch.png"),)),
)


def check_png(path: Path) -> None:
    """Reject truncated or damaged PNG containers without external libraries."""
    with path.open("rb") as image:
        if image.read(8) != b"\x89PNG\r\n\x1a\n":
            raise ValueError("invalid PNG signature")
        first = True
        seen_data = False
        while True:
            header = image.read(8)
            if len(header) != 8:
                raise ValueError("truncated PNG chunk header")
            size, kind = struct.unpack(">I4s", header)
            # Remaining bytes bound allocation even for malformed lengths.
            remaining = path.stat().st_size - image.tell()
            if size + 4 > remaining:
                raise ValueError("truncated PNG chunk")
            data = image.read(size)
            checksum = image.read(4)
            if zlib.crc32(kind + data) != struct.unpack(">I", checksum)[0]:
                raise ValueError("bad PNG chunk checksum")
            if first and (kind != b"IHDR" or size != 13):
                raise ValueError("missing PNG header")
            first = False
            seen_data |= kind == b"IDAT"
            if kind == b"IEND":
                if size or not seen_data or image.read(1):
                    raise ValueError("invalid PNG end")
                return


def validate(before: Path, after: Path, concepts: Path) -> list[str]:
    errors = []
    for root, label in ((before, "before"), (after, "after")):
        for relative in sorted({state[1] for page in PAGES for state in page[4]}):
            path = root / relative
            try:
                check_png(path)
            except (OSError, ValueError) as exc:
                errors.append(f"{label}: cannot read {path}: {exc}")
    for _, _, filename, expected, _ in PAGES:
        path = concepts / filename
        try:
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if digest != expected:
                errors.append(f"approved concept differs from approved SHA-256: {path}")
        except OSError as exc:
            errors.append(f"approved concept: cannot read {path}: {exc}")
    return errors


def link(image: Path, output: Path, text: str) -> str:
    relative = os.path.relpath(image.resolve(), output.parent.resolve())
    url = quote(relative, safe="/")
    label = html.escape(text)
    return f'<a href="{url}"><img src="{url}" alt="{label}" width="480"></a>'


def render(before: Path, after: Path, concepts: Path, output: Path, demo: bool) -> str:
    title = "TECHNICAL DEMO — not a candidate" if demo else "Screen polish comparison"
    parts = [
        "<!doctype html>", '<html lang="en"><head><meta charset="utf-8">',
        f"<title>{html.escape(title)}</title></head><body>",
        f"<h1>{html.escape(title)}</h1>",
        "<p>Approved concepts are implementation direction, not runtime acceptance. "
        "Captures show alternate states, not simultaneous controls. "
        "Click any image for full size; inspect visually.</p>",
        "<nav><h2>Beads</h2><ul>",
    ]
    for number, title, _, _, _ in PAGES:
        parts.append(f'<li><a href="#ddd-{number}">mind-garage-ddd.{number}: {html.escape(title)}</a></li>')
    parts.append("</ul></nav>")
    for number, title, filename, _, states in PAGES:
        parts.extend((
            f'<section id="ddd-{number}"><h2>mind-garage-ddd.{number}: {html.escape(title)}</h2>',
            "<h3>Approved concept</h3>",
            link(concepts / filename, output, f"Approved concept: {title}"),
        ))
        for label, relative in states:
            parts.extend((
                f"<h3>{html.escape(label)}</h3>",
                "<h4>Before</h4>", link(before / relative, output, f"Before: {label}"),
                "<h4>After</h4>", link(after / relative, output, f"After: {label}"),
            ))
        parts.append('<p><a href="#top">Back to top</a></p></section>')
    parts.append('</body></html>\n')
    return "\n".join(parts).replace("<body>", '<body id="top">', 1)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, default=LOCAL / "release-polish/before")
    parser.add_argument("--after", type=Path, default=LOCAL / "release-polish/after")
    parser.add_argument("--concepts", type=Path, default=CONCEPTS)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--technical-demo", action="store_true",
                        help="Mark a scratch comparison as a technical demo, not a candidate")
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(LOCAL.resolve()) or output.suffix.lower() != ".html":
        parser.error("output must be an HTML file under .lore/local")
    if output.exists():
        parser.error("output already exists; choose a new filename")
    errors = validate(args.before, args.after, args.concepts)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    try:
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open("x", encoding="utf-8") as page:
            page.write(render(args.before, args.after, args.concepts, output, args.technical_demo))
    except OSError as exc:
        print(f"Cannot write review: {exc}", file=sys.stderr)
        return 1
    print(f"Wrote {'technical demo' if args.technical_demo else 'review'}: {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
