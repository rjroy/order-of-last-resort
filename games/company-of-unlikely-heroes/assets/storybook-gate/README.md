# Accepted Storybook Gate artwork

Ronald accepted the exact combined 1280 × 820 in-engine candidate on 2026-11-21: “that's much better ... let's call that done.” The artwork is used for the `wrong_side_of_the_door` Storybook battle.

```sh
godot --path games/company-of-unlikely-heroes -- --mission=wrong_side_of_the_door
```

The five PNGs below are byte-for-byte copies of the accepted candidate layers. The frame, typography, grid, figures, graphite forecast, and controls remain live. No concept image, screenshot, local review file, or capture script is loaded by the game.

| Runtime file | Dimensions | SHA-256 |
| --- | --- | --- |
| `gate-scenery-surround-wall-rgba.png` | 1280 × 820 | `645b603963b963a51e7f10d62ec6d41c87a7b6fa1fb6ada50675c6601d2838b7` |
| `gate-open.png` | 312 × 216 | `7e1bfde2c754058423f39881fb170aced85013418070d4171b7d97bf896d79a4` |
| `gate-shut.png` | 312 × 216 | `b9926a5633c4e950faed5aa216cbabfac3019a8053bbdf06176141d30935f42d` |
| `exit-arch.png` | 228 × 165 | `8a3ee032aa2b050e5d50ac156c651d1319603d2f2e0093de7a3680bd1e4165cc` |
| `pressure-plate.png` | 240 × 102 | `4da509a1ee9294ec515de3ce5bc91bbee0757f3379fc51304af3133bbea55f85` |

The 8-bit sRGB PNGs use straight alpha. The surround maps to the full authored viewport. Its walkable area is transparent, including the D3 opening. The two Gate states use pivot `(156, 213)` at D3 center. The exit uses `(114, 162)` at F3 center. The plate uses contact `(120, 60)` at C2 center plus one quarter of the cell height. Props use `cell_height / 324` display scale and render below actors. Only the committed gate state chooses the actual texture. Missing artwork falls back to the live board presentation.

## Parity check

Godot 4.7.2 ran the ordinary launch from an isolated source copy with no `.godot` cache, `.lore`, or `assets-source`. A graphical observer of the same launch captured real mouse clicks without supplying an art override. At 1280 × 820 the unplanned and preview PNGs were byte-identical to the accepted captures; the post-commit difference was confined to a 71 × 101 rectangle around the Healer animation. The scenery, prop states, and all other pixels matched. The preview left the round at 2 and D3 shut; commit advanced to round 3 and opened D3.

To regenerate the live sequence without a user profile, use the existing capture tool with a new output directory:

```sh
godot --path games/company-of-unlikely-heroes --script res://tools/capture_storybook_gate.gd -- \
  --output="$PWD/.lore/local/storybook-gate-runtime-review"
```

The exact approved review PNGs were local output, not package inputs. Their SHA-256 values, in order of unplanned, preview, and committed: `fb9fc0e74482a6c788e1a967b63c27cc95dc589e915fcd801427eadd806f77f7`, `9521c631ca899a2837419afcc0036f420f5834cc7df2444f43ade0ff4f9160e7`, `9f946110e89bb71e2ab05e8ce96b82aef6618bd24f035ff27ed9badb7d9d70ec`. Exact actor animation timing can vary between captures.

See the [editable preparation package and recipes](../../assets-source/storybook-gate/README.md) for provenance.
