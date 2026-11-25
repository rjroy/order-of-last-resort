"""Build an action-only Blender library from the pinned Knight master."""

import argparse
import hashlib
import math
import sys
from dataclasses import dataclass
from pathlib import Path

import bpy
from bpy_extras.anim_utils import action_get_channelbag_for_slot
from mathutils import Euler, Quaternion, Vector


HERE = Path(__file__).resolve().parent
DONOR = HERE.parent / "knight/knight-guard-blockout.blend"
DONOR_SHA = "0bdf470f4472f2ee269337e458b605bf53be0f36f700e9ebbf8156147e10b45b"
GUARD = "Knight | Wary, plant, cover, settle"
RIG = "Knight_Rig"
SHIELD = "Shield_L_Detachable"


@dataclass(frozen=True)
class Arm:
    wrist: tuple
    elbow_hint: tuple
    roll: float = 0
    wrist_turn: tuple = (0, 0, 0)
    curl: float = 0
    palm_up: bool = False


@dataclass(frozen=True)
class Pose:
    frame: int
    weight: tuple = (0, 0, 0)  # Pelvis offset in model metres.
    chest: tuple = (0, 0, 0)  # Model-space pitch, bank, yaw in degrees.
    head: tuple = (0, 0, 0)
    right: Arm | None = None
    left: Arm | None = None
    cape: tuple = (0, 0, 0)


@dataclass(frozen=True)
class Take:
    label: str
    key_frame: int
    marker: str
    last: int
    poses: tuple
    proof: tuple  # Lead-in, key beat, finish detail.
    control: tuple  # Packaged clip, selected source frames.

    @property
    def name(self):
        return f"Knight | Fitted | {self.label}"


