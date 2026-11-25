"""Blender background: derive a separate editable Blender file, never the master."""

import hashlib
from math import radians, sqrt
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from choreography import BODY, CUES, FEET, HANDS

TOOLS = HERE.parents[6] / "games/company-of-unlikely-heroes/tools/cast"
sys.path.insert(0, str(TOOLS))
from rogue_vial import GRIP, GRIP_LOCAL, vial_for

MASTER = HERE.parent / "rogue/rogue-blockout.blend"
MASTER_SHA = "99d4607ab9e9792c51e15ae90d11d412973e98e3e17f481b5c976fbac02cfbb1"
READY = "Rogue | Ready / Retreat"
PROPS = ("cape_flash", "cape_usher", "bitter_vial", "wire_punch")
VIAL = "Try This | cordial vial"
HELD_PUNCH = "Try This | held ticket punch"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def between(rows, frame, smooth=True):
    for a, b in zip(rows, rows[1:]):
        if frame <= b[0]:
            t = (frame - a[0]) / (b[0] - a[0])
            if smooth:
                t = t*t*(3 - 2*t)
            return a, b, t
    raise ValueError(frame)


def blend(a, b, t):
    if isinstance(a, (Vector, tuple)):
        return Vector(a).lerp(Vector(b), t)
    return a + (b-a)*t


def score(rows, frame):
    a, b, t = between(rows, frame)
    return [blend(x, y, t) for x, y in zip(a[1:], b[1:])]


def set_pose_rotation(bone, q):
    # Preserve the current head; do not bake new anatomical bone translates.
    mat = q.to_matrix().to_4x4()
    mat.translation = bone.head
    bone.matrix = mat
    bpy.context.view_layer.update()


def solve(top, mid, destination, bend_hint, weight=1.):
    """Two-link FK solution with a stable elbow/knee plane and native bone lengths."""
    start = top.head.copy()
    target = destination - start
    axis = target.normalized()
    first, second = top.length, mid.length
    d = min(max(target.length, abs(first-second)+.001), first+second-.001)
    along = (first**2 - second**2 + d*d) / (2*d)
    perp = (bend_hint - axis*bend_hint.dot(axis)).normalized()
    elbow = start + axis*along + perp*sqrt(max(0, first**2-along**2))
    native = (top.tail - start).normalized()
    aimed = native.rotation_difference((elbow-start).normalized()) @ top.matrix.to_quaternion()
    set_pose_rotation(top, top.matrix.to_quaternion().slerp(aimed, weight))
    native = (mid.tail-mid.head).normalized()
    aimed = native.rotation_difference((start+axis*d-mid.head).normalized()) @ mid.matrix.to_quaternion()
    set_pose_rotation(mid, mid.matrix.to_quaternion().slerp(aimed, weight))


def rig_vector(bone, axis, degrees):
    set_pose_rotation(bone, Quaternion(axis, radians(degrees)) @ bone.matrix.to_quaternion())


def switched_scale(obj, rig, prop, expression):
    for axis in range(3):
        d = obj.driver_add("scale", axis).driver
        d.type = "SCRIPTED"
        d.expression = expression
        v = d.variables.new()
        v.name, v.type = "show", "SINGLE_PROP"
        v.targets[0].id, v.targets[0].data_path = rig, f'["{prop}"]'


def dress(scene, rig):
    for prop_name in PROPS[2:]:
        rig[prop_name] = 0.
        rig.id_properties_ui(prop_name).update(min=0, max=1)
    vial = vial_for(scene)
    vial.name = VIAL
    vial.parent, vial.parent_type, vial.parent_bone = rig, "BONE", GRIP
    # Blender's bone-parent origin is the tail, while GRIP_LOCAL uses the head.
    grip = GRIP_LOCAL.copy()
    grip.translation.y -= rig.pose.bones[GRIP].length
    vial.matrix_basis = grip
    vial.hide_render = False
    switched_scale(vial, rig, "bitter_vial", "max(show * 1.20, 0.00001)")

    # Use the Dodger's own tool, without recutting its mesh or adding a blade.
    # Only the hand version is visible while the duplicate is out of the belt.
    belt = bpy.data.objects["Punch_R_Detachable"]
    held = bpy.data.objects.new(HELD_PUNCH, None)
    scene.collection.objects.link(held)
    held.parent, held.parent_type, held.parent_bone = rig, "BONE", "hand.R"
    held.matrix_basis = (
        Matrix.Translation((.015,-.056,-.042))
        @ Matrix.Rotation(radians(79), 4, "X")
    )
    for part in belt.children:
        if "leather hanger" in part.name:
            continue
        copy = part.copy()
        copy.name = "Hand " + part.name
        scene.collection.objects.link(copy)
        copy.parent = held
        copy.matrix_parent_inverse = Matrix.Identity(4)
        copy.matrix_basis = part.matrix_local.copy()
    switched_scale(held, rig, "wire_punch", "max(show, 0.00001)")
    switched_scale(belt, rig, "wire_punch", "max(1 - show, 0.00001)")


