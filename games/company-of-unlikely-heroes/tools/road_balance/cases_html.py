#!/usr/bin/env python3
"""Render a road scorecard TSV as a self-contained, sortable HTML table."""

import argparse
import csv
import html
from pathlib import Path
import sys


COLUMNS = [
    ("mission", "Mission", False), ("variant", "Variant", False),
    ("roster", "Roster", False), ("policy", "Policy", False),
    ("wounded", "Wounded start", False), ("result", "Outcome", False),
    ("rounds", "Rounds", True), ("damage_dealt", "Enemy HP lost", True),
    ("damage_received", "Hero HP lost", True),
    ("starting_wounds", "Starting wounds", True),
    ("ending_wounds", "Ending wounds", True), ("fallen", "Fallen", False),
    ("tier", "Tier", True),
]
DETAILS = [("opening_hp", "Opening HP / maximum"), ("ending_hp", "Ending HP"),
           ("ending_kind", "Ending HP meaning"), ("setup", "Opening setup and settings")]


def escape(value):
    return html.escape(str(value), quote=True)


def render(source):
    reader = csv.DictReader(source, delimiter="\t", restkey=None, restval=None)
    fields = reader.fieldnames
    required = [name for name, _, _ in COLUMNS if name != "tier"] + [name for name, _ in DETAILS]
    if not fields or len(set(fields)) != len(fields) or not set(required) <= set(fields):
        raise ValueError("TSV has missing or duplicate scorecard columns")
    extra = [(name, name) for name in fields if name not in required and name != "tier"]
    headers = "".join(
        f'<th scope="col" aria-sort="none"><button type="button" '
        f'data-column="{index}" data-numeric="{str(numeric).lower()}">{escape(label)}</button></th>'
        for index, (_, label, numeric) in enumerate(COLUMNS)
    )
    rows = []
    for row in reader:
        if None in row or any(value is None for value in row.values()):
            raise ValueError(f"malformed TSV row at line {reader.line_num}")
        cells = "".join(f"<td>{escape(row.get(name, ''))}</td>" for name, _, _ in COLUMNS)
        detail = "".join(f"<dt>{escape(label)}</dt><dd><pre>{escape(row[name])}</pre></dd>"
                         for name, label in DETAILS + extra)
        detail_id = f"case-details-{len(rows)}"
        rows.append(f'<tr>{cells}<td><details><summary aria-controls="{detail_id}">'
                    f'View</summary></details></td></tr><tr class="detail-row" '
                    f'id="{detail_id}"><td colspan="{len(COLUMNS) + 1}">'
                    f'<dl>{detail}</dl></td></tr>')
    count = len(rows)
    return PAGE.replace("<!-- HEADERS -->", headers).replace("<!-- ROWS -->", "".join(rows)).replace(
        "<!-- COUNT -->", str(count))


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Road playtest cases</title>
<style>
:root { color-scheme: light; font-family: system-ui, sans-serif; color: #202a32; background: #f5f6f5; }
body { margin: 0; padding: 1.5rem; }
main { max-width: 100rem; margin: auto; }
h1 { font-size: 1.6rem; margin: 0 0 .4rem; }
p { max-width: 80ch; line-height: 1.45; }
.controls { display: flex; flex-wrap: wrap; align-items: end; gap: 1rem; margin: 1.5rem 0 .8rem; }
label { display: grid; gap: .35rem; font-weight: 600; }
input { font: inherit; padding: .5rem; width: min(25rem, 75vw); border: 1px solid #56636b; border-radius: .25rem; }
button, summary { cursor: pointer; }
:focus-visible { outline: 3px solid #12648a; outline-offset: 2px; }
.table-wrap { overflow-x: auto; border: 1px solid #9aa6ac; background: white; }
table { border-collapse: collapse; font-size: .88rem; width: 100%; font-variant-numeric: tabular-nums; }
th, td { text-align: left; vertical-align: top; padding: .5rem .6rem; border-bottom: 1px solid #d4dcdf; }
th { background: #e7edef; white-space: nowrap; }
th button { border: 0; padding: 0; background: transparent; color: inherit; font: inherit; font-weight: 700; text-align: left; text-decoration: underline; text-underline-offset: .2em; }
th[aria-sort="ascending"] button::after { content: " ↑"; }
th[aria-sort="descending"] button::after { content: " ↓"; }
tr[hidden], [hidden] { display: none; }
td { overflow-wrap: anywhere; }
details { min-width: 4rem; }
.detail-row dl { position: sticky; left: .6rem; width: min(42rem, calc(100vw - 5rem)); margin: 0; }
dt { font-weight: 700; margin-top: .6rem; }
dd { margin: .2rem 0; }
pre { white-space: pre-wrap; overflow-wrap: anywhere; margin: 0; }
.hint { color: #3c505a; }
</style>
</head>
<body>
<main>
<h1>Road playtest cases</h1>
<p>Search for one or more terms, or select a column heading to sort. Open a row's details for setup and per-hero HP.</p>
<p class="hint">Enemy and hero HP lost are counted by recipient, including friendly fire, excluding objects and civilians.
Ending wounds use projected carryover on victory and terminal HP otherwise. Round limits are inconclusive.
Tier is configured, not inferred; blank means unassigned or unavailable in an older report.</p>
<div class="controls">
<label for="search">Search cases <input id="search" type="search" placeholder="Mission, roster, policy, outcome…" autocomplete="off"></label>
<span id="count" role="status" aria-live="polite"><!-- COUNT --> cases</span>
</div>
<p id="empty" hidden>No cases match. Change or clear the search.</p>
<noscript><p>Search and sorting require JavaScript. All cases are shown below.</p></noscript>
<div class="table-wrap"><table>
<thead><tr><!-- HEADERS --><th scope="col">Details</th></tr></thead>
<tbody><!-- ROWS --></tbody>
</table></div>
</main>
<script>
(() => {
  const body = document.querySelector("tbody");
  const rows = Array.from(body.querySelectorAll("tr:not(.detail-row)"));
  const details = new Map(rows.map(row => [row, row.nextElementSibling]));
  rows.forEach(row => {
    const disclosure = row.querySelector("details");
    const detail = details.get(row);
    detail.hidden = true;
    disclosure.addEventListener("toggle", () => { detail.hidden = row.hidden || !disclosure.open; });
  });
  const search = document.getElementById("search");
  const count = document.getElementById("count");
  const empty = document.getElementById("empty");
  const headers = Array.from(document.querySelectorAll("th[aria-sort]"));
  function filter() {
    const terms = search.value.toLocaleLowerCase().trim().split(/\\s+/).filter(Boolean);
    let visible = 0;
    for (const row of rows) {
      const text = (row.textContent + " " + details.get(row).textContent).toLocaleLowerCase();
      row.hidden = !terms.every(term => text.includes(term));
      details.get(row).hidden = row.hidden || !row.querySelector("details").open;
      if (!row.hidden) visible++;
    }
    count.textContent = `${visible} of ${rows.length} cases`;
    empty.hidden = visible !== 0;
  }
  search.addEventListener("input", filter);
  headers.forEach(header => header.querySelector("button").addEventListener("click", event => {
    const column = Number(event.currentTarget.dataset.column);
    const numeric = event.currentTarget.dataset.numeric === "true";
    const ascending = header.getAttribute("aria-sort") !== "ascending";
    headers.forEach(item => item.setAttribute("aria-sort", "none"));
    header.setAttribute("aria-sort", ascending ? "ascending" : "descending");
    rows.sort((a, b) => {
      const left = a.cells[column].textContent.trim();
      const right = b.cells[column].textContent.trim();
      if (numeric && (!left || !right) && left !== right) return left ? -1 : 1;
      const comparison = numeric && left !== "" && right !== "" && Number.isFinite(Number(left)) && Number.isFinite(Number(right))
        ? Number(left) - Number(right) : left.localeCompare(right, undefined, {numeric: true, sensitivity: "base"});
      return ascending ? comparison : -comparison;
    });
    rows.forEach(row => { body.appendChild(row); body.appendChild(details.get(row)); });
  }));
})();
</script>
</body>
</html>
"""


def write_html(tsv, output):
    with tsv.open(encoding="utf-8", newline="") as source:
        page = render(source)
    with output.open("x", encoding="utf-8") as destination:
        destination.write(page)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tsv", type=Path)
    parser.add_argument("--out", type=Path, required=True, help="new HTML file")
    args = parser.parse_args()
    try:
        write_html(args.tsv, args.out)
    except (OSError, ValueError, csv.Error) as error:
        print(f"cases_html: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
