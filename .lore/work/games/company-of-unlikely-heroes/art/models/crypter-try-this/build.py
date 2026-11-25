"""Derive editable action-only candidates from SHA-pinned cast sources."""

import hashlib
import json
from math import atan2, radians, sqrt
from pathlib import Path
import sys

import bpy
from mathutils import Euler, Quaternion, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from score import CLIPS, LOWER, OWNER, READY, RIGS

TOOLS = HERE.parents[6] / "games/company-of-unlikely-heroes/tools/cast"
MASTERS = json.loads((TOOLS / "masters.json").read_text())
FLOOR_WORDS = ("review ground", "review floor", "studio floor", "ground • review", "paper ground", "shadow ground")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def body_surface(obj):
    return obj.type in {"MESH", "CURVE"} and not obj.hide_render and not any(
        word in obj.name.lower() for word in FLOOR_WORDS
    )


def limits(scene):
    dg = bpy.context.evaluated_depsgraph_get()
    lo, hi = [float("inf")]*3, [float("-inf")]*3
    for original in scene.objects:
        if not body_surface(original):
            continue
        o = original.evaluated_get(dg)
        # Some of the native curve objects have Blender's unset (-1,-1,-1)
        # bounding box. Their evaluated render geometry is valid.
        mesh = o.to_mesh() if o.type == "CURVE" else o.data
        try:
            m = o.matrix_world
            for v in mesh.vertices:
                for i, q in enumerate(m @ v.co):
                    if q < lo[i]:
                        lo[i] = q
                    if q > hi[i]:
                        hi[i] = q
        finally:
            if o.type == "CURVE":
                o.to_mesh_clear()
    return tuple(zip(lo,hi))


def rotation(bone, q):
    m = q.to_matrix().to_4x4()
    m.translation = bone.head
    bone.matrix = m
    bpy.context.view_layer.update()


def aim(bone, direction):
    forward = (bone.tail - bone.head).normalized()
    dest = Vector(direction).normalized()
    rotation(bone, forward.rotation_difference(dest) @ bone.matrix.to_quaternion())


def solve(upper, lower, wrist, bend_hint):
    start = upper.head.copy()
    delta = Vector(wrist) - start
    axis = delta.normalized()
    a, b = upper.length, lower.length
    d = min(max(delta.length, abs(a-b)+.001), a+b-.001)
    along = (a*a - b*b + d*d)/(2*d)
    hint = Vector(bend_hint)
    out = (hint - axis*hint.dot(axis)).normalized()
    elbow = start + axis*along + out*sqrt(max(0., a*a - along*along))
    aim(upper, elbow-start)
    aim(lower, start + axis*d - lower.head)


def turn(bones, name, angles):
    bone = bones[name]
    q = Euler(tuple(map(radians, angles))).to_quaternion()
    rotation(bone, q @ bone.matrix.to_quaternion())


def shift(bone, delta):
    m = bone.matrix.copy()
    m.translation += Vector(delta)
    bone.matrix = m
    bpy.context.view_layer.update()


def span(rows, f):
    for a, b in zip(rows, rows[1:]):
        if f <= b[0]:
            t = (f-a[0])/(b[0]-a[0])
            return a, b, t*t*(3-2*t)
    raise ValueError(f)


def owner(clip, f, bones, native):
    a, b, t = span(OWNER[clip], f)
    if (f in (OWNER[clip][0][0], OWNER[clip][-1][0])):
        return
    turn(bones, "chest", ((1-t)*a[1]+t*b[1], 0, 0))
    turn(bones, "head", ((1-t)*a[2]+t*b[2], 0, 0))
    base = native["hand.L"].translation
    wrist = Vector(a[3] or base).lerp(Vector(b[3] or base), t)
    solve(bones["upper_arm.L"], bones["forearm.L"], wrist, (.7, .14, -1))
    g = min(1., (f-1)/5, (OWNER[clip][-1][0]-f)/6)
    hand_paths = {
        "recall": ((.62, -.45, .28), (.05, -.3, .9)),
        "hush": ((.68, -.8, -.04), (.6, -.7, -.25)),
        "stay_close": ((.93, -.48, .17), (.93, -.48, .17)),
    }
    d1, d2 = map(Vector, hand_paths[clip])
    mix = min(1., max(0., (f-9)/8))
    hand = bones["hand.L"]
    current = (hand.tail-hand.head).normalized()
    aim(hand, current.lerp(d1.lerp(d2, mix).normalized(), g))
    # Open the four fingers into a readable single mass; on Recall pull the
    # wrist back before refolding. Keep the bell side untouched by hand posing.
    for finger in ("Index", "Middle", "Ring", "Little"):
        tip = bones[f"{finger}_tip.L"]
        base = bones[f"{finger}.L"]
        longitudinal = (base.tail-base.head).normalized()
        aim(tip, (tip.tail-tip.head).normalized().lerp(longitudinal, .8*g))


def skeleton(f, bones):
    t = (17-f)/16
    w = t*t*(3-2*t)
    turn(bones, "chest", (15*w, -5*w, 0))
    turn(bones, "head", (16*w, 0, -5*w))
    turn(bones, "upper_arm.L", (5*w, 0, -7*w))
    turn(bones, "upper_arm.R", (2*w, 0, 6*w))
    turn(bones, "scarf.long", (-13*w, 3*w, 2*w))


