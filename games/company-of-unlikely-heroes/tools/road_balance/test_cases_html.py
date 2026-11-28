import csv
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from cases_html import COLUMNS, DETAILS, render


class CasesHtmlTest(unittest.TestCase):
    def tsv(self, row):
        fields = [name for name, _, _ in COLUMNS] + [name for name, _ in DETAILS]
        output = io.StringIO(newline="")
        writer = csv.DictWriter(output, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        writer.writerow({name: row.get(name, "") for name in fields})
        output.seek(0)
        return output

    def test_escapes_all_cells_and_details(self):
        payload = '</td><script>alert("x")</script>&'
        page = render(self.tsv({"mission": payload, "setup": payload}))
        self.assertNotIn(payload, page)
        self.assertEqual(page.count("&lt;/td&gt;&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;&amp;"), 2)
        self.assertIn('data-numeric="true"', page)
        self.assertIn('id="search"', page)
        self.assertIn('id="empty" hidden', page)
        self.assertIn("<details>", page)
        self.assertIn('aria-controls="case-details-0"', page)
        self.assertIn('class="detail-row" id="case-details-0"', page)
        self.assertIn("1 cases", page)

    def test_bad_tsv_fails(self):
        with self.assertRaisesRegex(ValueError, "missing or duplicate"):
            render(io.StringIO("mission\none\n"))
        source = self.tsv({})
        with self.assertRaisesRegex(ValueError, "malformed"):
            render(io.StringIO(source.getvalue() + "incomplete\n"))

    def test_legacy_tsv_without_tier_is_renderable(self):
        fields = [name for name, _, _ in COLUMNS if name != "tier"] + [
            name for name, _ in DETAILS
        ]
        source = io.StringIO(newline="")
        writer = csv.DictWriter(source, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        writer.writerow({name: "legacy_mission" if name == "mission" else "" for name in fields})
        source.seek(0)
        page = render(source)
        self.assertIn("<td>legacy_mission</td>", page)

    def test_cli_preserves_existing_output(self):
        with tempfile.TemporaryDirectory(dir="/tmp/opencode") as temp:
            root = Path(temp)
            source, dest = root / "cases.tsv", root / "cases.html"
            source.write_text(self.tsv({"mission": "test"}).getvalue(), encoding="utf-8")
            dest.write_text("preserve", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(Path(__file__).with_name("cases_html.py")),
                 str(source), "--out", str(dest)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(dest.read_text(encoding="utf-8"), "preserve")


if __name__ == "__main__":
    unittest.main()
