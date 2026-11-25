# Music assets

## Playback contexts

| Folder | When it plays |
| --- | --- |
| `main/` | Guild screens, including recruitment and the first field reports before battle. |
| `road/` | Nonfinal commission battles, the practice lesson, and standalone battles. |
| `destination/` | The final battle at a commission's named destination. |

Between commission battles, field reports and debriefs keep the preceding battle's music. Results also keep that music until you return to the guild. Staying in the same context does not restart the current track.

Each folder has its own shuffled playlist. The playlist draws every track once per shuffle, and the first draw of a new shuffle cannot repeat the last draw if there is another choice. A folder with only one track repeats it after it finishes.

## Track provenance

These four MP3s were supplied by the user at the repository root. They were moved here unchanged, keeping their original filenames. This record does not establish authorship, licensing, or redistribution rights.

| Path relative to this directory | Duration (s) | SHA-256 |
| --- | ---: | --- |
| `main/main-theme.mp3` | 359.920000 | `8371bf6b4392ea290013c3e9269d226fdb0233b8a697083a9c671e8a2e4e7187` |
| `road/road-mission.mp3` | 359.600000 | `4b4139fd2871210c7936fb1e48d84a41e6fcf2b3b255e46186c13f9d7b908c6c` |
| `destination/destination.mp3` | 359.560000 | `e17d72d026a916d51b9e1e2962f2ef19e2be1eaf9250542ff43e6b103cd087e3` |
| `destination/destination2.mp3` | 359.600000 | `5876181ae2e4451810e9938874f5eaff4fe612647bdeeadc3065cc1bfaf45f0f` |

## Add a track

The game discovers imported MP3s directly inside the three folders at startup. Place a track in the appropriate folder and import it. No playlist manifest or code change is needed.

1. Place the original MP3 directly in `main/`, `road/`, or `destination/`, not in a nested folder. Record its source, any known permissions, and its SHA-256 and duration. Use `sha256sum` and `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 TRACK.mp3` to check the bytes and duration before and after moving it.
2. Import with Godot 4.7. From the repository root, run `godot --headless --editor --path games/company-of-unlikely-heroes --import`. Keep the MP3 import option **Loop** off (`loop=false`) so `AudioStreamPlayer.finished` can fire at the natural end. Leave beat and loop-offset settings at their defaults for these tracks.
3. Keep the MP3 and its generated `.mp3.import` sidecar together in source control. Do not commit the generated `.godot/` cache.

Durations were measured with FFprobe 9.0.2. In an isolated Godot 4.7.2 project using the same resource paths, a cache-free reimport left the sidecars unchanged. Each imported stream retained the original MP3 bytes and signaled `finished` at the natural end with looping disabled.
