# road painted surround

**Native candidate only.** Authorized in the map-edge rollout after the Hold the Line pilot; this file does not integrate artwork or record runtime acceptance.

- Original: `native.png`, 1567 × 1004 opaque 8-bit RGB PNG, decoded as sRGB, 2,982,808 bytes. Byte-identical to the preserved native output. SHA-256: `6323d830eec06a10331197835d4f4898776aa3acbc5dfde023bff35d8a320376`.
- 2026-11-23, Codex CLI 0.172.0 on ChatGPT login, one native OpenAI `image_gen` call. Thread `01a20be2-1b37-7e10-a7db-c2824f80dad0`, call `call_fd09f7d7dd3149fbb2fb50397dfcc076`; image model unreported.
- Native staging: `~/.codex/generated_images/01a20be2-1b37-7e10-a7db-c2824f80dad0/exec-72b50ecf-29c1-4710-b666-bbdf28138bc4.png`.
- Reference 1 (terrain): `games/company-of-unlikely-heroes/assets/boards/road.png`. SHA-256: `87195ae9b1100096f2bcb47a67c9d6871ce9588e803750afd15a376ca8b127b1`.
- Reference 2 (page placement only): actual opening capture `.lore/local/map-edge-passes/before/bridge_patrol.png`. SHA-256: `8ab3c607a7cd63fcef82a9cd5a96c91e94adf3bd82c1a64b6544e98403c233dc`.
- Exact CLI brief and job trace (local evidence): `.lore/local/map-edge-passes/native-jobs/road/request.txt` and `native-image-call.jsonl`. Brief SHA-256: `a9340890fd78cf789f0491160f55a5f9e89e8e5a301e4616f7d74545dd876bc6`.

**Source inspection:** Visually compared with the ground master and 1280 × 820 opening. The buff track, diagonal upper-left fieldstone, olive-gold pasture and low corner foliage match the opening. The new track runs roughly 30–45 px lower at the east join on a direct page fit, where it should be registered upward to the existing trail.
