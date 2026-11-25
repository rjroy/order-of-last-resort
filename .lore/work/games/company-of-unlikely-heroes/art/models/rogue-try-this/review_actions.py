"""Reopen and verify the exact staged Blender file, then render it read-only."""

import argparse
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from build_actions import CUES, HELD_PUNCH, MASTER, MASTER_SHA, READY, VIAL, digest

from bake_actor import ANCHOR, SIZE, render_ink, setup
from bpy_extras.object_utils import world_to_camera_view


def pose(scene, rig, action, frame):
    rig.animation_data.action = bpy.data.actions[action]
    scene.frame_set(int(frame), subframe=frame % 1)


def take(scene, rig, cue, frame):
    pose(scene, rig, "Rogue | " + cue["title"], frame)


def point(rig, name):
    return rig.pose.bones[name].head.copy()


def snapshot(rig):
    return {b.name: b.matrix.copy() for b in rig.pose.bones}


def delta(a, b):
    return max(abs(a[i][j]-b[i][j]) for i in range(4) for j in range(4))


def geometry(ob):
    state = ob.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = state.to_mesh()
    verts = [state.matrix_world @ v.co for v in mesh.vertices]
    state.to_mesh_clear()
    return verts


def verify(scene, rig):
    assert not bpy.data.libraries and not bpy.data.images
    assert len(rig.pose.bones) == 40 and scene.render.fps == 24
    assert scene.unit_settings.system == "METRIC" and scene.unit_settings.scale_length == 1
    assert len(bpy.data.actions) == 8
    assert not rig.animation_data.nla_tracks
    pose(scene, rig, READY, 1)
    ready = snapshot(rig)
    sampled = 0
    vial = bpy.data.objects[VIAL]
    held = bpy.data.objects[HELD_PUNCH]
    stowed = bpy.data.objects["Punch_R_Detachable"]
    soles = [bpy.data.objects["Soft shoe sole • "+side] for side in "LR"]
    geometry_objects = [ob for ob in scene.objects if ob.type in {"MESH", "CURVE"}
                        and ob.name != "Paper ground Z=0"]
    print(f"reopened: {len(geometry_objects)} mesh/curve objects including the vial and held tool, {len(ready)} bones")
    for key, cue in CUES.items():
        ac = bpy.data.actions["Rogue | "+cue["title"]]
        assert ac.use_fake_user and ac.frame_range[:] == (1.,float(cue["end"]))
        assert {m.name: m.frame for m in ac.pose_markers} == cue["markers"]
        for f in (1,cue["end"]):
            take(scene, rig, cue, f)
            assert max(delta(ready[name], m) for name,m in snapshot(rig).items()) < .00005
        min_floor, max_plant_err, min_pad = 1., 0., 1.
        for i in range(2,cue["end"]*2+1):
            f = i/2
            take(scene, rig, cue, f)
            sampled += 1
            assert delta(ready["root"], rig.pose.bones["root"].matrix) < .00002
            floor = min(v.z for ob in soles for v in geometry(ob))
            min_floor = min(min_floor, floor)
            if key != "clear_jump" or not 5 < f < 17:
                max_plant_err = max(
                    max_plant_err,
                    *(delta(ready["foot."+side], rig.pose.bones["foot."+side].matrix) for side in "LR")
                )
            visible = key == "bitter_medicine" and 6 <= f < 13.5
            deps = bpy.context.evaluated_depsgraph_get()
            assert (vial.evaluated_get(deps).scale.x > .9) == visible
            has_punch = key == "cut_the_wire" and 8 <= f < 18.5
            assert (held.evaluated_get(deps).scale.x > .9) == has_punch
            assert (stowed.evaluated_get(deps).scale.x > .9) != has_punch
            if f in cue["samples"]:
                for ob in geometry_objects:
                    if ob == vial and not visible:
                        continue
                    for p in (world_to_camera_view(scene, scene.camera, v) for v in geometry(ob)):
                        min_pad = min(min_pad, p.x, p.y, 1-p.x, 1-p.y)
        print(f"{key}: sole floor {min_floor*1000:.2f} mm, max planted foot matrix difference "
              f"{max_plant_err:.6f}, smallest framing pad {min_pad*SIZE:.1f} px")
        assert min_floor > -.003 and max_plant_err < .0005 and min_pad*SIZE > 6

    take(scene, rig, CUES["clear_jump"], 12)
    assert min(v.z for ob in soles for v in geometry(ob)) > .27
    take(scene, rig, CUES["it_was_me"], 10)
    assert point(rig,"hand.L").y < -.61
    take(scene, rig, CUES["it_was_me"], 19)
    p = rig.pose.bones["hand.R"].tail
    chest = rig.pose.bones["chest"]
    chest_front = chest.head.lerp(chest.tail,.56) - Vector((0,.145,0))
    assert (p-chest_front).length < .25, (p,chest_front)
    take(scene, rig, CUES["cut_the_wire"], 13)
    close = (point(rig,"hand.R")-point(rig,"hand.L")).length
    assert max(point(rig,"hand.R").z,point(rig,"hand.L").z) < .69
    take(scene, rig, CUES["cut_the_wire"], 15)
    assert (point(rig,"hand.R")-point(rig,"hand.L")).length > close+.42
    take(scene, rig, CUES["bitter_medicine"], 13)
    assert point(rig,"hand.L").y < -.67
    print(f"validated {sampled} evaluated half-frame poses plus specific action beats")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("output", type=Path)
    p.add_argument("--check-only", action="store_true")
    p.add_argument("--beats-only", action="store_true")
    args = p.parse_args(sys.argv[sys.argv.index("--")+1:])
    scene, rig = bpy.context.scene, bpy.data.objects["Rogue_Rig"]
    opened = Path(bpy.data.filepath).resolve()
    assert opened != MASTER and digest(MASTER) == MASTER_SHA
    candidate_hash = digest(opened)
    for ob in scene.objects:
        if ob.type == "LIGHT" or ob.name == "Paper ground Z=0":
            ob.hide_render = True
    setup(scene, "rogue", ANCHOR)
    verify(scene, rig)
    if not args.check_only:
        out = args.output.resolve()
        out.mkdir(parents=True,exist_ok=True)
        neutral = out / "ready.png"
        raw = out / "raw.png"
        first = next(iter(CUES.values()))
        take(scene, rig, first, 1)
        render_ink(scene, raw, neutral, SIZE)
        for name,cue in CUES.items():
            fs = cue["markers"].values() if args.beats_only else cue["samples"]
            for f in fs:
                if f not in (1,cue["end"]):
                    take(scene, rig, cue, f)
                    render_ink(scene, raw, out/f"{name}-{f:02d}.png", SIZE)
        raw.unlink()
        (out/"cues.json").write_text(json.dumps({
            "fp_s": 24, "capture_px": SIZE, "origin_px": ANCHOR,
            "display_scale": .375, "takes": CUES,
        }, indent=2)+"\n")
    assert candidate_hash == digest(opened) and digest(MASTER) == MASTER_SHA


if __name__ == "__main__":
    main()
