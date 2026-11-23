# Stock cast scene regression

From a fresh checkout and the repository root, with a graphical Godot display:

```sh
tool=games/company-of-unlikely-heroes/tools/cast/verify_stock_scenes.py
python3 "$tool" --dry-run --output "$PWD/.lore/local/stock-scenes-plan"
python3 "$tool" --output "$PWD/.lore/local/stock-scenes-NEW"
```

Choose a new output path each time. The wrapper discovers missions from the
checked-in merged stock catalog and actor/variant cases from checked-in
`tests/support/stock_cast_case_*.json`; it does not read previous experiment
history or captures. It runs the existing graphical scene driver sequentially:
one `--inventory --all-integrated` per mission, then each actor and variant.
`--dry-run` prints the exact plan and writes nothing.
These are graphical runs with Godot's `--audio-driver Dummy` because this
regression does not test audio. A real display and renderer are still required;
script and renderer errors remain failures.

The full run requires all stock actors to be integrated. For a smaller run,
repeat `--mission=<id>` and/or `--actor=<character-id>`. Inventories are still
run for every selected mission, so use an integrated mission or run the
single-actor command in `tests/stock_cast_mission_test.md` during incremental
work. Use `--godot=<executable>` if needed.

Output must be a **new** directory beneath this checkout's `.lore/local` and
must not pass through symlinks. Godot user data, cache, config, temporary files,
logs, and the original screenshot captures all remain there, not in `/tmp`.
The wrapper neither copies screenshots into another gallery nor deletes prior
evidence. It refuses to start or continue a job below 2 GiB free by default;
`--min-free-gib` changes the threshold. Individual jobs have a 120-second limit,
configurable with `--timeout`.

`summary.json` records every command, exit status, captured screenshot count and
error lines. A nonzero exit, Godot error/parse message, missing required capture,
timeout or disk stop fails the run. Review the original logs and screenshots:
passing the mechanical regression is not approval of the runtime appearance.

The wrapper does not replace asset/source verification:
`tools/cast/verify_cast.py` checks registered model hashes and bake metadata.
Run `python3 -m unittest discover -s games/company-of-unlikely-heroes/tools/cast
-p test_verify_stock_scenes.py` for controlled orchestration tests.
