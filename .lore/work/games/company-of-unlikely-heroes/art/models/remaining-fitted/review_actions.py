"""Reopen exact Actions on accepted rigs and inspect registered tactical frames."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector
from mathutils.bvhtree import BVHTree


HERE = Path(__file__).resolve().parent
CAST_TOOLS = Path("games/company-of-unlikely-heroes/tools/cast")
ROOT = next(path for path in HERE.parents if (path / CAST_TOOLS).is_dir())
sys.dont_write_bytecode = True
sys.path[:0] = [str(HERE), str(ROOT / CAST_TOOLS)]
from bake_actor import render_ink, setup  # noqa: E402
from build_actions import SOURCES, TAKES, digest, load_actions, master, select  # noqa: E402


SIZE = 352
ANCHOR = (176, 272)
PROPS = {
    "healer": ("Staff_R_Detachable",),
    "bard": ("Bow_R_Detachable", "Fiddle_L_Detachable"),
    "alchemist": ("Hip_Rack_Detachable", "Amber_Potion_Detachable", "Acid_Flask_Detachable"),
}


def transform_error(a, b):
    return max(abs(x) for row in a - b for x in row)


def point(name):
    return bpy.data.objects[name].matrix_world.translation


def palm_y(bone):
    return ((bone.matrix @ bone.bone.matrix_local.inverted()).to_3x3() @ Vector((0, -1, 0))).normalized().y


def base_surface(obj):
    return BVHTree.FromPolygons([obj.matrix_world @ v.co for v in obj.data.vertices],
                               [p.vertices[:] for p in obj.data.polygons])


def clearance_meshes(scene, key):
    # Same body and prop surfaces as the approved masters' review checks.
    if key == "keep_your_head_down":
        targets = [obj for obj in scene.objects if obj.name.startswith((
            "Puffed working sleeve", "Face •", "Field coat • open bodice", "Linen wrapped forearm",
            "Saddle satchel", "Waistcoat • shaped", "Hair cap",
        ))]
        return bpy.data.objects["Crook • oak with rounded knocking head"], targets
    if key == "fitted_pull":
        targets = [bpy.data.objects[n] for n in (
            "Face • broad sculpted head", "Jaw • moving chin and lower lip plane", "Face • bulb of nose",
            "Waistcoat • broad belly and fitted shoulder", "Fiddle • carved spruce belly",
            "Fiddle • maple ribs", "Fiddle • two piece back",
        )]
        return bpy.data.objects["Bow • tapered sprung pernambuco"], targets
    return None, []


def curve_hash(action):
    strip = action.layers[0].strips[0]
    curves = [(c.data_path, c.array_index,
               [(list(k.co), list(k.handle_left), list(k.handle_right), k.interpolation)
                for k in c.keyframe_points])
              for c in strip.channelbag(action.slots[0]).fcurves]
    return hashlib.sha256(json.dumps(sorted(curves), separators=(",", ":")).encode()).hexdigest()


def metric(scene, rig, key, frame):
    bones = rig.pose.bones
    if key == "keep_your_head_down":
        crown = point("Staff_Knock_Contact")
        return {"crook": list(crown), "tip_height": crown.z, "butt_height": point("Staff_Butt").z}
    if key == "fitted_pull":
        frog, tip = point("Bow_hair_frog"), point("Bow_hair_tip")
        contact = point("String_contact")
        line = tip - frog
        at = min(max((contact - frog).dot(line) / line.length_squared, 0.), 1.)
        return {"bow_grip": list(point("Bow_grip")), "bow_tip": list(point("Bow_hair_tip")),
                "string_gap": (contact - (frog + at*line)).length,
                "wrist": list(bones["hand.R"].head)}
    if key == "send_off":
        return {"reach": [-bones[f"hand.{s}"].head.y for s in ("R", "L")],
                "palm_y": [palm_y(bones[f"hand.{s}"]) for s in ("R", "L")]}
    bottle = bpy.data.objects["Amber_Potion_Detachable"]
    base, neck = point("Potion base cradle"), point("Potion neck steady point")
    offset = bones["hand.R"].matrix.inverted() @ bottle.matrix_world
    return {"tilt": (neck - base).normalized().z, "reach": -bones["hand.R"].head.y,
            "vial_size": max(bottle.matrix_world.to_scale()), "neck": list(neck),
            "grip": list(offset.translation)}


def validate(scene, rig, ready, action, key):
    take = TAKES[key]
    select(scene, rig, ready, 1)
    base = {b.name: b.matrix.copy() for b in rig.pose.bones}
    mounts = {
        obj.name: obj.matrix_local.copy()
        for name in PROPS[take.role]
        if (obj := bpy.data.objects[name]).parent_bone not in ("prop.potion", "prop.acid")
    }
    prop_bindings = {name: bpy.data.objects[name].parent_bone for name in PROPS[take.role]}
    assert all(bpy.data.objects[name].parent == rig for name in prop_bindings)
    assert action["ready_master_sha256"] == SOURCES[take.role][-1]
    assert action["impact_frame"] == take.beat and action["fitted_candidate_clip"] == key
    assert action["fps"] == scene.render.fps == 24
    assert len(action.slots) == 1 and not rig.animation_data.nla_tracks
    assert list(action.frame_range) == [1, take.end]
    assert [(m.frame, m.name) for m in action.pose_markers] == list(take.stages)
    foot_error, root_error, seam_error = 0, 0, 0
    measures = {}
    prop_mesh, clearance = clearance_meshes(scene, key)
    for i in range(2, take.end * 2 + 1):
        f = i / 2
        select(scene, rig, action, f)
        matrices = {b.name: b.matrix for b in rig.pose.bones}
        assert all(math.isfinite(value) for m in matrices.values() for row in m for value in row)
        root_error = max(root_error, transform_error(matrices["root"], base["root"]))
        for side in ("L", "R"):
            name = f"foot.{side}"
            foot_error = max(foot_error, transform_error(matrices[name], base[name]))
        if f in (1, take.end):
            seam_error = max(seam_error, *(transform_error(m, base[name]) for name, m in matrices.items()))
        for name, matrix in mounts.items():
            assert transform_error(matrix, bpy.data.objects[name].matrix_local) < .000002
        if prop_mesh is not None and i % 2 == 0:
            surface = base_surface(prop_mesh)
            for part in clearance:
                assert not surface.overlap(base_surface(part)), (key, f, part.name)
        measures[f] = metric(scene, rig, key, f)
    assert max(foot_error, root_error, seam_error) < .00002, (key, foot_error, root_error, seam_error)
    load, turn = measures[take.stages[1][0]], measures[take.beat]
    if key == "keep_your_head_down":
        assert 1.10 < turn["tip_height"] < 1.51
        assert turn["crook"][1] < load["crook"][1] - .10
        assert min(m["butt_height"] for m in measures.values()) > 0
    elif key == "fitted_pull":
        assert turn["wrist"][1] - load["wrist"][1] > .28
        assert (Vector(turn["bow_grip"]) - Vector(load["bow_grip"])).length > .35
        assert min(m["string_gap"] for m in measures.values()) > .042
    elif key == "send_off":
        assert min(b - a for a, b in zip(load["reach"], turn["reach"])) > .17
        assert max(turn["palm_y"]) < -.90
        for f in (1, 13, 28):
            select(scene, rig, action, f)
            assert all(max(bpy.data.objects[name].matrix_world.to_scale()) < .00011
                       for name in PROPS[take.role][1:])
    else:
        assert turn["tilt"] < -.35 and turn["reach"] - load["reach"] > .27
        assert turn["vial_size"] > .99 and measures[17]["vial_size"] > .99
        assert measures[1]["vial_size"] < .00011 and measures[take.end]["vial_size"] < .00011
        assert min(measures[f / 2]["vial_size"] for f in range(18, 39)) > .999
        grip = Vector(turn["grip"])
        assert max((Vector(measures[f / 2]["grip"]) - grip).length for f in range(22, 39)) < .00003
    report = {"role": take.role, "label": take.label, "stages": take.stages, "control": take.control,
              "beat": take.beat, "feet_error": foot_error, "root_error": root_error,
              "ready_seam_error": seam_error, "integer_clearance_meshes": [obj.name for obj in clearance],
              "curve_sha256": curve_hash(action), "samples": measures}
    print(f"{key}: {len(measures)} half-frame samples; planted feet {foot_error:.7f}, "
          f"ready seam {seam_error:.7f}; key {turn}", flush=True)
    return report


def render(scene, rig, action, key, folder, draft):
    take = TAKES[key]
    frames = sorted(set(range(1, take.end + 1, 2)) | {frame for frame, _ in take.stages})
    if draft:
        frames = [take.stages[i][0] for i in (1, 2, 3)]
    for f in frames:
        select(scene, rig, action, f)
        render_ink(scene, folder / "raw.png", folder / f"{key}-{f:02}.png", SIZE)
    return frames


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--draft", action="store_true")
    parser.add_argument("--role", choices=SOURCES)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    library, output = args.library.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    candidate_sha = digest(library)
    result = {"candidate_sha256": candidate_sha, "size": SIZE, "anchor": ANCHOR, "fps": 24, "takes": {}}
    assert bpy.app.version[:3] == (5, 2, 2)
    for role in ([args.role] if args.role else SOURCES):
        source, rig_name, ready_name = master(role)
        bpy.ops.wm.open_mainfile(filepath=str(source))
        assert not bpy.data.libraries
        assert not any(i.source in {"FILE", "SEQUENCE", "MOVIE", "TILED"} and not i.packed_files
                       for i in bpy.data.images)
        relevant = {key: take for key, take in TAKES.items() if take.role == role}
        actions = load_actions(library, {take.name for take in relevant.values()})
        scene, rig, ready = bpy.context.scene, bpy.data.objects[rig_name], bpy.data.actions[ready_name]
        if not args.check_only:
            for obj in scene.objects:
                if obj.type == "LIGHT" or any("review" in c.name.lower() for c in obj.users_collection):
                    obj.hide_render = True
            setup(scene, role, ANCHOR, SIZE)
            if args.draft:
                scene.cycles.samples = 4
            bpy.context.view_layer.update()
            ground = world_to_camera_view(scene, scene.camera, Vector((0, 0, 0)))
            assert abs(ground.x * SIZE - ANCHOR[0]) < .001 and abs((1 - ground.y) * SIZE - ANCHOR[1]) < .001
        for key, take in relevant.items():
            report = validate(scene, rig, ready, actions[take.name], key)
            if not args.check_only:
                report["frames"] = render(scene, rig, actions[take.name], key, output, args.draft)
            result["takes"][key] = report
        master(role)
    assert digest(library) == candidate_sha
    (output / "proof.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
