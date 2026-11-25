"""Build a small append-only library from the saved Smith. Never save the donor."""

import hashlib
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from build_smith import READY, Geometry, beat, collection, material, pose, q, sample

SHA = "a9d1113d0fb555accd4e0817890e3050d147bf45e2bf448a0fbe8f3b6e0da361"
KIT = "Smith supplementary hand kit"
PREFIX = "Hobby Smith | "


def kit():
    """Two independent grip-origin assemblies. The append step supplies the socket."""
    group = collection(KIT)
    mats = {
        k: material("Supplement • " + k, color, 0.16, 0)
        for k, color in {
            "ash": "b38249",
            "twine": "dfba82",
            "grain": "755034",
            "green": "a0ae37",
            "glass": "dce8ad",
            "cork": "ab7750",
            "glint": "f2edc8",
        }.items()
    }
    g = Geometry(None, mats)
    g.bucket = group

    def root(name):
        o = bpy.data.objects.new(name, None)
        group.objects.link(o)
        o.empty_display_size = 0.035
        return o

    staff = root("Smith_Crook_Detachable")
    g.tube(
        "Steam-bent ash shepherd hook",
        [
            (0, 0, -0.39),
            (0.006, 0.002, -0.30),
            (0, 0, 0.15),
            (0.003, 0.004, 0.42),
            (0.012, 0, 0.54),
            (0.055, 0, 0.61),
            (0.126, 0, 0.637),
            (0.185, 0, 0.61),
            (0.204, 0, 0.55),
            (0.179, 0, 0.509),
            (0.151, 0, 0.502),
        ],
        [0.032, 0.028, 0.024, 0.029, 0.034, 0.04, 0.038, 0.036, 0.034, 0.029, 0.021],
        "ash",
        staff,
        rounds=2,
    )
    for i in range(4):
        z = 0.395 + i * 0.018
        g.loft(
            "Crook binding",
            [(z, 0, 0, 0.032, 0.033), (z + 0.010, 0, 0, 0.035, 0.035), (z + 0.019, 0, 0, 0.032, 0.033)],
            "twine",
            staff,
            steps=20,
        )
    vial = root("Smith_Acid_Vial_Detachable")
    g.loft(
        "Pea-green acid bulb",
        [
            (-0.115, 0, 0, 0.034, 0.033),
            (-0.103, 0, 0, 0.064, 0.061),
            (-0.064, 0, 0, 0.081, 0.076),
            (-0.010, 0, 0, 0.080, 0.075),
            (0.023, 0, 0, 0.061, 0.058),
            (0.046, 0, 0, 0.031, 0.030),
        ],
        "green",
        vial,
        steps=24,
    )
    g.loft(
        "Blown vial neck",
        [
            (0.025, 0, 0, 0.060, 0.057),
            (0.048, 0, 0, 0.034, 0.032),
            (0.087, 0, 0, 0.028, 0.027),
            (0.092, 0, 0, 0.039, 0.038),
            (0.107, 0, 0, 0.039, 0.038),
        ],
        "glass",
        vial,
        steps=24,
    )
    g.loft(
        "Vial stopper",
        [(0.103, 0, 0, 0.027, 0.026), (0.134, 0, 0, 0.035, 0.034), (0.140, 0, 0, 0.031, 0.030)],
        "cork",
        vial,
        steps=18,
    )
    g.tube(
        "Acid glass reflection",
        [(-0.060, -0.041, -0.074), (-0.062, -0.047, -0.043), (-0.058, -0.049, -0.020)],
        [0.006, 0.009, 0.004],
        "glint",
        vial,
    )
    return group


