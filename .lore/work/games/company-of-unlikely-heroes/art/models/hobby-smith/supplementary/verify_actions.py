"""Reopen a candidate library against the read-only donor. Blender background only."""

import hashlib
import json
import sys
from pathlib import Path

import bpy
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from build_actions import KIT, PREFIX, SHA, floor_z


def snapshot(rig, action, frame):
    rig.animation_data.action = bpy.data.actions[PREFIX + action]
    bpy.context.scene.frame_set(frame)
    return np.array([np.array(bone.matrix) for bone in rig.pose.bones])


def main():
    donor = Path(bpy.data.filepath)
    assert hashlib.sha256(donor.read_bytes()).hexdigest() == SHA
    path = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
    takes = json.loads((HERE / "takes.json").read_text())
    names = {PREFIX + take[0] for take in takes.values()}
    with bpy.data.libraries.load(str(path)) as (src, dst):
        assert set(src.actions) == names and src.collections == [KIT]
        assert not src.armatures and not src.libraries and not src.images
        dst.actions = list(src.actions)
        dst.collections = [KIT]
    group = dst.collections[0]
    roots = {o.name: o for o in group.objects if o.parent is None}
    assert set(roots) == {"Smith_Crook_Detachable", "Smith_Acid_Vial_Detachable"}
    assert set(group.objects) == {
        part for root in roots.values() for part in [root, *root.children_recursive]
    }
    assert all(
        o.type == "MESH" and o.data.materials
        for root in roots.values()
        for o in root.children_recursive
    )
    scene = bpy.context.scene
    donor_meshes = {o for o in scene.objects if o.type == "MESH"}
    socket = bpy.data.objects["Fitting_Detachable"]
    old_kit = set(socket.children_recursive + bpy.data.objects["Hammer_Detachable"].children_recursive)
    scene.collection.children.link(group)
    for root in roots.values():
        root.parent = socket.parent
        root.parent_type = socket.parent_type
        root.parent_bone = socket.parent_bone
        root.matrix_parent_inverse = socket.matrix_parent_inverse.copy()
        root.matrix_basis = socket.matrix_basis.copy()

    rig = bpy.data.objects["HobbySmith_Rig"]
    ready = snapshot(rig, "Ready", 1)
    for name, frame in [("Hit", 1), ("Hit", 17), ("Down", 1), ("Recover", 26), ("Defeat", 1)]:
        assert np.allclose(ready, snapshot(rig, name, frame), atol=1e-5), (name, frame)
    assert np.allclose(snapshot(rig, "Down", 24), snapshot(rig, "Recover", 1), atol=1e-5)

    mins = {}
    for clip, (name, frames, stop, loop) in takes.items():
        if clip == "acid_flask":
            continue
        action = bpy.data.actions[PREFIX + name]
        assert not loop and frames[-1] < stop
        assert tuple(action.frame_range) == (frames[0], frames[-1])
        assert all(marker.frame in frames for marker in action.pose_markers)
        rig.animation_data.action = action
        lowest = 1.0
        first_feet = None
        prop = (
            roots["Smith_Crook_Detachable"] if clip == "bonk" else roots["Smith_Acid_Vial_Detachable"]
        )
        for frame in range(frames[0], frames[-1] + 1):
            bpy.context.scene.frame_set(frame)
            visible = donor_meshes
            if clip in {"bonk", "acid"}:
                visible = donor_meshes - old_kit
                if clip == "bonk" or frame < action.pose_markers["Release"].frame:
                    visible.update(prop.children_recursive)
                    assert (
                        prop.matrix_world.translation - socket.matrix_world.translation
                    ).length < 1e-6
            lowest = min(lowest, floor_z(visible))
            if clip not in {"bonk", "acid", "hit"}:
                continue
            feet = np.array([rig.pose.bones["foot." + side].head for side in "RL"])
            if first_feet is None:
                first_feet = feet
            assert np.allclose(feet, first_feet, atol=0.001), (clip, frame, feet)
        # Subpixel tolerance (3 mm is 0.12 board px) for the deformed cloth cuff.
        assert lowest >= -0.003, (clip, lowest)
        mins[clip] = round(float(lowest), 5)
    assert hashlib.sha256(donor.read_bytes()).hexdigest() == SHA
    print(json.dumps({"library": str(path), "ground_minimum_m": mins}, indent=2))


if __name__ == "__main__":
    main()