TAKES = {
    "fitted_pull": Take(
        "Pull", 14, "Reel / pull begins", 29,
        (
            Pose(1),
            Pose(5, (0, -.022, -.018), (5, -4, 5), (4, 2, -4),
                 Arm((-.37, -.35, 1.25), (-.61, .01, 1.06), -15, (-8, 2, 4))),
            Pose(10, (0, -.049, -.036), (13, -5, 14), (6, 0, -10),
                 Arm((-.47, -.60, 1.12), (-.59, -.30, .94), -13, (-10, 0, 4), -13)),
            Pose(12, (0, -.049, -.036), (12, -5, 14), (5, 0, -10),
                 Arm((-.47, -.59, 1.14), (-.58, -.29, .95), -10, (-4, 0, 4), 14)),
            Pose(14, (-.028, .034, -.073), (-13, 5, -13), (5, 0, 12),
                 Arm((-.43, -.12, 1.27), (-.68, .21, 1.11), 27, (8, -10, 2), 26),
                 cape=(13, -5, 8)),
            Pose(17, (-.035, .059, -.071), (-16, 6, -19), (8, 0, 13),
                 Arm((-.51, -.045, 1.28), (-.73, .28, 1.10), 27, (10, -10, 4), 24),
                 cape=(16, -7, 13)),
            Pose(22, (-.018, .032, -.034), (-8, 3, -8), (4, 0, 6),
                 Arm((-.34, -.13, 1.15), (-.63, .12, 1.03), 12, (4, -5, 1), 10),
                 cape=(7, -2, 7)),
            Pose(29),
        ), (10, 14, 17), ("rescue_line", (11, 14, 18)),
    ),
    "clear_the_floor": Take(
        "Clear the Floor", 14, "Sweep / outward pushes begin", 30,
        (
            Pose(1),
            Pose(5, (.03, -.01, -.04), (7, 2, -15), (4, -2, 3),
                 Arm((-.24, -.26, 1.16), (-.57, -.03, 1.00)),
                 Arm((.32, -.45, 1.20), (.10, -.28, 1.06), -10)),
            Pose(10, (.014, -.045, -.06), (15, 4, -24), (5, -3, 8),
                 Arm((-.18, -.22, 1.12), (-.53, -.04, 1.00)),
                 Arm((.20, -.53, 1.24), (-.08, -.32, 1.05), -10),
                 cape=(0, 5, 10)),
            Pose(12, (0, -.045, -.065), (15, 1, -10), (6, -1, 3),
                 Arm((-.27, -.38, 1.20), (-.57, -.10, 1.03)),
                 Arm((.46, -.46, 1.31), (.13, -.39, 1.11), -4)),
            Pose(14, (.011, -.066, -.055), (14, -5, 11), (5, 2, -9),
                 Arm((-.69, -.24, 1.29), (-.66, .05, 1.13), -25, (-13, 0, 11), -10),
                 Arm((.72, -.36, 1.39), (.39, -.33, 1.15), 8),
                 cape=(-10, 0, -16)),
            Pose(17, (.024, -.042, -.039), (8, -6, 15), (3, 2, -11),
                 Arm((-.73, -.17, 1.31), (-.65, .06, 1.11), -20, (-10, 0, 7), -9),
                 Arm((.71, -.27, 1.38), (.46, -.31, 1.13), 11),
                 cape=(-8, 0, -20)),
            Pose(23, (.010, -.012, -.020), (3, -3, 6), (0, 1, -5),
                 Arm((-.47, -.20, 1.12), (-.57, .01, 1.06)),
                 Arm((.58, -.21, 1.30), (.29, -.23, 1.13), 8),
                 cape=(-2, 0, -8)),
            Pose(30),
        ), (10, 14, 17), ("guard", (31, 39, 51)),
    ),
    "safety_distance": Take(
        "Safety Distance", 13, "Palm out / friendly push begins", 31,
        (
            Pose(1),
            Pose(5, (0, .017, -.014), (-4, -1, 3), (0, 2, -4),
                 Arm((-.25, -.21, 1.28), (-.57, .05, 1.08), -20, (-6, -5, 5))),
            Pose(9, (0, .009, -.023), (0, -4, 6), (-3, 1, -4),
                 Arm((-.23, -.23, 1.40), (-.53, -.01, 1.11), -25, (9, -10, 7), -12)),
            Pose(13, (0, -.050, -.037), (15, -7, 12), (-5, 1, -9),
                 Arm((-.63, -.40, 1.62), (-.64, -.22, 1.21), -18, curl=-18, palm_up=True),
                 cape=(5, -4, -6)),
            Pose(17, (.005, -.054, -.032), (13, -7, 11), (-3, 1, -8),
                 Arm((-.63, -.41, 1.62), (-.64, -.24, 1.23), -18, curl=-17, palm_up=True),
                 cape=(6, -4, -6)),
            Pose(22, (0, -.023, -.020), (6, -3, 5), (0, 1, -5),
                 Arm((-.43, -.32, 1.40), (-.61, -.10, 1.12), -11, (15, -4, 0), -8, True)),
            Pose(26, (0, 0, -.007), (2, 0, 2), (0, 0, -2),
                 Arm((-.28, -.28, 1.22), (-.52, -.03, 1.12))),
            Pose(31),
        ), (9, 13, 17), ("rescue_line", (8, 14, 22)),
    ),
    "lend_a_shield": Take(
        "Lend a Shield", 18, "Release / shield handoff", 32,
        (
            Pose(1),
            Pose(5, (0, -.009, -.017), (4, 0, 4), (5, 0, -6),
                 Arm((-.18, -.31, 1.17), (-.55, .02, 1.03)),
                 Arm((.40, -.26, 1.20), (.15, -.25, 1.10), -5)),
            Pose(10, (0, -.028, -.036), (10, 0, 6), (5, 0, -6),
                 Arm((-.115, -.40, 1.14), (-.48, -.11, 1.02), -12, (4, 0, 0)),
                 Arm((.35, -.46, 1.19), (.10, -.33, 1.12), -13)),
            Pose(14, (0, -.036, -.047), (13, 0, 6), (4, 0, -4),
                 Arm((-.12, -.36, 1.105), (-.45, -.14, 1.01), -12, (5, 0, 0)),
                 Arm((.36, -.53, 1.21), (.11, -.45, 1.13), -16)),
            Pose(17, (0, -.053, -.055), (15, 0, 6), (2, 0, -4),
                 Arm((-.08, -.44, 1.11), (-.45, -.16, 1.00), -14, (7, 0, 0)),
                 Arm((.39, -.59, 1.20), (.17, -.48, 1.09), -18)),
            Pose(18, (0, -.055, -.055), (15, 0, 6), (0, 0, -4),
                 Arm((-.05, -.59, 1.18), (-.45, -.19, 1.02), -14, (12, 0, 0), -13),
                 Arm((.40, -.61, 1.20), (.17, -.49, 1.09), -18, (3, -7, 1), -12)),
            Pose(21, (0, -.052, -.045), (13, 0, 5), (-2, 0, -3),
                 Arm((-.13, -.51, 1.20), (-.47, -.13, 1.06), -13, (10, 0, 0), -10),
                 Arm((.46, -.54, 1.23), (.18, -.47, 1.10), -13, (0, -9, 0), -10)),
            Pose(26, (0, -.019, -.019), (6, 0, 4), (-2, 0, -3),
                 Arm((-.25, -.30, 1.13), (-.49, -.02, 1.08)),
                 Arm((.47, -.36, 1.24), (.24, -.29, 1.13), -3)),
            Pose(32),
        ), (14, 18, 26), ("shield_throw", (12, 16, 23)),
    ),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_donor():
    assert bpy.app.version[:3] == (5, 2, 2)
    assert Path(bpy.data.filepath).resolve() == DONOR and digest(DONOR) == DONOR_SHA
    assert not bpy.data.libraries
    assert bpy.context.scene.render.fps == 24


def select(rig, action):
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]