def choreography():
    # Z aims the attached kit, so the actual crook travels through the contact arc.
    bready = beat(L=(0.38, -0.17, 1.16), fitting=(0.35, -0.1, 0.93))
    wind = beat(
        hip=(-0.026, 0.039, -0.095),
        body=(-6, -8, -17),
        look=(0, 4, 20),
        L=(0.48, -0.13, 1.46),
        fitting=(-0.23, 0.08, 0.97),
        R=(-0.42, -0.17, 1.10),
    )
    knock = beat(
        hip=(0.043, -0.044, -0.11),
        body=(12, 10, 9),
        look=(4, 6, 24),
        L=(0.64, -0.31, 1.33),
        fitting=(0.84, -0.47, 0.25),
        R=(-0.31, 0.04, 1.04),
    )
    cock = beat(
        hip=(-0.04, 0.05, -0.10),
        body=(-11, -7, -20),
        look=(-7, 9, 24),
        L=(0.45, 0.09, 1.68),
        fitting=(-0.2, 0.51, 0.84),
        R=(-0.44, -0.22, 1.13),
    )
    throw = beat(
        hip=(0.047, -0.06, -0.092),
        body=(9, 11, 19),
        look=(-3, 8, 29),
        L=(0.78, -0.32, 1.56),
        fitting=(0.81, -0.41, 0.42),
        R=(-0.37, 0.08, 1.02),
    )
    recoil = beat(
        hip=(-0.065, 0.082, -0.15),
        body=(-24, -19, -9),
        look=(-31, -23, -17),
        L=(0.32, -0.30, 1.46),
        R=(-0.51, -0.16, 1.28),
        hammer=(-0.74, -0.03, 0.67),
    )
    brace = beat(
        hip=(0.05, 0.02, -0.30),
        body=(24, 12, 11),
        look=(15, 7, 8),
        L=(0.48, -0.31, 0.78),
        R=(-0.34, -0.18, 0.82),
        apron=-32,
    )
    hold = beat(
        hip=(0.028, 0.037, -0.548),
        body=(49, 14, 11),
        look=(26, 12, 14),
        L=(0.50, -0.35, 0.33),
        R=(-0.40, -0.31, 0.52),
        hammer=(-0.58, -0.55, 0.60),
        fitting=(0.70, -0.64, 0.31),
        apron=-54,
        rfoot=(-0.25, 0.31, 0.158),
    )
    rise = beat(
        hip=(-0.018, -0.036, -0.325),
        body=(34, -4, 4),
        look=(10, 0, 12),
        L=(0.45, -0.40, 0.72),
        R=(-0.39, -0.22, 0.82),
        apron=-31,
    )
    tuck = beat(
        hip=(0, 0.07, -0.32),
        body=(20, -5, -13),
        look=(7, 9, -8),
        apron=-30,
        R=(-0.47, -0.13, 0.85),
        L=(0.35, -0.22, 1.09),
        hammer=(-0.18, -0.93, 0.32),
        rfoot=(-0.28, 0.19, 0.25),
        lfoot=(0.19, -0.13, 0.18),
    )
    slack = beat(
        hip=(0, 0.03, -0.10),
        body=(-10, 4, -2),
        look=(1, -13, 5),
        apron=-5,
        R=(-0.55, 0.06, 0.96),
        L=(0.52, 0.09, 1.04),
        hammer=(-0.85, -0.27, 0.45),
        fitting=(0.72, -0.25, 0.64),
        rfoot=(-0.31, 0.16, 0.19),
        lfoot=(0.26, 0.07, 0.16),
    )
    return {
        "Crook Bonk": [
            (1, bready),
            (5, beat(L=(0.39, -0.18, 1.21))),
            (9, wind),
            (12, wind | {"L": (0.57, -0.24, 1.47), "fitting": (0.32, -0.44, 0.84)}),
            (15, knock),
            (18, knock | {"fitting": (0.79, -0.41, 0.45)}),
            (22, bready | {"L": (0.49, -0.23, 1.25)}),
            (28, bready),
        ],
        "Acid Toss": [
            (1, READY),
            (5, beat(L=(0.36, -0.23, 1.30), look=(10, 0, 19))),
            (10, cock),
            (14, cock | {"L": (0.57, -0.10, 1.72), "body": (-4, 4, -3)}),
            (16, throw | {"L": (0.72, -0.23, 1.64)}),
            (18, throw),
            (21, throw | {"L": (0.74, -0.29, 1.43)}),
            (25, beat(L=(0.52, -0.23, 1.24), body=(7, 6, 7))),
            (32, READY),
        ],
        "Hit": [
            (1, READY),
            (3, recoil),
            (5, recoil | {"look": (-37, -23, -14)}),
            (8, beat(hip=(-0.026, 0.03, -0.104), L=(0.36, -0.27, 1.30), body=(-10, -8, -4))),
            (12, beat(body=(7, 3, 2), look=(9, 4, 3))),
            (17, READY),
        ],
        "Down": [
            (1, READY),
            (4, recoil),
            (8, brace),
            (12, hold | {"hip": (0.03, 0.043, -0.46)}),
            (16, hold | {"body": (55, 15, 13), "look": (46, 10, 12)}),
            (20, hold),
            (24, hold),
        ],
        "Recover": [
            (1, hold),
            (5, hold | {"look": (12, 6, 18)}),
            (9, rise),
            (14, brace),
            (18, beat(hip=(0.02, -0.01, -0.12), body=(15, 6, 7))),
            (22, beat(body=(4, 4, 2))),
            (26, READY),
        ],
        "Defeat": [
            (1, READY),
            (4, recoil),
            (8, tuck),
            (12, tuck),
            (16, slack),
            (20, slack),
            (24, slack | {"look": (-4, -16, 9)}),
        ],
    }


