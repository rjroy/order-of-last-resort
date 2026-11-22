# Barnaby's Order of Last Resort: storybook battle UX concepts

Exploratory full-screen images generated on 2026-11-21. Ronald selected the [framed Marked-Up Illustration](marked-up-illustration-framed.png) as the starting direction for the playable Gate pilot. The image is a visual reference, not a background or a specification for terrain and rules. Acceptance of the playable interface is separate.

## Shared brief

Each view explores the same intermediate state from *The Wrong Side of the Door*, round 2 of the standalone mission. The Knight is at B2. Moving him to the plate at C2 would open the closed D3 gate while the plate stays occupied. The proposed move replaces his Guard for this round; the Healer and Wizard retain Support and Hold. The actual board should be inked, the proposal drawn in pencil, and the commit action separate from selection and preview.

The Fieldbook puts deliberate action choice in a fixed strip near the board. The Marked-Up Illustration puts a destination's actions next to the thing clicked. The Inked Sequence makes the forecast an ordered strip of comic panels beside the live scene. All three begin with selecting a hero on the playable scene.

## Source references

All three independent generations used the same three references in this order. The built-in `experimental_image_generate` tool reported `openai/gpt-image-2`. The references supplied character design, tone, and live board geometry, not the existing screen layout.

| Reference | SHA-256 |
| --- | --- |
| [Approved guild portrait](../../../notes/a_richly_textured_hand_inked_watercolor_illustrat.webp) | `1852a999f87daa38e93339c91128a39d7f35f439dac288ca97aea548e1814dc0` |
| `.lore/local/painted-boards-live-20261121-153335/gate-closed.png` (round 1) | `433ed104a0786f370b14fa321b0176aa7206c53b427d41dd13c2f85e1b5aaaaa` |
| `.lore/local/painted-boards-live-20261121-153335/gate-open.png` (round 3) | `9ac39c3281730d45b5d19d02ddd2710e81116de881d3a52494dae3681a769664` |

The local screenshots are reference evidence, not required files. To reproduce the original test-interface screenshots, use `games/company-of-unlikely-heroes/tools/capture_painted_boards.gd` and its run instructions at commit `b7c85df`, the repository HEAD at concept dispatch. The old capture tool is not part of the current game.

## Candidate images

The saved concepts are byte-for-byte copies of the generator's originals. Native filenames below are relative to `/tmp/opencode/images/ses_dff650e88ffets7LAEDaIEezko/`; the local copies linked in the first column are the review files.

| Candidate | Native filename | Format and size | SHA-256 |
| --- | --- | --- | --- |
| [The Company Fieldbook](company-fieldbook.png) | `image_200aa1728001w3Va5SeMorkYpC.png` | PNG, 1586 × 992 | `37ec78a157ec2df83d0a8e47ec549097df0894a708f605ad432c2735d305107c` |
| [The Marked-Up Illustration](marked-up-illustration.png) | `image_200aa172f001VHLJRWNhZS25mW.png` | PNG, 1586 × 992 | `b0943b4d3d32d9cb7abbd01868165a7ecf62a3245208424d92f48d0b8aecc334` |
| [The Inked Sequence](inked-sequence.png) | `image_200aa1731001jbifANBiHca5U7.png` | PNG, 1586 × 992 | `59d796bf58531ec2f00a9583ef66b5fee752d6f51fec3388e4e715f5599cfa2e` |

## Review notes

- **Company Fieldbook:** The solid Knight at B2, pencil Knight at C2, closed D3 gate, and standing-order strip agree with the brief. The large cast illustration competes with the board, and the struck-through Guard can look deleted rather than suspended for one round. Keep the stable action strip, reduce the border art, and say explicitly which order is replaced this round.
- **Marked-Up Illustration:** The scene feels most like an illustration you can play, and the penciled gate swing is the clearest of the three. The generated perspective misregisters the far bank: the goblin and exit read closer to F3 and G3 than E3 and F3. Use the actual board geometry, not this image, for cell placement. In a complex round the contextual label needs space and automatic abilities still need an obvious way in.
- **Inked Sequence:** The ordered panels make the override and the standing actions easy to compare, while the gate annotation shows the effect on the board. The panels illustrate only the heroes. They are not the complete forecast: the live round 3 capture also shows the goblin has stepped to D3. Treat illustrative beats as highlights, never as a replacement for the complete ordered forecast, including enemies and hazards.

All three PNG sources decoded with ImageMagick, matched their saved copies byte-for-byte, and the saved images were visually inspected. The static concepts do not test keyboard access, resolving a round, or text at multiple screen sizes.

**Recommendation for discussion:** Choose the Company Fieldbook's stable actions and visible standing orders as the base. Give the board the visual priority of the Marked-Up Illustration and use its gate-swing annotation where it helps explain a cause. The Inked Sequence's illustrated beats would be stronger in a debrief than as the default forecast.

## Framed Marked-Up Illustration

The user chose the Marked-Up Illustration as the closest direction and requested a narrow physical book edge, approximately 10–20 pixels on all four sides, with no broad margin, gutter, cover, or tabletop. The exact `marked-up-illustration.png` above was the sole image input for this edit. The original remains unchanged; the framed concept is a separate candidate for review.

- **Candidate:** [marked-up-illustration-framed.png](marked-up-illustration-framed.png), generated on 2026-11-21 with `experimental_image_generate` (`openai/gpt-image-2`).
- **Native output:** `/tmp/opencode/images/ses_dff650e88ffets7LAEDaIEezko/image_200b52e19001vz1Ap58uu5R4yT.png`.
- **Verified:** PNG, 1585 × 992, SHA-256 `18570ec484d5b61772c4b5a94b29ff349f1fb075155f4022a4ef44118dc0da46`. Decoded with ImageMagick, matched the native output byte-for-byte, and was visually inspected at display scale. The source file still matches its original checksum above.
- **Frame:** Continuous on all four sides, approximately 18–20 pixels at the straight-side midpoints, with rounded corners. The pale page layers are clear, though the warm highlight can also read as gilded trim.
- **Drift:** The native output is one pixel narrower than the source. The generator lightly redrew foliage, stone, and costume details while keeping the composition, board-first controls, focus ring, and pencil gate preview. The original concept's far-side piece placement caveat still applies.
