"""Reopen the saved candidate in Blender, check its stock performances and render read-only proofs."""

import bpy, sys, json
from pathlib import Path
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

S = bpy.context.scene
rig = next(o for o in S.objects if o.type == "ARMATURE")
actor = "frontier_war_drummer"
out = Path(sys.argv[sys.argv.index("--") + 1])
out.mkdir(exist_ok=True, parents=True)
check_only = "--check-only" in sys.argv
peaks = {
    "Neutral": 1,
    "Ready": 1,
    "Hit": 4,
    "Defeat": 24,
    "Reserve arrival": 6,
    "War drum pulse": 14,
}
assert set(peaks) == set(bpy.data.actions.keys())
assert not bpy.data.libraries and not bpy.data.images and S.render.fps == 24
objs = [o for o in S.objects if o.type == "MESH"]
assert all(
    o.parent == rig and o.parent_type == "BONE" and o.parent_bone in rig.pose.bones
    for o in objs
)
assert all(not o.data.validate(verbose=False) for o in objs)
S.render.resolution_x = S.render.resolution_y = 320
S.render.threads_mode = "FIXED"
S.render.threads = 2
S.cycles.samples = 5
S.cycles.use_denoising = True
results = {}
foot = {}
pose = {}
motion = {}


def pick(action, frame):
    rig.animation_data.action = bpy.data.actions[action]
    S.frame_set(frame)


def render(path):
    if check_only:
        return
    S.render.filepath = str(out / path)
    bpy.ops.render.render(write_still=True)


# Ensure the rest and performance endpoints survive saving. Defeat holds rather than resetting.
pick("Ready", 1)
resting = {b.name: b.matrix.copy() for b in rig.pose.bones}


def delta(m, n):
    return max(abs(m[i][j] - n[i][j]) for i in range(4) for j in range(4))


for name in peaks:
    a = bpy.data.actions[name]
    assert a.use_fake_user and a.frame_range[0] == 1
    pick(name, 1)
    if name == "Neutral":
        assert (
            max(
                delta(b.matrix, b.bone.matrix_local)
                for b in rig.pose.bones
                if b.name != "Burst"
            )
            < 0.0001
        )
    else:
        assert max(delta(b.matrix, resting[b.name]) for b in rig.pose.bones) < 0.0001
        pick(name, int(a.frame_range[1]))
        dev = max(delta(b.matrix, resting[b.name]) for b in rig.pose.bones)
        assert dev > 0.1 if name in ("Defeat", "Detonate on defeat") else dev < 0.0001

import bmesh
import numpy as np

v = {}
manif = {}
for o in objs:
    vs = np.zeros((len(o.data.vertices), 3), dtype=np.float32)
    o.data.vertices.foreach_get("co", vs.ravel())
    v[o] = np.c_[vs, np.ones(len(vs), np.float32)]
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bad = sum(not e.is_manifold for e in bm.edges)
    bm.free()
    if bad:
        manif[o.name] = bad
cam = np.array(S.camera.matrix_world.inverted())
scale = S.camera.data.ortho_scale
sweep = {}
lo = 0
for a in bpy.data.actions:
    rig.animation_data.action = a
    mi = np.full(3, 1e4)
    ma = -mi
    for f in range(1, 1 + int(a.frame_range[1])):
        S.frame_set(f)
        vs = np.concatenate([(v[o] @ np.array(o.matrix_world).T) for o in objs])
        uv = (vs @ cam.T)[:, :2] / scale + 0.5
        samples = np.c_[uv, vs[:, 2]]
        mi = np.minimum(mi, samples.min(axis=0))
        ma = np.maximum(ma, samples.max(axis=0))
        lo += 1
    sweep[a.name] = [mi.round(4).tolist(), ma.round(4).tolist()]
json.dump(
    dict(frames=lo, nonmanifold_edges=manif, uv_and_height=sweep),
    open(out / "sweep.json", "w"),
    indent=2,
)
print(
    "Swept",
    lo,
    "frames; floor",
    min(r[0][2] for r in sweep.values()),
    "nonmanifold",
    manif,
    "projection",
    min(min(r[0][:2]) for r in sweep.values()),
    max(max(r[1][:2]) for r in sweep.values()),
)
assert (
    not manif
    and min(r[0][2] for r in sweep.values()) >= 0
    and min(min(r[0][:2]) for r in sweep.values()) > 0
    and max(max(r[1][:2]) for r in sweep.values()) < 1
)


for name, fr in peaks.items():
    pick(name, fr)
    verts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    pts = [world_to_camera_view(S, S.camera, v) for v in verts]
    results[name] = [
        round(x, 3)
        for x in [
            min(v.x for v in pts),
            max(v.x for v in pts),
            min(v.y for v in pts),
            max(v.y for v in pts),
        ]
    ]
    foot[name] = round(min(v.z for v in verts), 4)
    end = int(bpy.data.actions[name].frame_range[1])
    if name == "Neutral":
        neutral_bounds = [
            round(max(v[i] for v in verts) - min(v[i] for v in verts), 3)
            for i in range(3)
        ]
    if name == "War drum pulse":
        felt = bpy.data.objects["Wrapped felt beater R"]
        cen = felt.matrix_world @ (
            sum((v.co for v in felt.data.vertices), Vector()) / len(felt.data.vertices)
        )
        skin = bpy.data.objects["Calfskin head.001"]
        verts2 = [skin.matrix_world @ v.co for v in skin.data.vertices]
        c0 = sum(verts2[:28], Vector()) / 28
        c1 = sum(verts2[28:], Vector()) / 28
        axis = (c1 - c0).normalized()
        diff = cen - c1
        gap = diff.dot(axis) - 0.068
        radial = (diff - axis * diff.dot(axis)).length
        print("CONTACT", gap, radial)
        assert abs(gap) < 0.013 and radial < 0.24
    key = name.replace(" ", "_")
    file = "pose_" + key + ".png"
    render(file)
    pose[name] = file
    if name != "Neutral":
        motion[name] = []
        for i in sorted(set([1, *range(3, end, 3), fr, end])):
            pick(name, i)
            file = f"{key}_{i:02}.png"
            render(file)
            motion[name].append([i, file])
assert all(min(r) > 0 and max(r) < 1 for r in results.values()), results
assert all(v > -0.008 for v in foot.values()), foot
print(
    "Mesh/bones, bounds in metres, floors:",
    len(objs),
    len(rig.data.bones),
    neutral_bounds,
    foot,
)
if not check_only:
    json.dump(
        dict(
            camera_width=S.camera.data.ortho_scale,
            actor=actor,
            source=bpy.data.filepath,
            projection=results,
            minimum_z=foot,
            mesh_count=len(objs),
            bones=len(rig.data.bones),
            neutral_bounds=neutral_bounds,
            poses=pose,
            motion=motion,
        ),
        open(out / "validation.json", "w"),
        indent=2,
    )
