# bridge painted surround

**Native candidate only.** Authorized in the map-edge rollout after the Hold the Line pilot; this file does not integrate artwork or record runtime acceptance.

- Original: `native.png`, 1567 × 1004 opaque 8-bit RGB PNG, decoded as sRGB, 3,245,711 bytes. Byte-identical to the preserved native output. SHA-256: `dbb799af8910f5cfd20eef8af529a52b2ab0b85964505adc3be47877051fc252`.
- 2026-11-23, Codex CLI 0.172.0 on ChatGPT login, one native OpenAI `image_gen` call. Thread `01a20be0-b4cf-70e1-8a13-c86eb08b195d`, call `call_62b32ba7b8d54605987bd96caa516e6d`; image model unreported.
- Native staging: `~/.codex/generated_images/01a20be0-b4cf-70e1-8a13-c86eb08b195d/exec-de70ce3c-4f98-43da-85d1-02b83f1970bc.png`.
- Reference 1 (terrain): `games/company-of-unlikely-heroes/assets/boards/bridge.png`. SHA-256: `4f82c2e88167e11f9cf95813dd756805254e4c3dc5d343440e6f079a20a20e91`.
- Reference 2 (page placement only): actual opening capture `.lore/local/map-edge-passes/before/company_rescue.png`. SHA-256: `8d72bd1b1e430d5277365f1ee80d00aba59d950363a7845b1b4653db4375eb93`.
- Exact CLI brief and job trace (local evidence): `.lore/local/map-edge-passes/native-jobs/bridge/request.txt` and `native-image-call.jsonl`. Brief SHA-256: `1107392862bdd664fde51d6b8775c53605fe4bff94fda4568f29c22dd38080b6`.

**Source inspection:** Visually compared with the ground master and 1280 × 820 opening. Teal, rippled river and twin ochre approaches with low perimeter masonry match the existing season and ground; nothing bridges the river. Direct page fit is more diagonal than the baseline river and puts the east approach several dozen pixels low. Preserve the original river through the top/bottom strips or register both bank contours before using those portions; check the east road seam live.
