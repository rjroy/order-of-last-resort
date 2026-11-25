"""Stage selected registered cast atlases and a partial manifest for review."""

import argparse
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from bake_cast import GAME, publish, render_role
from recipe import load_fragment, load_registered
from takes import RELEASES, TAKES


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new or empty staging directory")
    parser.add_argument("actors", nargs="+")
    parser.add_argument("--threads", type=int, default=6)
    parser.add_argument("--recipe", type=Path, help="optional single-actor staging fragment")
    args = parser.parse_args()
    masters, takes, releases = load_registered(
        HERE / "actors", json.loads((HERE / "masters.json").read_text()), TAKES, RELEASES, args.actors
    )
    masters, takes, _ = load_fragment(args.recipe, masters, takes, releases)
    roles = dict.fromkeys(args.actors)
    unknown = roles.keys() - masters.keys()
    if unknown:
        parser.error(f"unregistered actors: {', '.join(sorted(unknown))}")
    dest = args.output.resolve()
    runtime = (GAME / "assets/cast").resolve()
    if dest == runtime or dest.is_relative_to(runtime):
        parser.error("a partial build may not write runtime assets")
    if dest.exists() and (not dest.is_dir() or any(dest.iterdir())):
        parser.error("staging directory must be empty")
    dest.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for role in roles:
            render_role(role, work, args.threads, args.recipe)
        publish(work, dest, {role: masters[role] for role in roles}, takes)


if __name__ == "__main__":
    main()
