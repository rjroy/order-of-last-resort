# Standalone extraction

Source: Mind Garage commit `64e6289821b912f394e4eaa744ae76e0ce485a3f`
on its `master` branch. At that snapshot the game was already titled
Barnaby's Order of Last Resort; The Company of Unlikely Heroes is its earlier
title and remains in its paths.

The extraction filtered only `master`, retaining `games/company-of-unlikely-heroes/`,
`.lore/work/games/company-of-unlikely-heroes/`, `.lore/work/shared/`, the
`discover-game-hook`, `explore-mechanic` and `model-a-class` skills, `LICENSE`
and `.gitignore`. Original directory names are intentional: recipes and
scripts use those paths. The source commit is immutable: extraction did not
rewrite it. This does not describe or prohibit subsequent graduation changes
to the Mind Garage working tree or later commits.

The retained files at the filtered tip matched their source tree objects
before standalone documentation was added. History was rewritten, so original
commit IDs in historical documents are provenance identifiers, not necessarily
resolvable here. `migration-commit-map.txt` maps source commits to rewritten
commits; zero IDs identify commits discarded by the path filter. The source
tip changed only excluded content and maps to zero; the filtered tip before
standalone changes corresponds to the preceding retained source commit.

The original issue database and other games were excluded from the filtered
history. A separate tracker migration selected game issues from a live source
tracker snapshot; see [tracker migration and bootstrap](.beads/MIGRATION.md)
for its scope, ID mapping and publication status. Historical references to
other source issues and games remain as context and may not resolve here.
External creative skills named by the modeling procedure are not included;
they must be installed separately if that workflow is used.

## Fresh checkout

Clone this repository to a new directory, then follow [README.md](README.md).
Use Godot 4.7.2 and, for actor production, Blender 5.2.2 LTS and ImageMagick 7
as documented in the actor recipe. No original repository or local experiment
output should be needed. Avoid reusing Godot's import cache when checking a
fresh clone.

## Exposure audit

The pre-extraction source had 2,559 distinct reachable blobs. The filtered
history retained 1,802 and excluded 757; shared blob content is counted as
retained even if it also appeared under an excluded path. No source blob
exceeded 100 MB. The largest excluded blob was a 3,231,291-byte Borrowed
Turns storyboard. The largest retained blob was the 8,001,012-byte Zombie
Blender master. An audit of source history paths found no names containing
credential, secret, `.env`, `id_rsa`, `.pem`, token, password or private.
Additionally, 1,465 text-like retained historical blobs were scanned for
private-key headers, AWS access key IDs, GitHub tokens and OpenAI-style keys;
none matched. This is a bounded check, not proof that historical content
contains no secrets or personal information. Review all retained history
before publication.