def radians(angles):
    return tuple(map(math.radians, angles))


def turn(bone, angles):
    matrix = bone.matrix.copy()
    turned = (Euler(radians(angles)).to_matrix() @ matrix.to_3x3()).to_4x4()
    turned.translation = matrix.translation
    bone.matrix = turned


def orient(bone, destination, roll=0):
    matrix = bone.matrix.copy()
    direction = (Vector(destination) - matrix.translation).normalized()
    swing = (bone.tail - bone.head).normalized().rotation_difference(direction)
    result = (Quaternion(direction, math.radians(roll)) @ swing @
              matrix.to_quaternion()).to_matrix().to_4x4()
    result.translation = matrix.translation
    bone.matrix = result
    bpy.context.view_layer.update()


def elbow_point(origin, target, hint, a, b):
    """Place the joint in the plane from origin toward the editable hinge hint."""
    axis = (Vector(target) - origin).normalized()
    distance = (Vector(target) - origin).length
    distance = min(max(distance, abs(a - b) + .001), a + b - .009)
    along = (a*a - b*b + distance*distance) / (2*distance)
    plane = Vector(hint) - origin
    bend = (plane - axis * plane.dot(axis)).normalized()
    return origin + axis * along + bend * math.sqrt(a*a - along*along), origin + axis * distance


def aim_pair(upper, lower, target, hint, roll=0):
    hinge, end = elbow_point(upper.head, target, hint, upper.length, lower.length)
    orient(upper, hinge)
    orient(lower, end, roll)


def plant_feet(bones, ready):
    for side in ("R", "L"):
        boot = f"boot.{side}"
        shin = f"shin.{side}"
        aim_pair(bones[f"thigh.{side}"], bones[shin], ready[boot].translation, ready[shin].translation)
        bones[boot].matrix = ready[boot]
        bpy.context.view_layer.update()


