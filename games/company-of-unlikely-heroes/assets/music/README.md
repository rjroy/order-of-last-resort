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

The user supplied six additional MP3s in `~/Downloads/game/`. All were copied unchanged. The incoming `destination2.mp3` has different audio from the existing track, so its copy is named `destination2-download.mp3` to keep both in rotation. No additional licensing information was supplied.

| Path relative to this directory | Duration (s) | SHA-256 |
| --- | ---: | --- |
| `main/main-theme2.mp3` | 228.400000 | `5ae3e8af261f6e1f34b90fae5fa8df50fe601cf7be833abfb55354ab6d1e951b` |
| `main/main-theme3.mp3` | 248.840000 | `7ce4abd6782dfe589a9227475b90adf5659328ca32de3d5e6c570688189f5d83` |
| `road/road-mission2.mp3` | 359.760000 | `a36fa055014fbd10062e96ca9fecbaa9ff56b89d1eb8db5061965fc7ce19863b` |
| `road/road-mission3.mp3` | 359.560000 | `4b4a95810c5c10f246b29c0eb39760bc8f70f1c3231dd3cc86f68bc4ff170c6a` |
| `destination/destination2-download.mp3` | 360.040000 | `163e10e868faac4d0f365dbddef5cbeaf93fe71a8b27bef9fe0b6454d218bfa0` |
| `destination/destination3.mp3` | 359.720000 | `7941e762ba8ffea84793efda6e45c7d6891d69be2934f6d110edd66b203076e9` |

## Add a track

The game discovers imported MP3s directly inside the three folders at startup. Place a track in the appropriate folder and import it. No playlist manifest or code change is needed.

1. Place the original MP3 directly in `main/`, `road/`, or `destination/`, not in a nested folder. Record its source, any known permissions, and its SHA-256 and duration. Use `sha256sum` and `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 TRACK.mp3` to check the bytes and duration before and after moving it.
2. Import with Godot 4.7. From the repository root, run `godot --headless --editor --path games/company-of-unlikely-heroes --import`. Keep the MP3 import option **Loop** off (`loop=false`) so `AudioStreamPlayer.finished` can fire at the natural end. Leave beat and loop-offset settings at their defaults for these tracks.
3. Keep the MP3 and its generated `.mp3.import` sidecar together in source control. Do not commit the generated `.godot/` cache.

Durations were measured with FFprobe 9.0.2. In an isolated Godot 4.7.2 project using the same resource paths, a cache-free reimport left the sidecars unchanged. Each imported stream retained the original MP3 bytes and signaled `finished` at the natural end with looping disabled.
