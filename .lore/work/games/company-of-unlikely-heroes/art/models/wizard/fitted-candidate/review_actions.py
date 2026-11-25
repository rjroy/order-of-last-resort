"""Verify reopened Wizard actions and render registered board-angle samples."""

import argparse
import json
from pathlib import Path
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

HERE = Path(__file__).resolve().parent
CAST_TOOLS = Path("games/company-of-unlikely-heroes/tools/cast")
ROOT = next(path for path in HERE.parents if (path / CAST_TOOLS).is_dir())
sys.dont_write_bytecode = True
sys.path[:0] = [str(HERE), str(ROOT / CAST_TOOLS)]
from bake_actor import render_ink, setup  # noqa: E402
from build_actions import MARKERS, PREFIX, SIDES, SOURCE, SOURCE_SHA, select, sha  # noqa: E402


SIZE = 352
ANCHOR = (176, 272)
FITTED = {
    "mending_blast_self": ("Mending Blast · Self", [1, 4, 8, 13, 17, 21, 25, 27, 30], 17, 32),
    "send_off": ("Send-Off", [1, 4, 6, 9, 11, 13, 15, 18, 22, 25, 28], 13, 30),
    "clear_jump": ("Clear Jump", [1, 3, 6, 7, 8, 10, 12, 15, 17, 19, 20, 24, 28], 17, 30),
}
LEGACY = ("Neutral T", "Ready", "Blast", "Pull")


def rig_and_scene():
    return bpy.data.objects["Wizard_Rig"], bpy.context.scene


def actions_signature():
    return {
        name: (
            tuple(action.frame_range),
            [(m.name, m.frame) for m in action.pose_markers],
            [(curve.data_path, curve.array_index,
              [(tuple(k.co), tuple(k.handle_left), tuple(k.handle_right), k.interpolation)
               for k in curve.keyframe_points])
             for curve in action.layers[0].strips[0].channelbag(action.slots[0]).fcurves],
        )
        for name in LEGACY
        if (action := bpy.data.actions[PREFIX + name])
    }


def asset_signature():
    rig, scene = rig_and_scene()
    return (
        tuple(sorted((obj.name, obj.type, obj.parent.name if obj.parent else "",
                      obj.parent_bone, obj.data.name if obj.data else "")
                     for obj in scene.objects)),
        tuple((bone.name, bone.parent.name if bone.parent else "") for bone in rig.data.bones),
        tuple(sorted(material.name for material in bpy.data.materials if material.users)),
    )


def sole(side):
    ev = bpy.data.objects["Ground sole " + side].evaluated_get(bpy.context.evaluated_depsgraph_get())
    return min((ev.matrix_world @ v.co).z for v in ev.data.vertices)


def matrix_error(a, b):
    return max(abs(a[row][col] - b[row][col]) for row in range(4) for col in range(4))


def palm(hand):
    return (hand.matrix @ hand.bone.matrix_local.inverted()).to_3x3() @ Vector((0, -1, 0))