def shape_pose(rig, pose, ready):
    bones = rig.pose.bones
    if not any((any(pose.weight), any(pose.chest), any(pose.head), pose.right, pose.left, any(pose.cape))):
        return
    pelvis = bones["pelvis"]
    moved = pelvis.matrix.copy()
    moved.translation += Vector(pose.weight)
    pelvis.matrix = moved
    bpy.context.view_layer.update()
    for name, angles in (("chest", pose.chest), ("head", pose.head), ("mantle", pose.cape)):
        if any(angles):
            turn(bones[name], angles)
            bpy.context.view_layer.update()
    for side, arm in (("R", pose.right), ("L", pose.left)):
        if arm:
            aim_pair(bones[f"upper_arm.{side}"], bones[f"forearm.{side}"],
                     arm.wrist, arm.elbow_hint, arm.roll)
            hand = bones[f"hand.{side}"]
            if arm.palm_up:
                orient(hand, hand.head + Vector((-.15, -.10, .90)), -15)
            if any(arm.wrist_turn):
                turn(hand, arm.wrist_turn)
            if arm.curl:
                finger = bones[f"fingers.{side}"]
                finger.rotation_quaternion @= Quaternion((1, 0, 0), math.radians(arm.curl))
            bpy.context.view_layer.update()
    plant_feet(bones, ready)


def record(bones, frame, previous):
    for p in bones:
        assert p.rotation_mode == "QUATERNION"
        if p.name in previous:
            p.rotation_quaternion.make_compatible(previous[p.name])
        previous[p.name] = p.rotation_quaternion.copy()
        for prop in ("location", "rotation_quaternion", "scale"):
            p.keyframe_insert(prop, frame=frame, group=p.name)


def pin_inbetweens(take, scene, rig, action, ready):
    """Sample the eased body first; retarget only the legs to the planted boots."""
    legs = [p for p in rig.pose.bones if p.name.split(".")[0] in {"thigh", "shin", "boot"}]
    keyed_frames = {pose.frame for pose in take.poses}
    body_samples = {}
    for frame in range(2, take.last):
        if frame not in keyed_frames:
            scene.frame_set(frame)
            body_samples[frame] = [p.matrix_basis.copy() for p in rig.pose.bones]
    for frame, matrices in body_samples.items():
        select(rig, action)
        scene.frame_set(frame)
        hints = {p.name: p.rotation_quaternion.copy() for p in legs}
        rig.animation_data.action = None
        for p, basis in zip(rig.pose.bones, matrices, strict=True):
            p.matrix_basis = basis
        bpy.context.view_layer.update()
        plant_feet(rig.pose.bones, ready)
        select(rig, action)
        record(legs, frame, hints)


def create_take(take, scene, rig, donor):
    select(rig, donor)
    scene.frame_set(8)
    ready = {p.name: p.matrix.copy() for p in rig.pose.bones}
    channels = {p.name: p.matrix_basis.copy() for p in rig.pose.bones}
    action = bpy.data.actions.new(take.name)
    action.use_fake_user = True
    action.slots.new("OBJECT", RIG)
    action.use_frame_range = True
    action.frame_start = 1
    action.frame_end = take.last
    action.pose_markers.new(take.marker).frame = take.key_frame
    action["donor_sha256"] = DONOR_SHA
    action["fps"] = 24
    if take.label == "Lend a Shield":
        action["prop_release_frame"] = take.key_frame
        action["prop_root"] = SHIELD
    previous = {}
    for pose in take.poses:
        rig.animation_data.action = None
        scene.frame_set(pose.frame)
        for p in rig.pose.bones:
            p.matrix_basis = channels[p.name]
        bpy.context.view_layer.update()
        shape_pose(rig, pose, ready)
        select(rig, action)
        record(rig.pose.bones, pose.frame, previous)
    pin_inbetweens(take, scene, rig, action, ready)
    for curve in action_get_channelbag_for_slot(action, action.slots[0]).fcurves:
        for point in curve.keyframe_points:
            point.handle_left_type = point.handle_right_type = "AUTO_CLAMPED"
    return action


def build(out):
    require_donor()
    assert out.suffix == ".blend" and not out.exists() and out.resolve() != DONOR, out
    scene = bpy.context.scene
    rig = bpy.data.objects[RIG]
    donor = bpy.data.actions[GUARD]
    actions = {create_take(take, scene, rig, donor) for take in TAKES.values()}
    bpy.data.libraries.write(str(out), actions, path_remap="NONE", compress=True)
    assert digest(DONOR) == DONOR_SHA
    print(f"Saved {len(actions)} editable Actions only to {out}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    build(arguments.output.resolve())
