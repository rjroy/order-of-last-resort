"""Add three editable fitting actions to a separate copy of the accepted Wizard."""

import argparse
import hashlib
from math import radians, sqrt
from pathlib import Path
import sys

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector


HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / "wizard-blockout.blend"
SOURCE_SHA = "5776143ed740e3cb924535ab267bad1e49a41753651c89223d812e36a65eaf24"
OUTPUT = HERE / "wizard-fitted-candidate.blend"
PREFIX = "Wizard | "
SIDES = ("R", "L")

# Wrists, onward finger directions, and palm normals are in Wizard space
# (metres, -Y forward). Each side keeps the live finger rig.
SELF_GATHER = (
    ((-.29, -.36, 1.19), (.75, -.15, .50), (.15, .28, .85)),
    (( .30, -.39, 1.23), (-.70, .17, .55), (-.15, .45, .60)),
)
SELF_MEND = (
    ((-.23, -.31, 1.17), (.85, .16, .32), (.15, .85, -.12)),
    (( .20, -.30, 1.28), (-.85, .21, .27), (.25, .90, -.15)),
)
SEND_LOAD = (
    ((-.37, -.29, 1.10), (.20, -.15, .85), (.25, -.90, -.05)),
    (( .36, -.35, 1.25), (-.20, -.15, .85), (-.25, -.90, -.07)),
)
SEND_RELEASE = (
    ((-.01, -.65, 1.22), (.17, -.29, .93), (.01, -.98, -.14)),
    (( .29, -.65, 1.36), (-.20, -.24, .95), (.02, -.99, -.15)),
)
SEND_FOLLOW = (
    ((-.035, -.58, 1.12), (.27, -.69, .69), (.05, -.67, -.68)),
    (( .31,  -.59, 1.26), (-.31, -.56, .77), (.02, -.72, -.69)),
)
JUMP_LOAD = (
    ((-.40, -.05, 1.00), (.25, .75, -.42), (.30, -.35, -.70)),
    (( .37, -.15, 1.06), (-.25, .81, -.40), (-.20, -.27, -.70)),
)
JUMP_APEX = (
    ((-.62, -.12, 1.35), (-.75, -.50, .27), (.20, .23, -.80)),
    (( .37, -.60, 1.44), (.04, -.96, .31), (-.32, -.05, -.70)),
)
JUMP_LAND = (
    ((-.49, -.34, 1.03), (-.46, -.71, -.31), (.15, -.12, -.80)),
    (( .43, -.44, 1.11), (.37, -.77, -.35), (-.15, -.20, -.85)),
)

MARKERS = {
    "Mending Blast · Self": {1: "Ready", 8: "Cup the spell", 17: "Heal self", 21: "Release breath", 30: "Ready restored"},
    "Send-Off": {1: "Ready", 9: "Brace and load", 13: "Send target away", 18: "Hands follow, feet stay", 28: "Ready restored"},
    "Clear Jump": {1: "Ready", 6: "Load", 8: "Leave ground", 12: "Airborne", 17: "Land beside opponent", 20: "Absorb landing", 28: "Ready restored"},
}

# Frame, hip offset (x/y/z), right and left ankle offsets, forward chest angle.
# Board travel is deliberately not keyed: the board owns source/destination.
JUMP = (
    (1,  (0, 0, 0),        (0, 0, 0),          (0, 0, 0),          0),
    (3,  (0, .028, -.03),  (0, 0, 0),          (0, 0, 0),          7),
    (6,  (0, .065, -.15),  (0, 0, 0),          (0, 0, 0),         20),
    (7,  (0, -.015, -.045),(0, 0, 0),          (0, 0, 0),         14),
    (8,  (0, -.05, .065),  (0, .03, .080),     (0, -.01, .100),    9),
    (12, (0, -.02, .29),   (-.015, .20, .46), (.01, -.19, .365),   9),
    (15, (0, -.01, .14),   (-.025, .08, .21), (.012, -.08, .16),  13),
    (17, (0, -.045, -.04), (0, 0, .070),      (0, 0, 0),          19),
    (19, (0, -.035, -.13), (0, 0, 0),         (0, 0, 0),          22),
    (20, (0, -.03, -.16),  (0, 0, 0),         (0, 0, 0),          24),
    (24, (0, -.015, -.06), (0, 0, 0),         (0, 0, 0),           9),
    (28, (0, 0, 0),        (0, 0, 0),         (0, 0, 0),           0),
)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def select(scene, rig, action, frame):
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    scene.frame_set(frame)


def matrix_with_axes(y, reference_normal):
    y = Vector(y).normalized()
    normal = Vector(reference_normal)
    normal = (normal - normal.dot(y) * y).normalized()
    return Matrix((y, normal, y.cross(normal))).transposed()


