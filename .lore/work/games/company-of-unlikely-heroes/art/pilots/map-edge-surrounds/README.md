# Map-edge surround source index

After the [Hold the Line pilot](../hold-the-line-surround/README.md), the user directed integration of this ten-board set. The art criterion is to carry scenery to the page edge without adding noise to the playable cells. Integration and technical verification do not record human acceptance of the in-game appearance.

Each unmodified, opaque 8-bit RGB PNG came from one native OpenAI `image_gen` call on 2026-11-23 via Codex CLI 0.172.0 with ChatGPT login. The image model was not reported. Each call referenced the matching `assets/boards/<board_id>.png` ([ground manifest](../../../../../../../games/company-of-unlikely-heroes/assets/boards/manifest.json)) for terrain and a 1280 × 820 opening capture of the mission listed below for page placement only. Captures are not recipe or runtime inputs. Native dimensions are 1567 × 1004 except `village_approach` (1566 × 1004).

| Native source | Opening capture mission ID | SHA-256 | Native image call ID |
|---|---|---|---|
| [`bridge/native.png`](bridge/native.png) | `company_rescue` | `dbb799af8910f5cfd20eef8af529a52b2ab0b85964505adc3be47877051fc252` | `call_62b32ba7b8d54605987bd96caa516e6d` |
| [`frontier_bridge_board/native.png`](frontier_bridge_board/native.png) | `bridge_is_out` | `933adca861bc98fae656b344cc7c5cc9bc3e30a82a8f2159eea1041a109cfd92` | `call_f5e7637d62a24aa89c4e8c5756779668` |
| [`frontier_ritual_board/native.png`](frontier_ritual_board/native.png) | `unfortunate_ritual` | `47a52bda3d96f475031ed7e1ae632684108d76d1799bb5a16fe08c396f40f192` | `call_0bd4b98e0d5e4b198c2178d31b6cfac7` |
| [`frontier_sheep_board/native.png`](frontier_sheep_board/native.png) | `great_sheep_escape` | `f9352932d20f529a334bc28330fdb3cb90be09780f8755f58cb4c9cbed0fbfb7` | `call_bdbc0c2864eb4218bcb18f557ff5b30d` |
| [`frontier_treasure_board/native.png`](frontier_treasure_board/native.png) | `dont_wake_the_giant` | `e35f43f4b34fd5a4a186db5cec600a23f9991b5ecab88cfcbd7670eca38a797c` | `call_430101a909f948c686572529d970847f` |
| [`frontier_wagon_board/native.png`](frontier_wagon_board/native.png) | `last_wagon` | `0cf80eeac28270e9a4e837b05dc5e0405df62d31a241fdd3f43d5b3f40669a49` | `call_4c8a7bfe9f7941f5b2ef0ec8f671905c` |
| [`road/native.png`](road/native.png) | `bridge_patrol` | `6323d830eec06a10331197835d4f4898776aa3acbc5dfde023bff35d8a320376` | `call_fd09f7d7dd3149fbb2fb50397dfcc076` |
| [`village_approach/native.png`](village_approach/native.png) | `goblin_mob` | `dc225bc539d4ab37a24e6364262c0883fccdc0b7ecd6caf92a1bdecc40b9be7f` | `call_b649975847f04a9394807c93257eef6d` |
| [`village_lane/native.png`](village_lane/native.png) | `harpoon_squad` | `2fa08ae52287a947926b893e3aa05ad33461f7b07014dcb716df670355f9d00c` | `call_eddc830ce6604469a0de37206359c2e1` |
| [`village_square/native.png`](village_square/native.png) | `unwelcome_guest` | `8312c3c17b625f7e918d5b7641143a57fa551cc2726b5a73ac622708f16a7365` | `call_b54fcf002e5b4c59a9dcd03ca51dbea4` |

## Design and registration

- **The Last Ferryman and The Bridge Is Out:** Side-only registration preserves the original river and crossing state. Narrow rippled water and low masonry distinguish the ferryman from the deep slate chasm. The chasm uses outward bank adjustments to keep the cliff joins clear.
- **The Last Wagon and Trouble on the Road:** Side-only road warps match the dirt approaches. The wagon road keeps its wheel ruts and distant cottage without painting in the wagon. The patrol road retains its upper-west fieldstone alignment with a localized row offset.
- **The Goblin Mob:** Side-only registration retains the original narrow cross-trail. A dry patch in the lower west suppresses its duplicate while the main slab road continues through both flanks.
- **The Unfortunate Ritual, The Great Sheep Escape, and Don't Wake the Giant:** The full ring carries heather and ruin fragments, open unfenced pasture, and warm-to-cool slate, respectively. It adds no markers or implied objectives.
- **The Harpoon Squad and The Unwelcome Guest:** Cool taupe flagstones distinguish the lane from the warm terracotta square. The square's final [corner override](../../../../../../../games/company-of-unlikely-heroes/assets/storybook-surrounds/village_square.md) blends the existing ground into the upper-west wall and lower-east roof, preserving ring alpha and leaving the native art untouched.

The [registration package](../../../../../../../games/company-of-unlikely-heroes/assets-source/storybook-surrounds/README.md) documents sampling and reproduction; [runtime board records](../../../../../../../games/company-of-unlikely-heroes/assets/storybook-surrounds/) identify the packaged derivatives.
