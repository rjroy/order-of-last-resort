"""Write only the four new actions; the three accepted rigs remain separate."""

import argparse
import hashlib
from dataclasses import dataclass
from math import radians, sqrt
from pathlib import Path
import sys

import bpy
from mathutils import Euler, Matrix, Vector


HERE = Path(__file__).resolve().parent
SOURCES = {
    "healer": ("healer", "Healer", "Ally Heal", "3a0b8427c788a26b511a6f6262c6debeb3fbcea78fa2c44fd867b32e5010aaa5"),
    "bard": ("bard", "Bard", "Ready Count-In", "5685e66c4f43a73a8267afcb6d16c369e64d3d6460cc80631642f3e796874966"),
    "alchemist": ("mixologist", "Mixologist", "Ready", "8458bf889a27b57fc99698964c5dcceb981c9b60bf54ac3db3aff29cea48033f"),
}


@dataclass(frozen=True)
class Take:
    role: str
    label: str
    stages: tuple
    control: tuple

    @property
    def name(self):
        return f"{SOURCES[self.role][1]} | Fitted | {self.label}"

    @property
    def beat(self):
        return self.stages[2][0]

    @property
    def end(self):
        return self.stages[-1][0]


TAKES = {
    "keep_your_head_down": Take("healer", "Keep Your Head Down",
        ((1, "Ready"), (8, "Set the crook low"), (13, "Soft tap / cover"),
         (17, "Hold, then withdraw"), (28, "Ready restored")), ("bonk", 15)),
    "fitted_pull": Take("bard", "Pull",
        ((1, "Ready"), (9, "Reach off the strings"), (14, "Reel / pull starts"),
         (17, "Finish the draw"), (29, "Ready restored")), ("push", 12)),
    "send_off": Take("alchemist", "Send-Off",
        ((1, "Ready"), (9, "Brace / hands gather"), (13, "Palms drive / shove starts"),
         (17, "Press through, feet stay"), (28, "Ready restored")), ("pull", 13)),
    "hostile_dose": Take("alchemist", "Hostile Dose",
        ((1, "Ready"), (9, "Lift the amber vial"), (13, "Tip / contact"),
         (17, "Withdrawal, still in grip"), (28, "Ready restored")), ("potion", 20)),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def master(role):
    directory, prefix, ready, checksum = SOURCES[role]
    path = HERE.parent / directory / f"{directory}-blockout.blend"
    if digest(path) != checksum:
        raise ValueError(f"Accepted source hash does not match: {path}")
    return path, f"{prefix}_Rig", f"{prefix} | {ready}"


def select(scene, rig, action, frame):
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    whole = int(frame)
    scene.frame_set(whole, subframe=frame - whole)


def rotation(angles):
    return Euler(tuple(map(radians, angles))).to_quaternion()


def basis(axis, palm):
    axis = Vector(axis).normalized()
    palm = Vector(palm)
    palm = (palm - palm.dot(axis) * axis).normalized()
    return Matrix((axis, palm, axis.cross(palm))).transposed()


class Author:
    def __init__(self, scene, rig, ready):
        self.scene, self.rig = scene, rig
        self.bones = rig.pose.bones
        self.update = bpy.context.view_layer.update
        select(scene, rig, ready, 1)
        self.ready = self.channels()
        self.world = {b.name: b.matrix.copy() for b in self.bones}
        self.previous = {}

    def reset(self, pose=None):
        self.rig.animation_data.action = None
        for bone in self.bones:
            bone.location, bone.rotation_quaternion, bone.scale = (self.ready if pose is None else pose)[bone.name]
        self.update()

    def channels(self):
        return {b.name: (b.location.copy(), b.rotation_quaternion.copy(), b.scale.copy()) for b in self.bones}

    def snapshot(self, action, frame):
        select(self.scene, self.rig, action, frame)
        return self.channels()

    def orient(self, name, world_quat):
        b = self.bones[name]
        target = world_quat.to_matrix().to_4x4()
        target.translation = b.head
        local = b.bone.convert_local_to_pose(target, b.bone.matrix_local,
                 parent_matrix=b.parent.matrix, parent_matrix_local=b.parent.bone.matrix_local, invert=True)
        b.rotation_quaternion = local.to_quaternion()
        self.update()

    def turn(self, name, angles):
        self.orient(name, rotation(angles) @ self.bones[name].matrix.to_quaternion())

    def aim(self, name, end):
        b = self.bones[name]
        turn = (b.tail - b.head).rotation_difference(Vector(end) - b.head)
        self.orient(name, turn @ b.matrix.to_quaternion())

    def arm(self, side, wrist, pole, parts=("upper_arm", "forearm")):
        upper, fore = (f"{part}.{side}" for part in parts)
        start = self.bones[upper].head
        a, b = (self.bones[name].bone.length for name in (upper, fore))
        delta = Vector(wrist) - start
        d, line = delta.length, delta.normalized()
        if not abs(a - b) < d < a + b:
            raise ValueError(f"{upper}: wrist {tuple(wrist)} outside {a + b:.3f} m reach (d={d:.3f})")
        bend = Vector(pole) - Vector(pole).dot(line) * line
        along = (a * a - b * b + d * d) / (2 * d)
        elbow = start + along * line + sqrt(a * a - along * along) * bend.normalized()
        self.aim(upper, elbow)
        self.aim(fore, wrist)

    def palm(self, side, fingers, normal, open_by=.9):
        name = f"hand.{side}"
        rest = self.bones[name].bone.matrix_local.to_3x3()
        to_pose = basis(fingers, normal) @ basis(rest @ Vector((0, 1, 0)), (0, -1, 0)).inverted()
        self.orient(name, (to_pose @ rest).to_quaternion())
        finger_roots = {"index", "middle", "ring", "little", "thumb"}
        for bone in self.bones:
            if bone.name.endswith(f".{side}") and bone.name.split(".")[0].split("_")[0] in finger_roots:
                bone.rotation_quaternion = self.ready[bone.name][1].slerp(
                    Matrix.Identity(3).to_quaternion(), open_by)

    def new(self, clip):
        take = TAKES[clip]
        action = bpy.data.actions.new(take.name)
        action.use_fake_user = True
        action.use_frame_range = True
        action.frame_start, action.frame_end = 1, take.end
        action["fitted_candidate_clip"] = clip
        action["ready_master_sha256"] = SOURCES[take.role][-1]
        action["impact_frame"] = take.beat
        action["fps"] = 24
        for frame, label in take.stages:
            action.pose_markers.new(label).frame = frame
        self.previous = {}
        return action

    def key(self, action, frame, names=None):
        # Single-slot actions can be appended to the pinned rig without a scene.
        self.rig.animation_data.action = action
        if action.slots:
            self.rig.animation_data.action_slot = action.slots[0]
        for b in self.bones if names is None else (self.bones[name] for name in names):
            q = b.rotation_quaternion.copy()
            if b.name in self.previous:
                q.make_compatible(self.previous[b.name])
            b.rotation_quaternion = q
            self.previous[b.name] = q
            for prop in ("location", "rotation_quaternion", "scale"):
                b.keyframe_insert(prop, frame=frame, group=b.name)

    @staticmethod
    def finish(action):
        for curve in action.layers[0].strips[0].channelbag(action.slots[0]).fcurves:
            for key in curve.keyframe_points:
                key.handle_left_type = key.handle_right_type = "AUTO_CLAMPED"


def cover(a):
    t = a.new("keep_your_head_down")
    hand = a.world["hand.R"].to_quaternion()
    # Bank the staff below head height; the last few inches are a short
    # forward touch rather than a wound-up downward blow.
    poses = {
        5: ((-.414, -.21, 1.135), (16, 18, 8), 4, None),
        8: ((-.400, -.26, 1.125), (54, 40, 16), 8, (.32, -.23, 1.15)),
        10: ((-.385, -.29, 1.115), (58, 45, 20), 9, (.31, -.21, 1.18)),
        13: ((-.265, -.46, 1.098), (69, 57, 29), 12, (.275, -.185, 1.22)),
        17: ((-.330, -.37, 1.103), (62, 49, 24), 9, (.29, -.215, 1.17)),
        21: ((-.414, -.242, 1.138), (29, 26, 8), 5, None),
        25: ((-.388, -.164, 1.132), (7, 7, 2), 2, None),
    }
    for f in (1, *poses, 28):
        a.reset()
        if f in poses:
            wrist, staff_turn, lean, free = poses[f]
            a.turn("chest", (lean, -2, 5))
            a.turn("head", (-lean * .45, -3, 6))
            a.arm("R", wrist, (-1, .12, -.48))
            a.orient("hand.R", rotation(staff_turn) @ hand)
            if free:
                a.arm("L", free, (.6, .05, -.65))
                a.palm("L", (.35, -.77, -.18), (0, -.13, -1), .65)
        a.key(t, f)
    a.finish(t)
    return t


def pull(a):
    t = a.new("fitted_pull")
    hand = a.world["hand.R"].to_quaternion()
    bow_line = (bpy.data.objects["Bow_hair_tip"].matrix_world.translation
                - bpy.data.objects["Bow_hair_frog"].matrix_world.translation).normalized()
    poses = {
        5: ((-.060, -.485, 1.354), (.58, -.47, -.44), (4, -3, -5), 3),
        9: ((-.100, -.610, 1.291), (.83, -.51, -.22), (13, 0, -7), 10),
        11: ((-.131, -.580, 1.292), (.82, -.49, -.17), (10, 2, -7), 8),
        14: ((-.465, -.277, 1.310), (.36, -.84, -.31), (-13, -10, -12), -11),
        17: ((-.518, -.202, 1.305), (.20, -.86, -.35), (-17, -10, -14), -16),
        21: ((-.379, -.281, 1.325), (.46, -.57, -.50), (-8, -6, -10), -9),
        25: ((-.182, -.416, 1.420), (.56, .16, -.72), (-2, -2, -3), -2),
    }
    for f in (1, *poses, 29):
        a.reset()
        if f in poses:
            wrist, line, torso, tail = poses[f]
            a.turn("chest", torso)
            a.turn("head", (-torso[0] * .55, -4, -torso[2] * .6))
            a.turn("coat_tail.L", (tail, 3, tail * .42))
            a.turn("coat_tail.R", (tail * .72, -2, tail * .7))
            a.arm("R", wrist, (-.91, .04, -.45))
            a.orient("hand.R", bow_line.rotation_difference(Vector(line)) @ hand)
        a.key(t, f)
    a.finish(t)
    return t


MIX_ARMS = ("upper", "fore")


def send_off(a):
    t = a.new("send_off")
    poses = {
        4: ((-.322, -.215, 1.120), (.277, -.224, 1.151), (1, -1, 1), .3),
        7: ((-.343, -.285, 1.170), (.292, -.323, 1.268), (-3, -1, 4), .75),
        9: ((-.311, -.285, 1.199), (.271, -.325, 1.278), (-6, -2, 5), .9),
        11: ((-.275, -.365, 1.207), (.262, -.419, 1.291), (1, -3, 6), .9),
        13: ((-.183, -.498, 1.252), (.306, -.514, 1.359), (14, 1, 8), .95),
        15: ((-.158, -.493, 1.243), (.313, -.508, 1.350), (16, 1, 8), .95),
        17: ((-.177, -.451, 1.219), (.312, -.496, 1.319), (13, 1, 6), .9),
        22: ((-.311, -.241, 1.101), (.276, -.268, 1.152), (4, 0, 3), .6),
        25: ((-.351, -.159, 1.050), (.247, -.215, 1.108), (1, 0, 1), .2),
    }
    for f in (1, *poses, 28):
        a.reset()
        if f in poses:
            right, left, torso, opening = poses[f]
            a.turn("chest", torso)
            a.turn("head", (-torso[0] * .52, -3, 6))
            for side, wrist, sign in (("R", right, -1), ("L", left, 1)):
                a.arm(side, wrist, (sign, .04, -.75), MIX_ARMS)
                a.palm(side, (sign * .22, -.19, .97), (0, -1, -.15), opening)
        a.key(t, f)
    a.finish(t)
    return t


def hostile_dose(a):
    t = a.new("hostile_dose")
    native = bpy.data.actions["Mixologist | Healing Potion"]
    select(a.scene, a.rig, native, 17)
    hand, prop = a.bones["hand.R"], a.bones["prop.potion"]
    grip = hand.matrix.inverted() @ prop.matrix
    upright_hand = hand.matrix.to_quaternion()
    # The prop bone's local Y is not the actual bottle axis. Use its authored
    # cradle and neck markers; the existing glass wind sits unchanged in grip.
    upright = (bpy.data.objects["Potion neck steady point"].matrix_world.translation
               - bpy.data.objects["Potion base cradle"].matrix_world.translation).normalized()
    pickups = {f: a.snapshot(native, f) for f in (4, 7, 9)}
    for sample in pickups.values():
        # The accepted offer shifts weight through its feet. Borrow its upper
        # pickup only, preserving this candidate's planted lower-body registration.
        for name in a.ready:
            if name == "pelvis" or name.split(".")[0] in {"thigh", "shin", "foot"}:
                sample[name] = a.ready[name]
    poses = {
        11: ((-.132, -.346, 1.180), (.26, -.22, .93), (8, 1, 21)),
        13: ((.310, -.470, 1.240), (.89, -.22, -.40), (16, 25, 53)),
        15: ((.198, -.451, 1.205), (.77, -.49, -.40), (14, 17, 37)),
        17: ((-.116, -.318, 1.113), (.45, -.35, .80), (8, 0, 15)),
        19: ((-.270, -.177, 1.057), (.22, -.14, .96), (4, 0, 7)),
        21: ((-.331, -.151, 1.042), (.15, -.05, .99), (2, 0, 3)),
    }
    for f in (1, *pickups, *poses, 24, 28):
        a.reset(pickups.get(f))
        if f in poses:
            wrist, tilt, torso = poses[f]
            a.turn("chest", torso)
            a.turn("head", (-torso[0] * .48, -3, -torso[2] * .30))
            a.arm("L", (.305, -.012, 1.076), (.85, .20, -.55), MIX_ARMS)
            a.arm("R", wrist, (-1, .06, -.75), MIX_ARMS)
            a.orient("hand.R", upright.rotation_difference(Vector(tilt)) @ upright_hand)
            # Keep the stock grasp fingers from the extended offer.
            for b in a.bones:
                if b.name.endswith(".R") and b.parent and b.name.split(".")[0].split("_")[0] in {
                    "index", "middle", "ring", "little", "thumb"
                }:
                    b.rotation_quaternion = a.grasp[b.name][1]
        a.key(t, f)
    a.finish(t)
    # The vial has no parent constraint in the accepted rig. Key the held
    # transform at half-frame steps so it follows the hand throughout the tip.
    select(a.scene, a.rig, t, 9)
    pickup_grip = hand.matrix.inverted() @ prop.matrix
    a.previous = {}
    carry_frames = tuple(range(18, 43))
    carries = []
    for half in carry_frames:
        f = half / 2
        select(a.scene, a.rig, t, f)
        if f < 11:
            carry = hand.matrix @ pickup_grip.lerp(grip, (f - 9) / 2)
        else:
            carry = hand.matrix @ grip
        if f > 19:
            carry = carry @ Matrix.Scale((21 - f) / 2 if f < 21 else 0.0001, 4)
        carries.append((f, carry))
    for f, carry in carries:
        select(a.scene, a.rig, t, f)
        prop.matrix = carry
        a.key(t, f, [prop.name])
    a.finish(t)
    return t


BUILDERS = {"keep_your_head_down": cover, "fitted_pull": pull, "send_off": send_off, "hostile_dose": hostile_dose}


def load_actions(library, names=None):
    expected = {take.name for take in TAKES.values()}
    with bpy.data.libraries.load(str(library), link=False) as (source, target):
        if set(source.actions) != expected or any(getattr(source, kind) for kind in (
            "objects", "armatures", "meshes", "scenes", "materials", "images", "collections", "libraries",
        )):
            raise ValueError(f"Unexpected content in action library: {library}")
        target.actions = sorted(expected if names is None else names)
    return {action.name: action for action in target.actions}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--scratch", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    output, scratch = args.output.resolve(), args.scratch.resolve()
    if output.suffix != ".blend" or output.exists():
        parser.error("Output must be a new .blend file")
    scratch.mkdir(parents=True, exist_ok=False)
    assert bpy.app.version[:3] == (5, 2, 2)
    partials = []
    for role in SOURCES:
        path, rig_name, ready_name = master(role)
        bpy.ops.wm.open_mainfile(filepath=str(path))
        author = Author(bpy.context.scene, bpy.data.objects[rig_name], bpy.data.actions[ready_name])
        if role == "alchemist":
            author.grasp = author.snapshot(bpy.data.actions["Mixologist | Healing Potion"], 17)
        actions = {BUILDERS[key](author) for key, take in TAKES.items() if take.role == role}
        partial = scratch / f"{role}.blend"
        bpy.data.libraries.write(str(partial), actions, fake_user=True, compress=True)
        partials.append(partial)
        master(role)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    actions = set()
    for partial in partials:
        with bpy.data.libraries.load(str(partial), link=False) as (source, target):
            target.actions = source.actions
        actions.update(target.actions)
    bpy.data.libraries.write(str(output), actions, fake_user=True, compress=True)
    print(f"{output}: {digest(output)}", flush=True)


if __name__ == "__main__":
    main()