def build(output):
    if Path(bpy.data.filepath).resolve() != MASTER or digest(MASTER) != MASTER_SHA:
        raise ValueError("Open the SHA-pinned Rogue master, not a different source.")
    if output.suffix != ".blend" or output.exists() or not output.parent.is_dir():
        raise ValueError("Choose an unused .blend path in an existing staging directory.")

    scene, rig = bpy.context.scene, bpy.data.objects["Rogue_Rig"]
    anim, bones = rig.animation_data, rig.pose.bones
    scene.frame_set(1)
    # Read the accepted baseline before disconnecting its action.
    ready_action = anim.action
    assert ready_action.name == READY and scene.render.fps == 24
    ready = {b.name: b.matrix_basis.copy() for b in bones}
    world = {b.name: b.matrix.copy() for b in bones}
    dress(scene, rig)
    anim.action = None

    for clip, cue in CUES.items():
        action = bpy.data.actions.new("Rogue | " + cue["title"])
        action.use_fake_user = True
        slot = action.slots.new(id_type="OBJECT", name=rig.name)
        anim.action, anim.action_slot = action, slot
        for label, frame in cue["markers"].items():
            action.pose_markers.new(label).frame = frame
        previous = {}

        # Half-frame FK samples keep foot anchors and curved reach paths stable.
        # There are no live IK constraints or dependencies in the saved file.
        for index in range(2, 2*cue["end"]+1):
            f = index/2
            for b in bones:
                b.matrix_basis = ready[b.name]
            bpy.context.view_layer.update()
            rig["cape_usher"], rig["cape_flash"] = 0., 0.
            for property_name, label in (("bitter_vial","vial_visible"), ("wire_punch","punch_in_hand")):
                start, stop = cue.get(label, (-1,-1))
                rig[property_name] = float(start <= f <= stop)
            if f not in (1, cue["end"]):
                shift, chest, head, flash = score(BODY[clip], f)
                pelvis = bones["pelvis"]
                m = pelvis.matrix.copy()
                m.translation += shift
                pelvis.matrix = m
                bpy.context.view_layer.update()
                rig_vector(bones["chest"], (1,0,0), chest)
                rig_vector(bones["head"], (1,0,0), head)
                rig_vector(bones["cap_tip"], (1,0,0), -.22*head)
                rig["cape_flash"] = flash
                feet = score(FEET, f) if clip == "clear_jump" else [(0,0,0), (0,0,0), 0., 0.]
                for side, delta, pitch in zip("LR", feet[:2], feet[2:]):
                    foot = bones["foot."+side]
                    thigh, shin = (bones[part+"."+side] for part in ("thigh","shin"))
                    solve(thigh, shin, world[foot.name].translation+Vector(delta), Vector((0,-1,0)))
                    set_pose_rotation(foot, Quaternion((1,0,0), radians(pitch)) @ world[foot.name].to_quaternion())

                for side, rows in HANDS[clip].items():
                    a, b, t = between(rows, f)
                    hand = bones["hand."+side]
                    up, mid = (bones[part+"."+side] for part in ("upper_arm","forearm"))
                    base_dir = world[hand.name].to_3x3() @ Vector((0,1,0))
                    p = blend(a[1] or world[hand.name].translation, b[1] or world[hand.name].translation, t)
                    y = blend(a[2] or base_dir, b[2] or base_dir, t).normalized()
                    roll = blend(a[3], b[3], t)
                    w = blend(float(a[1] is not None), float(b[1] is not None), t)
                    bend = Vector((-.82 if side == "R" else .82,.15,-.55))
                    solve(up, mid, p, bend, w)
                    q = Quaternion(y, radians(roll)) @ base_dir.rotation_difference(y) @ world[hand.name].to_quaternion()
                    set_pose_rotation(hand, hand.matrix.to_quaternion().slerp(q, w))

            for b in bones:
                q = b.rotation_quaternion.copy()
                if b.name in previous and q.dot(previous[b.name]) < 0:
                    q.negate()
                    b.rotation_quaternion = q
                previous[b.name] = q
                for prop_name in ("location", "rotation_quaternion", "scale"):
                    b.keyframe_insert(prop_name, frame=f, group=b.name)
            for prop_name in PROPS:
                rig.keyframe_insert(f'["{prop_name}"]', frame=f, group="Stage")

        from bpy_extras.anim_utils import action_get_channelbag_for_slot
        for fc in action_get_channelbag_for_slot(action, slot).fcurves:
            for key in fc.keyframe_points:
                key.interpolation = "CONSTANT" if fc.data_path in ('["bitter_vial"]','["wire_punch"]') else "LINEAR"

    anim.action = bpy.data.actions["Rogue | It Was Me"]
    scene.frame_start, scene.frame_end = 1, CUES["it_was_me"]["end"]
    scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(output), compress=True)
    assert output.is_file() and digest(MASTER) == MASTER_SHA


if __name__ == "__main__":
    build(Path(sys.argv[sys.argv.index("--")+1]).resolve())