def blend_jump(frame):
    for start, end in zip(JUMP, JUMP[1:]):
        if start[0] <= frame <= end[0]:
            t = (frame - start[0]) / (end[0] - start[0])
            # Keep upward/downward speed through takeoff and landing; only ease
            # on the grounded compressions and at the top of each vertical arc.
            if (start[0], end[0]) in {(1, 3), (3, 6), (12, 15), (20, 24), (24, 28)}:
                t = t * t * (3 - 2 * t)
            return (*(Vector(start[i]).lerp(Vector(end[i]), t) for i in (1, 2, 3)),
                    start[4] + (end[4] - start[4]) * t)
    raise ValueError(frame)


class Author:
    def __init__(self, scene, rig):
        self.scene = scene
        self.rig = rig
        self.bones = rig.pose.bones
        self.view = bpy.context.view_layer
        self.ready = bpy.data.actions[PREFIX + "Ready"]
        select(scene, rig, self.ready, 1)
        self.base = {b.name: (b.location.copy(), b.rotation_quaternion.copy(), b.scale.copy())
                     for b in self.bones}
        self.ready_matrix = {b.name: b.matrix.copy() for b in self.bones}
        self.previous = {}

    def reset(self):
        self.rig.animation_data.action = None
        for b in self.bones:
            b.location, b.rotation_quaternion, b.scale = self.base[b.name]
        self.view.update()

    def orient(self, key, world_rotation):
        b = self.bones[key]
        target = world_rotation.to_matrix().to_4x4()
        target.translation = b.head
        converter = b.bone.convert_local_to_pose
        basis = converter(target, b.bone.matrix_local, parent_matrix=b.parent.matrix,
                          parent_matrix_local=b.parent.bone.matrix_local, invert=True)
        b.rotation_quaternion = basis.to_quaternion()
        self.view.update()

    def turn(self, key, angles):
        turn = Euler(tuple(map(radians, angles))).to_quaternion()
        self.orient(key, turn @ self.bones[key].matrix.to_quaternion())

    def shift(self, key, offset):
        bone = self.bones[key]
        target = bone.matrix.copy()
        target.translation += offset
        bone.matrix = target
        self.view.update()

    def swing(self, key, destination):
        bone = self.bones[key]
        axis = (bone.tail - bone.head).normalized()
        new = (destination - bone.head).normalized()
        self.orient(key, axis.rotation_difference(new) @ bone.matrix.to_quaternion())

    def limb(self, upper, lower, end, pole):
        # Analytic FK targets preserve bone lengths and put the elbow/knee on
        # the performer-facing side of the chain without baking a constraint.
        start = self.bones[upper].head
        a, b = (self.bones[key].bone.length for key in (upper, lower))
        delta = Vector(end) - start
        d = delta.length
        if not abs(a - b) < d < a + b:
            raise ValueError(f"{upper} cannot reach {tuple(end)} from {tuple(start)} (d={d:.4f})")
        along = delta.normalized()
        bend = Vector(pole) - Vector(pole).dot(along) * along
        x = (a * a - b * b + d * d) / (2 * d)
        joint = start + x * along + sqrt(a * a - x * x) * bend.normalized()
        self.swing(upper, joint)
        self.swing(lower, Vector(end))

    def arms(self, pair, open_amount=.9):
        for side, (wrist, fingers, palm) in zip(SIDES, pair):
            sign = -1 if side == "R" else 1
            hand = "hand." + side
            self.limb("upper_arm." + side, "forearm." + side, wrist, (sign, -.14, -.42))
            local = self.bones[hand].bone.matrix_local
            rest_direction = local.to_3x3() @ Vector((0, 1, 0))
            desired = matrix_with_axes(fingers, palm) @ matrix_with_axes(rest_direction, (0, -1, 0)).inverted()
            self.orient(hand, (desired @ local.to_3x3()).to_quaternion())
            for b in self.bones:
                if b.parent and b.name.endswith("." + side) and b.name.split(".")[0] in (
                        "index", "middle", "ring", "pinky", "thumb"):
                    b.rotation_quaternion = self.base[b.name][1].slerp(Quaternion(), open_amount)

    def key(self, action, frame, bones=None):
        self.rig.animation_data.action = action
        if action.slots:
            self.rig.animation_data.action_slot = action.slots[0]
        for b in self.bones if bones is None else (self.bones[name] for name in bones):
            q = b.rotation_quaternion.copy()
            if b.name in self.previous:
                q.make_compatible(self.previous[b.name])
            b.rotation_quaternion = q
            self.previous[b.name] = q
            for prop in ("location", "rotation_quaternion", "scale"):
                b.keyframe_insert(prop, frame=frame, group=b.name)

    def new(self, name):
        self.previous.clear()
        action = bpy.data.actions.new(PREFIX + name)
        action.use_fake_user = True
        action.use_frame_range = True
        action.frame_start = 1
        action.frame_end = max(MARKERS[name])
        for frame, label in MARKERS[name].items():
            action.pose_markers.new(label).frame = frame
        return action

    def finish(self, action, dense=()):
        for channel in action.layers[0].strips[0].channelbag(action.slots[0]).fcurves:
            for key in channel.keyframe_points:
                if any(f'"{name}"' in channel.data_path for name in dense):
                    key.interpolation = "LINEAR"
                else:
                    key.handle_left_type = key.handle_right_type = "AUTO_CLAMPED"

    def casting(self, name, poses):
        action = self.new(name)
        for frame, pair, angles, openness in poses:
            self.reset()
            if pair:
                chest, head, hat = angles
                self.turn("chest", chest)
                self.turn("head", head)
                self.turn("hat.tip", hat)
                self.arms(pair, openness)
            self.key(action, frame)
        self.finish(action)

    def jumping(self):
        action = self.new("Clear Jump")
        poses = {
            3: (None, (-2, 0, 4), (5, 0, 5)),
            6: (JUMP_LOAD, (0, 0, -7), (13, -4, 9)),
            8: (JUMP_APEX, (-6, 0, 4), (-9, -3, -6)),
            12: (JUMP_APEX, (3, -6, 5), (-15, 4, -12)),
            15: (JUMP_LAND, (10, 1, -4), (6, -5, 8)),
            17: (JUMP_LAND, (13, 0, -1), (19, 0, 5)),
            20: (JUMP_LAND, (11, 0, 4), (25, 5, -4)),
            24: (None, (-3, 0, 4), (-6, 0, 3)),
        }
        legs = ["pelvis", *(f"{part}.{side}" for side in SIDES for part in ("thigh", "shin", "foot"))]
        for frame in range(1, 29):
            self.reset()
            if frame not in (1, 28):
                hip, right, left, pitch = blend_jump(frame)
                self.shift("pelvis", hip)
                self.turn("chest", (pitch, 0, -4 if 6 <= frame <= 17 else 0))
                for side, offset in zip(SIDES, (right, left)):
                    foot = "foot." + side
                    matrix = self.ready_matrix[foot]
                    self.limb("thigh." + side, "shin." + side, matrix.translation + offset,
                              (-.28 if side == "R" else .28, -1, 0))
                    toe = -26 if side == "R" else -16
                    flare = max(0., 1 - abs(frame - 12) / 4)
                    self.orient(foot, Euler((radians(toe * flare), 0, 0)).to_quaternion() @ matrix.to_quaternion())
                if frame in poses:
                    pair, head, hat = poses[frame]
                    self.turn("head", head)
                    self.turn("hat.tip", hat)
                    self.turn("tail.side.R", (-pitch / 2, 0, -6))
                    self.turn("tail.side.L", (-pitch / 2, 0, 6))
                    if pair:
                        self.arms(pair)
            self.key(action, frame, None if frame in poses or frame in (1, 28) else legs)
        self.finish(action, legs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    output = args.output.resolve()
    if not output.name.endswith(".blend") or output.exists() or output == SOURCE:
        parser.error("output must be a new, separate .blend file")
    assert sha(SOURCE) == SOURCE_SHA
    assert bpy.app.version[:3] == (5, 2, 2)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    scene = bpy.context.scene
    rig = bpy.data.objects["Wizard_Rig"]
    author = Author(scene, rig)
    rest = (None, None, 0)
    author.casting("Mending Blast · Self", (
        (1, *rest),
        (8, SELF_GATHER, ((1, -4, 0), (14, 0, -6), (-5, 0, 2)), .35),
        (13, SELF_MEND, ((-4, 4, -6), (11, 0, 3), (-8, 0, 2)), .6),
        (17, SELF_MEND, ((-7, 4, -5), (-3, 0, 5), (-8, 0, 2)), .76),
        (21, SELF_GATHER, ((-2, 1, 2), (-5, 0, 3), (7, 0, -3)), .52),
        (30, *rest),
    ))
    author.casting("Send-Off", (
        (1, *rest),
        (6, SEND_LOAD, ((-5, 0, -5), (5, 1, 4), (5, -2, -1)), .6),
        (9, SEND_LOAD, ((-7, -3, -9), (4, 0, 3), (9, -1, 3)), .82),
        (13, SEND_RELEASE, ((15, 1, 5), (-6, 0, -3), (-14, 5, 7)), 1.0),
        (15, SEND_RELEASE, ((14, 1, 4), (-4, 0, -2), (-4, -4, -1)), 1.0),
        (18, SEND_FOLLOW, ((11, 0, 4), (-3, 0, -1), (8, 0, -3)), .85),
        (22, SEND_LOAD, ((2, 0, 1), (0, 0, 0), (-5, 0, 0)), .44),
        (28, *rest),
    ))
    author.jumping()
    default = bpy.data.actions[PREFIX + "Send-Off"]
    select(scene, rig, default, 1)
    scene.frame_end = 28
    scene.timeline_markers.clear()
    for frame, label in MARKERS["Send-Off"].items():
        scene.timeline_markers.new(label, frame=frame)
    bpy.ops.wm.save_as_mainfile(filepath=str(output), compress=True)
    assert sha(SOURCE) == SOURCE_SHA
    print(f"Saved {output}  SHA-256 {sha(output)}")


if __name__ == "__main__":
    main()