def check(rig, scene):
    assert bpy.data.is_saved and not bpy.data.libraries
    assert not any(im.source in {"FILE", "SEQUENCE", "MOVIE", "TILED"} and not im.packed_files
                   for im in bpy.data.images)
    assert scene.unit_settings.system == "METRIC" and scene.unit_settings.scale_length == 1
    assert scene.render.fps == 24 and scene.render.fps_base == 1
    assert not rig.animation_data.nla_tracks
    assert rig.animation_data.action.name == PREFIX + "Send-Off" and scene.frame_current == 1
    ledger = bpy.data.objects["Ledger_R_Detachable"]
    assert (ledger.parent, ledger.parent_type, ledger.parent_bone) == (rig, "BONE", "ledger_mount")
    bones = rig.pose.bones
    select(scene, rig, bpy.data.actions[PREFIX + "Ready"], 1)
    base = {b.name: b.matrix.copy() for b in bones}
    feet = {s: bones["foot." + s].head.copy() for s in SIDES}
    soles = {s: sole(s) for s in SIDES}
    assert max(soles.values()) < .010
    mount = bones["ledger_mount"].matrix.inverted() @ ledger.matrix_world
    metrics = {}
    for role, (title, frames, impact, stop) in FITTED.items():
        action = bpy.data.actions[PREFIX + title]
        assert action.use_fake_user and len(action.slots) == 1 and impact in frames
        assert list(action.frame_range) == [1, frames[-1]] and stop > frames[-1]
        assert {m.frame: m.name for m in action.pose_markers} == MARKERS[title]
        for f in (1, frames[-1]):
            select(scene, rig, action, f)
            errors = {b.name: matrix_error(b.matrix, base[b.name]) for b in bones}
            assert max(errors.values()) < .0001, (role, f, sorted(errors.items(), key=lambda i: i[1])[-8:])
        metrics[role] = {}
        for frame in range(1, frames[-1] + 1):
            scene.frame_set(frame)
            assert matrix_error(bones["root"].matrix, base["root"]) < .0001
            assert matrix_error(ledger.matrix_world, bones["ledger_mount"].matrix @ mount) < .0001
            floor = [sole(s) for s in SIDES]
            assert min(floor) > -.001, (role, frame, floor)
            for i, s in enumerate(SIDES):
                contact = role != "clear_jump" or frame <= 7 or frame >= (19 if s == "R" else 17)
                if contact:
                    assert (bones["foot." + s].head - feet[s]).length < .001, (role, frame, s)
                    assert abs(floor[i] - soles[s]) < .001
            pelvis = bones["pelvis"].head
            metrics[role][frame] = {
                "pelvis_z": round(pelvis.z, 4),
                "sole_z": [round(z, 4) for z in floor],
                "wrist_reach": [round(-bones["hand." + s].head.y, 4) for s in SIDES],
                "palm_y": [round(palm(bones["hand." + s]).normalized().y, 4) for s in SIDES],
            }
    send = metrics["send_off"]
    assert min(x["pelvis_z"] for x in send.values()) > .90
    assert min(b - a for a, b in zip(send[9]["wrist_reach"], send[13]["wrist_reach"])) > .20
    assert max(send[13]["palm_y"]) < -.85
    assert min(metrics["mending_blast_self"][17]["palm_y"]) > .70
    assert min(metrics["clear_jump"][8]["sole_z"]) > .055
    assert min(metrics["clear_jump"][12]["sole_z"]) > .30
    assert metrics["clear_jump"][17]["sole_z"][1] < .010
    print("Verified all frames: exact Ready seams, ledger mount, root registration, planted casts, "
          "inward self-heal palms, outward upright Send-Off, airborne Jump and leading boot contact.")
    return metrics


def render(rig, scene, output):
    for obj in scene.objects:
        if obj.type == "LIGHT" or any(c.name.startswith("07") for c in obj.users_collection):
            obj.hide_render = True
    setup(scene, "wizard", ANCHOR, SIZE)
    for role, (title, frames, _, _) in FITTED.items():
        action = bpy.data.actions[PREFIX + title]
        for frame in frames:
            select(scene, rig, action, frame)
            assert scene.camera is not None
            render_ink(scene, output / "scratch-raw.png", output / f"{role}-{frame:02}.png", SIZE)
    ground = world_to_camera_view(scene, scene.camera, Vector((0, 0, 0)))
    assert abs(ground.x * SIZE - ANCHOR[0]) < .001 and abs((1 - ground.y) * SIZE - ANCHOR[1]) < .001


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    candidate = Path(bpy.data.filepath).resolve()
    assert candidate.is_file() and candidate != SOURCE and sha(SOURCE) == SOURCE_SHA
    candidate_sha = sha(candidate)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    accepted_actions, accepted_assets = actions_signature(), asset_signature()
    bpy.ops.wm.open_mainfile(filepath=str(candidate))
    assert actions_signature() == accepted_actions and asset_signature() == accepted_assets
    rig, scene = rig_and_scene()
    samples = check(rig, scene)
    if not args.check_only:
        render(rig, scene, output)
    assert sha(candidate) == candidate_sha and sha(SOURCE) == SOURCE_SHA
    (output / "review.json").write_text(json.dumps({
        "candidate_sha256": candidate_sha, "accepted_source_sha256": SOURCE_SHA,
        "renderer": "Blender 5.2.2 LTS / Cycles board ink, 12 samples CPU",
        "capture_size": SIZE, "anchor": ANCHOR, "fps": 24, "takes": FITTED,
        "samples": samples,
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
