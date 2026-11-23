# Tracker migration and bootstrap

This tracker contains nine open game issues and their two closed prerequisites
selected from a live, read-only Mind Garage Beads export. The associated source
code commit was `64e6289821b912f394e4eaa744ae76e0ce485a3f`; the live tracker
snapshot is not necessarily the tracker state at that commit. Original issue
text and historical references are retained. The source tracker and unrelated
issue history were not copied.

| Mind Garage ID | Standalone ID |
| --- | --- |
| mind-garage-y1v | olr-y1v |
| mind-garage-mtf | olr-mtf |
| mind-garage-egw | olr-egw |
| mind-garage-4ai | olr-4ai |
| mind-garage-ftn | olr-ftn |
| mind-garage-djp.5 | olr-djp.5 |
| mind-garage-05o | olr-05o |
| mind-garage-ddd | olr-ddd |
| mind-garage-djp | olr-djp |
| mind-garage-ojr | olr-ojr |
| mind-garage-em7 | olr-em7 |

## Fresh clone

Install Beads, clone the repository, then run `bd bootstrap --yes` from the
clone. Beads uses the origin's `refs/dolt/data` when present. Verify with
`bd --readonly count --json` and `bd --readonly show olr-05o olr-djp.5 --json`.
The imported snapshot has 11 issues; the count can change as work continues.

The native Dolt ref initially exists only in the local repository. Publishing
the Git branch alone does not publish it. Once a destination is authorized,
publish the native ref separately and verify a fresh clone bootstraps from it.
Do not overwrite an existing remote Dolt ref without reconciling its history.

`.beads/issues.jsonl` is a passive migration snapshot, not the live tracker or
a substitute for native sync. If no native ref exists, `bd bootstrap` can
import that snapshot, but subsequent issue changes will not be represented in
it unless it is explicitly exported again.
