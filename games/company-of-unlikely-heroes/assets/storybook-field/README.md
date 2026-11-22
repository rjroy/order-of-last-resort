# Accepted Storybook Frontier Field

Ronald approved this exact combined in-engine candidate on 2026-11-21: “perfect.” `frontier-field-surround-rgba.png` is the accepted 1280 × 820 straight-alpha sRGB PNG, copied byte-for-byte. SHA-256: `115188a399e0153855b6f479a74fb4c5730916bd483566f40a8b85e332b46cee`.

The shared Storybook page loads it only for the `frontier_field` board, used by The Shield Wall, The Cowardly Captain, The Explosive Situation, The Unfortunate Healer, The Duelists, The Odd Couple, The Mirror Company, and The Last One Standing. The existing ground, figures, grid, book edge, controls, and forecast stay live. This layer is registered to the full viewport and is transparent across all 35 playable cells. It contains no Gate props or gameplay information.

```sh
godot --path games/company-of-unlikely-heroes -- --mission=explosive_situation
godot --path games/company-of-unlikely-heroes -- --mission=mirror_company
```

To repeat the review, in Explosive Situation select Wizard and use **Blast nearest**. Forecast shows both Bomber explosions. In Mirror Company select Wizard and move from B4 to A4. Forecast shows the Knight's aura redirecting the rival Blast to the Rival Knight, then the rival Healer restoring 2 HP. Commit each and compare the live outcome.

From an isolated source copy without `.godot`, `.lore`, or the authoring package, both ordinary launches ran in Godot 4.7.2. For each, the opening, preview, forecast, reaction, and committed captures matched the accepted in-engine frames pixel-for-pixel at 1280 × 820. Gate opening and preview also matched the prior captures pixel-for-pixel; the post-commit difference was confined to the Healer's animation. Legacy openings of all three missions matched before and after promotion.

The approved Explosive Situation and Mirror Company preview PNG SHA-256 values are `b44f0e354421114186e7a13a97fef9a4bc08e6d53cadafd5b820eb7ba0550b7d` and `7f39063042ca3aa09bd9c3cfe4f2434ed7db703dbf6747cdd65240d0d26852ec`. Captures are review evidence only, not game inputs. See [source provenance and the preparation recipe](../../assets-source/storybook-field/README.md).
