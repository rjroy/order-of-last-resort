# Working on Barnaby's Order of Last Resort

Read the [game guide](games/company-of-unlikely-heroes/README.md) and relevant
game records under `.lore/work/games/company-of-unlikely-heroes/` before
changing the game. This is a standalone extraction of the Mind Garage game.
Preserve the existing paths: asset recipes and regression tools depend on them.

- Keep accepted artwork, native models, recipes and their provenance in source
  control. Place generated captures, logs and temporary evidence in ignored
  `.lore/local/`, never as a required runtime input.
- Commit Godot-generated `.uid` sidecars alongside their source files, including
  test scripts. Move or rename the sidecar with its source so the resource keeps
  its ID. After adding scripts or shaders, run a headless editor import and
  check `git status` for new sidecars. Do not commit the `.godot/` import cache.
- Verify gameplay changes with reproducible checks and retain relevant tests.
  Automated checks do not establish human enjoyment.
- Preserve experiment records, claims, approvals and human contributions.
  Player feedback is evidence from Ronald, not a representative sample.
- To add a recruitable hero, start with [Adding a playable class](docs/adding-a-playable-class.md).
  Follow it from class design through recruitment, combat, art, sound and
  verification in the running game. The [model-a-class skill](.agents/skills/model-a-class/SKILL.md)
  covers the model phase only; concept, model and runtime integration approvals
  are separate.
- Use the retained discovery and mechanic skills for new mechanics. Shared
  research under `.lore/work/shared/` is context, not authorization to build.
- Do not overwrite accepted originals or treat disposable captures as source.
  Record how to reproduce evidence and distinguish design proposals from work
  the user has approved.

The historical records may mention Mind Garage issue IDs and old source commit
IDs. They are provenance, not a live issue tracker in this repository. See
[MIGRATION.md](MIGRATION.md).
