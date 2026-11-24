# Hold the Line surround pilot (olr-kgx)

**Status:** The user directed integration of this exact painting along with the full remaining set of board surrounds. Hold the Line now uses the registered derivative over its original board and book UI. That direction authorized integration; it did not record human acceptance of the in-game appearance.

`hold-the-line-native.png` is the unmodified 1566 × 1004 opaque 8-bit RGB PNG (sRGB as decoded, 3,212,574 bytes). Native and candidate files compare byte for byte. SHA-256: `24c89a8fb925939ba54606c2ac6561eb929955faaf338681d2d1c3eb3d16abdd`.

- The [integrated source and registration recipe](../../../../../../../games/company-of-unlikely-heroes/assets-source/storybook-surrounds/README.md) use `frontier_line_board-native.png`, a byte-for-byte copy of this painting.
- The [runtime package](../../../../../../../games/company-of-unlikely-heroes/assets/storybook-surrounds/README.md) contains the registered `frontier_line_board.png` selected by trusted board ID. Separate [live Hold the Line evidence](../../../../../../local/map-edge-passes/verify/hold-the-line-final/hold_the_line.png) verifies the surround in Godot; the 1280 × 820 comparison preserved the tactical aperture, command rail, and outer frame. This is technical verification, not human acceptance.

## Generation

- 2026-11-23, Codex CLI 0.172.0 via ChatGPT login, one native OpenAI `image_gen` call. The image model was not reported.
- Codex thread `01a20bd3-ccea-7a53-a578-b8256cee98bc`; native call `call_9e80193c49f841a08db95cc533c61689`.
- Preserved native staging: `~/.codex/generated_images/01a20bd3-ccea-7a53-a578-b8256cee98bc/exec-bcd9f261-793b-4c01-97ad-5ca704564d99.png`.
- Input order: `games/company-of-unlikely-heroes/assets/boards/frontier_line_board.png` for warm stone terrain and watercolor; `games/company-of-unlikely-heroes/assets-source/storybook-field/frontier-field-native.png` for full-page composition only.
- Brief: full-bleed ochre stone yard with a quiet 7 × 5 center, open flanks, a low dry-stone breastwork on the lower left, and shallower rubble and grass on the upper right. No baked grid, actors, UI, frame, or dark rails.

## Original offline preview

Local evidence lives in `.lore/local/map-edge-passes/hold-the-line/`: the exact baseline copy `hold-the-line-before.png`, the **offline composite** `hold-the-line-candidate-composited.png`, and `native-image-call.jsonl`. At 1280 × 820, the breastwork and right rubble both read above the controls, and the open approaches still read. The added side ground is slightly warmer than the existing center. Both the native painting and the composite were visually inspected.

The preview fits the native art to the authored 1280 × 820 page, uses the existing Field `register.py` outward feather and the live page shader's aperture refit, and composites below the book/UI using black/white transmission probes from the unchanged game. The probe baseline matched the review screenshot byte for byte. All 476,502 pixels inside the measured playable aperture and all pixels below the rail separator were unchanged. The painting was never loaded by Godot for this preview; it is not evidence of runtime acceptance.

To regenerate this historical preview, run these commands from the repo root at pre-integration revision `74a100c`, with the pilot painting and local evidence scripts available. Both scripts refuse to overwrite output:

```sh
evidence="$PWD/.lore/local/map-edge-passes/hold-the-line"
godot --display-driver wayland --path games/company-of-unlikely-heroes --script "$evidence/probe.gd"
PYTHONDONTWRITEBYTECODE=1 python "$evidence/composite.py"
```

The offline preview used Godot 4.7.2 (`gl_compatibility`), Python 3.14.8, NumPy 2.5.4, and ImageMagick 7.1.2-34.
