"""Check staged real-board sheets against the pinned stock art at the tile level."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
from subprocess import check_output
from tempfile import NamedTemporaryFile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[6]
GAME = ROOT / "games/company-of-unlikely-heroes"
ART = HERE.parents[1]
STOCK = "5952801588efe25d1d2a60a40bbc179172573f53"
MOMENTS = {
    "necromancer": {"recall": 17, "hush": 11, "stay_close": 15},
    "skeleton": {"recall_tuck": 17},
    "zombie": {"play_dead": 26},
}


def stock_blob(filename):
    path = (GAME / "assets/cast" / filename).relative_to(ROOT)
    return check_output(["git", "-C", ROOT, "show", f"{STOCK}:{path}"])


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def atlas(path):
    with path.open("rb") as stream:
        width, height = struct.unpack(">II", stream.read(24)[16:24])
    rgba = check_output(["magick", str(path), "-depth", "8", "rgba:-"])
    assert len(rgba) == width*height*4
    return width, height, rgba


def tile(image, rect):
    width, height, rgba = image
    x, y, w, h = rect
    assert x >= 0 and y >= 0 and x+w <= width and y+h <= height
    return b"".join(rgba[4*(width*i+x):4*(width*i+x+w)] for i in range(y,y+h))


def compare_stock(role, old, new, old_atlas, new_atlas):
    changed = []
    total = 0
    for name, original in old.items():
        clip = new[name]
        assert original == clip, (role, name, "stock metadata or rect changed")
        for a,b in zip(original["frames"], clip["frames"]):
            if tile(old_atlas, a["rect"]) != tile(new_atlas, b["rect"]):
                changed.append((name, a["source_frame"]))
            total += 1
    assert not changed, (role, changed)
    return total


def verify(root):
    stock_manifest = json.loads(stock_blob("manifest.json"))
    totals = [0, 0]
    for role, cue_frames in MOMENTS.items():
        stage = root/role if (root/role/"manifest.json").is_file() else root
        manifest = json.loads((stage/"manifest.json").read_text())
        for field in ("version", "display_scale", "source_root", "pixels_per_metre", "camera_euler_xyz"):
            assert stock_manifest[field] == manifest[field], field
        stock_role, new_role = stock_manifest["actors"][role], manifest["actors"][role]
        for field in ("source", "sha256"):
            assert stock_role[field] == new_role[field], (role, field)
        old, new = stock_role["clips"], new_role["clips"]
        delivered = atlas(stage/f"{role}.png")
        with NamedTemporaryFile(suffix=".png", dir=root.parent) as png:
            png.write(stock_blob(f"{role}.png"))
            png.flush()
            original = atlas(Path(png.name))
        supplement = json.loads((GAME/"tools/cast/supplements"/f"{role}.json").read_text())
        assert digest(ART/supplement["source"]) == supplement["sha256"]
        assert new_role["supplements"] == [
            {"source": "art/"+supplement["source"], "sha256": supplement["sha256"]}
        ]
        takes = supplement["takes"]
        assert set(takes) == set(cue_frames) == set(new)-set(old) and set(old) <= set(new)
        kept = compare_stock(role, old, new, original, delivered)
        added = 0
        for name, frame in cue_frames.items():
            action, samples, stop, loop = takes[name]
            clip = new[name]
            assert clip["action"] == action and clip["loop"] == loop is False
            assert clip["path"] == f"res://assets/cast/{role}.png"
            assert frame in samples and samples[0] == 1 and samples[-1] == stop-1
            assert [row["source_frame"] for row in clip["frames"]] == samples
            elapsed = 0
            for row in clip["frames"]:
                assert elapsed == round((row["source_frame"]-1)*1000/24)
                assert row["duration_ms"] > 0
                elapsed += row["duration_ms"]
                rect = row["rect"]
                w,h = rect[2:]
                rgba = tile(delivered, rect)
                alpha = rgba[3::4]
                assert any(alpha)
                assert not any(alpha[:3*w]) and not any(alpha[-3*w:])
                for y in range(h):
                    assert not any(alpha[y*w:y*w+3]) and not any(alpha[(y+1)*w-3:(y+1)*w])
                added += 1
            assert elapsed == round((stop-1)*1000/24)
        print(f"{role}: {delivered[0]}×{delivered[1]}, {kept} stock tiles unchanged, {added} new samples")
        totals[0] += kept
        totals[1] += added
    print(f"Verified {totals[0]} byte-identical stock tiles and {totals[1]} new samples.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path)
    verify(parser.parse_args().stage.resolve())
