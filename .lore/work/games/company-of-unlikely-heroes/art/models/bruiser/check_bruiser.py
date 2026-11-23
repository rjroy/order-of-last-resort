"""Reopen checks for source bind, grip, registration, feet, poses and action endpoints."""

import bpy, math
from mathutils import Vector as V

s = bpy.context.scene
r = bpy.data.objects["Bruiser_Rig"]
prop = bpy.data.objects["Maul_Detachable"]
assert prop.parent_bone == "maul" and prop.parent == r and not bpy.data.libraries
assert not any(i.source == "FILE" for i in bpy.data.images)
pb = r.pose.bones
acts = {a.name.split(" | ")[1]: a for a in bpy.data.actions}
assert set(acts) == {"Neutral T", "Ready", "Trudge", "Heavy Strike", "Hit", "Down"}


def at(name, f):
    r.animation_data.action = acts[name]
    s.frame_set(f)


def pose():
    return [p.matrix.copy() for p in pb]


def diff(a, b):
    return max(
        abs(u - v)
        for m, n in zip(a, b)
        for row, col in zip(m, n)
        for u, v in zip(row, col)
    )


at("Neutral T", 1)
assert diff(pose(), [p.bone.matrix_local for p in pb]) < 1e-5
at("Ready", 1)
ready = pose()
for name, f in [("Ready", 37), ("Trudge", 29), ("Heavy Strike", 42), ("Hit", 17)]:
    at(name, f)
    assert diff(pose(), ready) < 1e-5
at("Down", 21)
held = pose()
at("Down", 29)
assert diff(pose(), held) < 1e-5
maxgap = (0, "", 0, "")
minsole = 10
count = 0
for name, a in acts.items():
    if name == "Neutral T":
        continue
    for f in range(1, int(a.frame_range[1]) + 1):
        at(name, f)
        count += 1
        assert pb["root"].head.length < 1e-5
        for side, t in [(-1, "R"), (1, "L")]:
            p = pb["fist." + t]
            target = prop.matrix_world @ V((side * 0.153, 0, 1.50))
            palm = (p.matrix @ p.bone.matrix_local.inverted()) @ V(
                (side * 1.046, -0.048, 1.51)
            )
            gap = (palm - target).length
            maxgap = max(maxgap, (gap, name, f, t))
            sole = bpy.data.objects["Hobnailed sole " + t]
            bt = pb["boot." + t]
            mat = bt.matrix @ bt.bone.matrix_local.inverted()
            minsole = min(minsole, min((mat @ v.co).z for v in sole.data.vertices))
print(
    "Frame checks:",
    count,
    "max grip center error",
    maxgap,
    "lowest boot sole (m)",
    minsole,
)
assert minsole > -0.002
assert maxgap[0] < 0.001
at("Heavy Strike", 15)
crest = (prop.matrix_world @ V((0.637, 0, 1.50))).z
at("Heavy Strike", 21)
follow = (prop.matrix_world @ V((0.637, 0, 1.50))).z
assert crest - follow > 1.1
print("Maul face center height at load and follow-through (m):", crest, follow)
at("Trudge", 8)
heel = pb["boot.L"].head.z
assert heel > 0.27
print("Leading ankle at trudge lift (m):", heel)
print("Native Bruiser checks passed.")
