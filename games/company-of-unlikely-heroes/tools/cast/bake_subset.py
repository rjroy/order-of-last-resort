"""Stage selected registered cast atlases and a partial manifest for review."""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from bake_cast import GAME, publish


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new or empty staging directory")
    parser.add_argument("actors", nargs="+")
    parser.add_argument("--threads", type=int, default=6)
    args = parser.parse_args()
    masters = json.loads((HERE / "masters.json").read_text())
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
            subprocess.run(
                [
                    "blender", "-b", "-t", str(args.threads), "--python-exit-code", "1",
                    "-P", str(HERE / "bake_actor.py"), "--", role, str(work),
                ],
                env={**os.environ, "MAGICK_THREAD_LIMIT": "1"},
                check=True,
            )
        publish(work, dest, {role: masters[role] for role in roles})


if __name__ == "__main__":
    main()
