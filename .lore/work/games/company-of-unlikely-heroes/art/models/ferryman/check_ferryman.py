"""Check native rig, not the consumer, independently from the review cameras."""

import bpy
from mathutils import Matrix

s = bpy.context.scene
r = bpy.data.objects["Ferryman_Rig"]
prop = bpy.data.objects["Oar_R_Detachable"]
assert prop.parent == r and prop.parent_bone == "oar_socket" and len(prop.children) == 4
assert not bpy.data.libraries and not any(i.source == "FILE" for i in bpy.data.images)


def at(a, f):
    r.animation_data.action = bpy.data.actions["Ferryman | " + a]
    s.frame_set(f)


def dist(a, b):
    return max(abs(v - w) for x, y in zip(a, b) for v, w in zip(x, y))


def pose():
    return [b.matrix.copy() for b in r.pose.bones]


at("Neutral T", 1)
assert max(dist(b.matrix, b.bone.matrix_local) for b in r.pose.bones) < 1e-5
at("Ready", 1)
ready = pose()
rel = r.pose.bones["oar_socket"].matrix.inverted() @ prop.matrix_world
for a, f in [
    ("Ready", 33),
    ("Cautious Step", 1),
    ("Cautious Step", 39),
    ("Safe Bank", 1),
    ("Flinch", 23),
    ("Recover", 24),
]:
    at(a, f)
    assert max(dist(x, y) for x, y in zip(pose(), ready)) < 2e-5
at("Down", 31)
down = pose()
at("Recover", 1)
assert max(dist(x, y) for x, y in zip(pose(), down)) < 2e-5
for act in bpy.data.actions:
    r.animation_data.action = act
    for f in range(int(act.frame_range[0]), int(act.frame_range[1]) + 1):
        s.frame_set(f)
        assert (
            dist(rel, r.pose.bones["oar_socket"].matrix.inverted() @ prop.matrix_world)
            < 2e-5
        )
at("Safe Bank", 15)
lift = r.pose.bones["sleeve.L"].head.z
at("Safe Bank", 34)
drop = lift - r.pose.bones["sleeve.L"].head.z
assert drop > 0.02
print("Exhale shoulder drop (m)", drop)
o = bpy.data.objects["Ash oar • broad spoon to rounded handle"]
for a, f in [("Ready", 1), ("Cautious Step", 13), ("Safe Bank", 34), ("Down", 31)]:
    at(a, f)
    dg = bpy.context.evaluated_depsgraph_get()
    soles = [
        min(
            (ob.evaluated_get(dg).matrix_world @ v.co).z
            for v in ob.evaluated_get(dg).data.vertices
        )
        for ob in s.objects
        if ob.name.startswith("Dark welt")
    ]
    print(
        "GROUND",
        a,
        f,
        "blade",
        round(min((o.matrix_world @ v.co).z for v in o.data.vertices), 4),
        "soles",
        soles,
    )
print("All native Ferryman rig checks passed.")
