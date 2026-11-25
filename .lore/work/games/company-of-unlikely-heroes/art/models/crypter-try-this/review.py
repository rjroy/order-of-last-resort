"""Reopen, check and render action candidates with the stock bake projection."""

from pathlib import Path
import sys

import bpy

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from build import TOOLS, FLOOR_WORDS, MASTERS, digest, limits
from score import CLIPS, READY, RENDER, RIGS
sys.path.insert(0, str(TOOLS))
from bake_actor import render_ink, setup


def load_action(rig, name):
    action = bpy.data.actions[name]
    rig.animation_data.action = action
    assert len(action.slots) == 1
    rig.animation_data.action_slot = action.slots[0]
    return action


def pose(scene, rig, f):
    scene.frame_set(int(f), subframe=f-int(f))
    return {b.name: b.matrix.copy() for b in rig.pose.bones}


def compare(a, b, exclude=()):
    return max(abs(v-w) for name in a if name not in exclude
               for x, y in zip(a[name], b[name]) for v, w in zip(x, y))


def native_signature(role):
    rig = bpy.data.objects[RIGS[role]+"_Rig"]
    rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
    inventory = sorted((o.name, o.type, o.data.name if o.data else None,
                        o.parent.name if o.parent else None, o.parent_bone) for o in bpy.context.scene.objects)
    native = {}
    for action in list(bpy.data.actions):
        load_action(rig, action.name)
        for f in range(int(action.frame_range[0]), int(action.frame_range[1])+1):
            native[action.name, f] = pose(bpy.context.scene, rig, f)
    return rig, rest, inventory, native


def review(role, source, out):
    assert source.name in (f"{role}-candidate.blend", f"{role}-try-this.blend") and out.is_dir()
    checksum = digest(source)
    master = HERE.parents[1] / MASTERS[role]["source"]
    assert digest(master) == MASTERS[role]["sha256"]
    bpy.ops.wm.open_mainfile(filepath=str(master))
    _, rest, inventory, native = native_signature(role)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    scene = bpy.context.scene
    rig, new_rest, new_inventory, reopened = native_signature(role)
    assert not bpy.data.libraries and not rig.animation_data.nla_tracks
    assert inventory == new_inventory and compare(rest, new_rest) == 0
    assert all(compare(old_pose, reopened[key]) < 2e-6 for key, old_pose in native.items())
    ready_name = f"{RIGS[role]} | {READY[role]}"
    ready = native[ready_name, 1]
    load_action(rig, ready_name)
    pose(scene, rig, 1)
    ready_bounds = limits(scene)
    print(f"{role} native ready bounds xyz: {ready_bounds}", flush=True)
    for clip, (end, cues) in CLIPS[role].items():
        action = load_action(rig, f"Try This | {clip}")
        assert action.use_fake_user and tuple(action.frame_range) == (1, end)
        assert {m.name: m.frame for m in action.pose_markers} == cues
        start, finish = pose(scene, rig, 1), pose(scene, rig, end)
        if role != "skeleton":
            assert compare(start, ready) < 2e-5
        if role != "zombie":
            assert compare(finish, ready) < 2e-5
            for step in range(2, 2*end+1):
                sample = pose(scene, rig, step/2)
                assert max((sample[n].translation-ready[n].translation).length for n in ("foot.L","foot.R")) < .001
        else:
            floors = []
            for step in range(2, 2*end+1):
                pose(scene, rig, step/2)
                floors.append(limits(scene)[2][0])
            assert min(floors) >= ready_bounds[2][0] - .002
            assert limits(scene)[2][1] < .67
            assert finish["head"].translation.z < .55
            print(f"Zombie ground z range {min(floors):.4f}..{max(floors):.4f}; terminal bounds {limits(scene)}",
                  flush=True)

    for o in scene.objects:
        if o.type == "LIGHT" or any(word in o.name.lower() for word in FLOOR_WORDS):
            o.hide_render = True
    setup(scene, role, [160,248])
    for clip, frames in RENDER[role].items():
        load_action(rig, f"Try This | {clip}")
        for f in frames:
            scene.frame_set(f)
            path = out/f"{role}-{clip}-{f:02d}.png"
            render_ink(scene, out/f"{role}-raw.png", path, 320)
            assert path.stat().st_size > 1024
    assert digest(source) == checksum and digest(master) == MASTERS[role]["sha256"]
    print(f"{role}: validated {len(inventory)} objects, {len(rest)} bones, "
          f"{len(native)} protected native poses; candidate sha256 {checksum}", flush=True)


if __name__ == "__main__":
    role, model, frames = sys.argv[sys.argv.index("--")+1:]
    review(role, Path(model).resolve(), Path(frames).resolve())