def zombie(f, bones, native, scene, floor):
    if f == 1:
        return
    a, b, t = span(LOWER, f)
    shift(bones["pelvis"], Vector(a[1]).lerp(Vector(b[1]), t))
    for bone in bones:
        if bone.name in a[2] or bone.name in b[2]:
            turn(bones, bone.name, Vector(a[2].get(bone.name, (0,0,0))).lerp(
                Vector(b[2].get(bone.name, (0,0,0))), t))
    if f < 15:
        w = max(0, min(1., (15-f)/4))
        for side in "LR":
            foot = bones["foot."+side]
            dest = foot.head.lerp(native[foot.name].translation, w)
            solve(bones["thigh."+side], bones["shin."+side], dest, (0,-1,0))
            rotation(foot, foot.matrix.to_quaternion().slerp(native[foot.name].to_quaternion(), w))
    if f >= 17:
        t = min(1., (f-17)/7)
        w = t*t*(3-2*t)
        # Stow the weighted gift alongside the chest before settling. A wrist
        # hanging below the shoulder would hold the entire body off the floor.
        # Relax the boots alongside one another instead of kicking up.
        for name, direction in (
            ("upper_arm.R", (.30,-.90,-.03)), ("forearm.R", (-.50,-.80,.13)),
            ("hand.R", (-.74,-.30,.28)),
            ("thigh.R", (.91,-.31,.02)), ("shin.R", (.91,.40,-.07)),
            ("foot.R", (.40,-.92,0)),
            ("thigh.L", (.91,-.16,-.14)), ("shin.L", (.90,.4,-.16)),
            ("foot.L", (.30,-.95,-.07)),
            ("upper_arm.L", (.42,-.80,-.45)), ("forearm.L", (-.42,-.72,-.37)),
            ("hand.L", (-.42,-.81,.10)),
        ):
            b = bones[name]
            aim(b, (b.tail-b.head).normalized().lerp(Vector(direction).normalized(),w))
        # Turn the gripped daisy upward as a whole, without altering the prop
        # relationship or keying a release. Aim the stem around the wrist's axis.
        hand = bones["hand.R"]
        axis = (hand.tail-hand.head).normalized()
        flower = bpy.data.objects["Daisy | floret cushion"].evaluated_get(
            bpy.context.evaluated_depsgraph_get())
        mesh = flower.to_mesh()
        center = flower.matrix_world @ (sum((p.co for p in mesh.vertices), Vector())/len(mesh.vertices))
        flower.to_mesh_clear()
        stem = center - hand.head
        start = (stem-axis*stem.dot(axis)).normalized()
        up = Vector((0,0,1))
        target = (up-axis*up.dot(axis)).normalized()
        angle = atan2(axis.dot(start.cross(target)), start.dot(target))
        rotation(hand, Quaternion(axis, angle*w) @ hand.matrix.to_quaternion())
    now = limits(scene)[2][0]
    if now < floor or f >= 18:
        # Use the actual evaluated body envelope for ground contact. This is
        # baked FK, not runtime ground simulation or an impact effect.
        shift(bones["pelvis"], (0, 0, floor-now))


def build(role, output):
    source = HERE.parents[1] / MASTERS[role]["source"]
    assert digest(source) == MASTERS[role]["sha256"], source
    assert output.suffix == ".blend" and output.parent.is_dir() and not output.exists()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    scene = bpy.context.scene
    rig = bpy.data.objects[RIGS[role]+"_Rig"]
    anim, bones = rig.animation_data, rig.pose.bones
    assert anim.action.name == f"{RIGS[role]} | {READY[role]}" and scene.render.fps == 24
    assert bpy.app.version[:3] == (5, 2, 2) and not bpy.data.libraries and not anim.nla_tracks
    scene.frame_set(1)
    ready = {b.name: b.matrix_basis.copy() for b in bones}
    native = {b.name: b.matrix.copy() for b in bones}
    floor = limits(scene)[2][0]
    stock = anim.action
    stock_slot = anim.action_slot
    for action in bpy.data.actions:
        action.use_fake_user = True
    for clip, (end, markers) in CLIPS[role].items():
        anim.action = None
        action = bpy.data.actions.new(f"Try This | {clip}")
        action.use_fake_user = True
        anim.action = action
        anim.action_slot = action.slots.new(id_type="OBJECT", name=rig.name)
        for label, frame in markers.items():
            action.pose_markers.new(label).frame = frame
        last = {}
        for step in range(2, 2*end+1):
            f = step/2
            for b in bones:
                b.matrix_basis = ready[b.name]
            bpy.context.view_layer.update()
            if role == "necromancer":
                owner(clip, f, bones, native)
            elif role == "skeleton":
                skeleton(f, bones)
            else:
                zombie(f, bones, native, scene, floor)
            for b in bones:
                assert b.rotation_mode == "QUATERNION", b.name
                q = b.rotation_quaternion.copy()
                if b.name in last:
                    q.make_compatible(last[b.name])
                b.rotation_quaternion = last[b.name] = q
                for channel in ("location", "rotation_quaternion", "scale"):
                    b.keyframe_insert(data_path=channel, frame=f, group=b.name)
        for curve in action.layers[0].strips[0].channelbag(anim.action_slot).fcurves:
            for key in curve.keyframe_points:
                key.interpolation = "LINEAR"
    anim.action, anim.action_slot = stock, stock_slot
    scene.frame_set(1)
    assert digest(source) == MASTERS[role]["sha256"]
    bpy.ops.wm.save_as_mainfile(filepath=str(output), compress=True)
    print(f"{role}: saved {output}, sha256={digest(output)}")


if __name__ == "__main__":
    role, output = sys.argv[sys.argv.index("--")+1:]
    build(role, Path(output).resolve())
