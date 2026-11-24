# Storybook board surrounds

`frontier_line_board.png` is the registered runtime derivative for the
`frontier_line_board` used by Hold the Line. Its SHA-256 is
`ae814c02f4891563811608865b668fedc7d3ed480b4813b20ea3d36d55a1a20f`.
The full-page scenery is noninteractive and transparent across the playable
grid; the existing board, figures, controls and gameplay remain live.

The [source and recipe](../../assets-source/storybook-surrounds/README.md)
describe provenance and byte-for-byte reproduction. The page selects this
texture by trusted board ID; it does not load artwork from `.lore`.

`frontier_bridge_board.png` is the side-only derivative for The Bridge Is Out.
SHA-256: `6b7413d502ab24b540a4158afe0120f9f44ff84a4fa9f828d96c45e8c0786d49`.
The central channel retains the live terrain and collapse state; scenery
extends only the side wings. The lossless import disables alpha-border color
fixup so the imported visible RGB and alpha match the source PNG. Its native
source, provenance, settings and reproducible command are documented in the
[recipe package](../../assets-source/storybook-surrounds/README.md#the-bridge-is-out).
