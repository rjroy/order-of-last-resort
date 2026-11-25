"""Audit the staged complete Dodger atlas against stock and approved drawings."""

import argparse
import hashlib
import json
from pathlib import Path
from struct import unpack
from subprocess import check_output

from choreography import CUES

HERE = Path(__file__).resolve().parent
SUPPLEMENT = HERE.parents[6] / "games/company-of-unlikely-heroes/tools/cast/supplements/rogue.json"
SIZE, GROUND, BPP = 320, (160, 248), 4
CONTACT = {
    "it_was_me": (10, 19),
    "clear_jump": (7, 12, 17),
    "cut_the_wire": (13, 15),
    "bitter_medicine": (10, 13),
}


def atlas(directory, name="rogue.png"):
    path = directory / name
    w, h = unpack(">II", path.read_bytes()[16:24])
    data = check_output(["magick", str(path), "-depth", "8", "rgba:-"])
    assert len(data) == w * h * BPP, path
    return w, h, data


def rows(data, width, box):
    x, y, w, h = box
    return [data[(j*width+x)*BPP : (j*width+x+w)*BPP] for j in range(y, y+h)]


def clear_rgb(data):
    """Transparent RGB is not drawing data; antialiased alpha and RGB are."""
    result = bytearray(data)
    for k in range(0, len(result), BPP):
        if not result[k+3]:
            result[k:k+3] = b"\0\0\0"
    return result


def registered(data, width, height, clip, frame):
    sx, sy, w, h = frame["rect"]
    assert min(sx,sy,w-1,h-1) >= 0 and sx+w <= width and sy+h <= height
    ox, oy = clip["anchor"]
    assert int(ox) == ox and int(oy) == oy
    dx, dy = GROUND[0]-int(ox), GROUND[1]-int(oy)
    assert min(dx,dy) >= 0 and dx+w <= SIZE and dy+h <= SIZE
    drawing = bytearray(SIZE*SIZE*BPP)
    area = rows(data,width,frame["rect"])
    assert any(b for row in area for b in row[3::BPP])
    assert not any(b for row in area[:3]+area[-3:] for b in row[3::BPP])
    assert not any(b for row in area for b in row[3:12:BPP]+row[-9::BPP])
    for j, strip in enumerate(area):
        start = ((dy+j)*SIZE+dx)*BPP
        drawing[start:start+w*BPP] = strip
    return clear_rgb(drawing)


def actor(directory):
    manifest = json.loads((directory/"manifest.json").read_text())
    assert manifest["display_scale"] == .375
    return manifest["actors"]["rogue"]


def review_differences(new, reference):
    """Allow only a handful of one-LSB interior RGB roundings across renders."""
    differences = 0
    for at in range(0, len(new), BPP):
        a, b = new[at:at+BPP], reference[at:at+BPP]
        if a != b:
            assert a[3] == b[3] == 255 and max(abs(x-y) for x,y in zip(a,b)) <= 1
            differences += 1
    assert differences <= 8
    return differences


def verify(stock_dir, staged_dir, approved_pngs):
    source = HERE / "rogue-try-this.blend"
    recipe = json.loads(SUPPLEMENT.read_text())
    assert hashlib.sha256(source.read_bytes()).hexdigest() == recipe["sha256"]
    assert recipe["capture_size"] == SIZE and tuple(recipe["capture_anchor"]) == GROUND
    stock_entry, merged_entry = map(actor,(stock_dir,staged_dir))
    for field in ("source","sha256"):
        assert merged_entry[field] == stock_entry[field]
    assert merged_entry["supplements"] == [
        {"source": "art/"+recipe["source"], "sha256": recipe["sha256"]}
    ]
    stock, merged = stock_entry["clips"], merged_entry["clips"]
    assert set(stock).isdisjoint(CUES)
    assert set(merged) == stock.keys() | CUES.keys()
    assert all(merged[key] == clip for key,clip in stock.items()), "Stock clip metadata changed"
    sw, sh, baseline = atlas(stock_dir)
    w, h, data = atlas(staged_dir)
    assert w >= sw and h >= sh
    assert b"".join(rows(data,w,(0,0,sw,sh))) == baseline, "Changed stock rectangle pixels"
    count = most_rounded = exact = 0
    for ident, cue in CUES.items():
        clip = merged[ident]
        title, frames, stop, loop = recipe["takes"][ident]
        assert frames == cue["samples"] and stop == cue["end"]+1
        assert set(CONTACT[ident]) <= set(frames)
        assert clip["action"] == f"{recipe['action_prefix']} | {title}"
        assert clip["loop"] == loop and clip["path"] == "res://assets/cast/rogue.png"
        assert "release" not in clip and [f["source_frame"] for f in clip["frames"]] == frames
        boundaries = [round((f-1)*1000/24) for f in frames+[stop]]
        assert [f["duration_ms"] for f in clip["frames"]] == [
            after-before for before,after in zip(boundaries,boundaries[1:])
        ]
        for frame in clip["frames"]:
            f = frame["source_frame"]
            png = "ready.png" if f in (1,cue["end"]) else f"{ident}-{f:02}.png"
            aw, ah, expected = atlas(approved_pngs,png)
            assert aw == ah == SIZE
            rendered = registered(data,w,h,clip,frame)
            try:
                rounded = review_differences(rendered,clear_rgb(expected))
            except AssertionError as e:
                raise AssertionError(f"{ident} F{f}: approved drawing changed") from e
            most_rounded = max(most_rounded,rounded)
            exact += rounded == 0
            count += 1
        print(f"{ident}: {len(frames)} frames, {boundaries[-1]} ms")
    print(f"Verified {sw}×{sh} stock region byte-for-byte, {len(stock)} unchanged clips / "
          f"{sum(len(c['frames']) for c in stock.values())} frames; {count} approved frames "
          f"match in ground registration at {w}×{h} atlas size "
          f"({exact} exact; at most {most_rounded} opaque pixels differ by one RGB level).")


def proof(stage, out):
    from package_review import draw

    notes = [("DAFT DODGER / PRODUCTION ATLAS",22,28,20),
             ("Packed contact drawings",22,52,13),
             ("65 x 54 tile scale",500,52,13)]
    layers = []
    clips = actor(stage)["clips"]
    for row,(name,beats) in enumerate(CONTACT.items()):
        cue, clip = CUES[name], clips[name]
        by_frame = {f["source_frame"]: f["rect"] for f in clip["frames"]}
        names = {f: label for label,f in cue["markers"].items()}
        ground = 193+151*row
        notes.append((cue["title"],22,74+151*row,14))
        for col,f in enumerate(beats):
            x,y,w,h = by_frame[f]
            crop = f"{w}x{h}+{x}+{y}"
            layers.append((stage/"rogue.png",crop,clip["anchor"],.51,(130+130*col,ground)))
            layers.append((stage/"rogue.png",crop,clip["anchor"],.254,(537+68*col,ground-12)))
            notes.append((f"{names[f]} F{f}",90+130*col,ground+17,12))
    draw(730,677,notes,layers,out)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("stock", "stage", "approved_frames"):
        parser.add_argument(name, type=Path)
    parser.add_argument("--proof",type=Path,help="optional contact proof from the staged PNG")
    args = parser.parse_args()
    verify(args.stock, args.stage, args.approved_frames)
    if args.proof:
        proof(args.stage,args.proof)