def floor_z(objects=None):
    dg = bpy.context.evaluated_depsgraph_get()
    result = 100.0
    for obj in bpy.context.scene.objects if objects is None else objects:
        if obj.type != "MESH":
            continue
        ev = obj.evaluated_get(dg)
        vs = ev.data.vertices
        xyz = np.empty(3 * len(vs), dtype=np.float32)
        vs.foreach_get("co", xyz)
        row = np.array(ev.matrix_world[2])
        result = min(result, (xyz.reshape(-1, 3) @ row[:3]).min() + row[3])
    return result


def make_take(rig, name, keys):
    action = bpy.data.actions.new(PREFIX + name)
    action.use_fake_user = True
    action.asset_mark()
    rig.animation_data.action = action
    prev = {}
    for frame in range(1, keys[-1][0] + 1):
        pose(rig, sample(keys, frame))
        if name == "Defeat" and frame > 4:
            # Roll onto his back and right shoulder. Lower the hull to its
            # actual contacts rather than letting the shoulder cross the floor.
            turn = sample(
                [
                    (f, {"deg": a})
                    for f, a in [
                        (4, 0.0),
                        (8, -24.0),
                        (12, -61.0),
                        (16, -90.0),
                        (20, -96.0),
                        (24, -98.0),
                    ]
                ],
                frame,
            )["deg"]
            root = rig.pose.bones["root"]
            rest = root.bone.matrix_local.to_quaternion()
            rot = q((0, 0, 1), -0.67 * turn) @ q((1, 0, 0), 0.90 * turn) @ q((0, 1, 0), 0.16 * turn)
            root.rotation_quaternion = rest.inverted() @ rot @ rest
            pivot = Vector((0, 0, 0.76))
            root.location = rest.inverted() @ (pivot - rot @ pivot)
            bpy.context.view_layer.update()
            root.location += rest.inverted() @ Vector((0, 0, 0.006 - floor_z()))
        for bone in rig.pose.bones:
            rot = bone.rotation_quaternion.copy()
            if bone.name in prev and rot.dot(prev[bone.name]) < 0:
                rot.negate()
            prev[bone.name] = rot
            bone.rotation_quaternion = rot
            bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone.name)
            if bone.name in ("root", "pelvis"):
                bone.keyframe_insert("location", frame=frame, group=bone.name)
    for bag in action.layers[0].strips[0].channelbags:
        for curve in bag.fcurves:
            for key in curve.keyframe_points:
                key.interpolation = "LINEAR"
    for label, f in {
        "Crook Bonk": [("Contact", 15)],
        "Acid Toss": [("Release", 18)],
        "Hit": [("Recoil", 3)],
        "Down": [("Contact", 16)],
        "Recover": [("Rise", 22)],
        "Defeat": [("Contact", 16)],
    }[name]:
        action.pose_markers.new(label).frame = f
    return action


def main():
    source = Path(bpy.data.filepath)
    assert hashlib.sha256(source.read_bytes()).hexdigest() == SHA
    out = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
    if out.exists():
        raise FileExistsError(out)
    rig = bpy.data.objects["HobbySmith_Rig"]
    actions = {make_take(rig, k, v) for k, v in choreography().items()}
    bpy.data.libraries.write(str(out), actions | {kit()}, fake_user=True, compress=True)
    assert hashlib.sha256(source.read_bytes()).hexdigest() == SHA


if __name__ == "__main__":
    main()
