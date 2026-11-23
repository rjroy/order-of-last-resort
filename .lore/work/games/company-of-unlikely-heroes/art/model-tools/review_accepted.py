"""Reopen registered models and optionally render the accepted poses, without publishing."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

ART = Path(__file__).resolve().parents[1]
ROSTER = ART / "concepts/non-hero-cast/accepted-roster.json"
ROOT = next(p for p in ART.parents if (p / "games/company-of-unlikely-heroes/project.godot").is_file())
sys.path.insert(0, str(ROOT / "games/company-of-unlikely-heroes/tools/cast"))
from bake_actor import setup


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def image(args):
    subprocess.run(["magick", "-limit", "thread", "1", *map(str, args)], check=True, timeout=60)


def review(role, row, output, size):
    src = (ROSTER.parent / row["source"]).resolve()
    assert src.is_relative_to(ART / "models") and sha(src) == row["sha256"], src
    bpy.ops.wm.open_mainfile(filepath=str(src), load_ui=False, use_scripts=False)
    s = bpy.context.scene
    assert not bpy.data.libraries and all(i.source != "FILE" or i.packed_file for i in bpy.data.images), src
    rig, = [o for o in s.objects if o.type == "ARMATURE"]
    actions = {a.name.split(" | ")[-1]: a for a in bpy.data.actions}
    assert len(actions) == len(bpy.data.actions), src
    if output:
        assert not s.compositing_node_group and not s.render.use_freestyle
        for obj in s.objects:
            if obj.type == "LIGHT":
                obj.hide_render = True
        anchor = row["capture_anchor_px"]
        setup(s, role, anchor)
        assert s.render.resolution_x == s.render.resolution_y == size
        bpy.context.view_layer.update()
        uv = world_to_camera_view(s, s.camera, Vector())
        assert abs(uv.x * size - anchor[0]) < .001 and abs((1 - uv.y) * size - anchor[1]) < .001
        dest = output / role
        dest.mkdir(parents=True, exist_ok=True)
    for label, (action, frame) in row["review_poses"].items():
        take = actions[action]
        assert take.frame_range[0] <= frame <= take.frame_range[1], (role, action, frame)
        if not output:
            continue
        rig.animation_data.action = take
        s.frame_set(frame)
        raw = dest / f"{label}-raw.png"
        final = dest / f"{label}.png"
        s.render.filepath = str(raw)
        bpy.ops.render.render(write_still=True)
        # Approved contour from the production recipe recorded in accepted-roster.json.
        image([raw, "-alpha", "extract", "-morphology", "Dilate", "Disk:2", "-write", "mpr:mask",
               "+delete", "-size", f"{size}x{size}", "xc:#352b28", "mpr:mask", "-compose",
               "CopyOpacity", "-composite", raw, "-compose", "Over", "-composite", "-strip",
               f"PNG32:{final}"])
        assert final.stat().st_size > 500, final
    assert sha(src) == row["sha256"], src
    print(f"{role}: {row['sha256']} · {'rendered' if output else 'opened and checked'}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("roles", nargs="*")
    parser.add_argument("--output", type=Path, help="target below .lore/local; defaults to validation only")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    output = args.output.resolve() if args.output else None
    if output is not None and not (ROOT / ".lore/local").resolve() in output.parents:
        parser.error("render output must be below .lore/local/")
    data = json.loads(ROSTER.read_text())
    actors = data["actors"]
    roles = args.roles or actors.keys()
    if set(roles) - actors.keys():
        parser.error(f"unknown roles: {', '.join(sorted(set(roles) - actors.keys()))}")
    assert bpy.app.version[:3] == (5, 2, 2)
    width, height = data["approved_review"]["finish"]["capture_px"]
    assert width == height
    for role in roles:
        review(role, actors[role], output, width)


if __name__ == "__main__":
    main()
