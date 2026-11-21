"""Check or render the saved Skeleton candidate in Blender. Never saves the source."""

import argparse
import sys
from functools import cache
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


PREFIX = "Skeleton | "
REST, READY, WAVE, PLEAD = ("Neutral T", "Ready & Greet", "Wave", "Don't Go")
ENDS = {REST: 1, READY: 45, WAVE: 53, PLEAD: 65}
TACTICAL = "Camera_Tactical_3Q"
STILLS = (
    ("neutral", REST, 1, "Camera_Neutral_Front"),
    ("ready", READY, 1, TACTICAL),
    ("greet", READY, 18, TACTICAL),
    ("wave", WAVE, 15, TACTICAL),
    ("wave-through", WAVE, 20, TACTICAL),
    ("dont-go", PLEAD, 27, TACTICAL),
    ("profile", PLEAD, 27, "Camera_Working_Side"),
    ("rear", REST, 1, "Camera_Working_Rear"),
    ("portrait", READY, 18, "Camera_Portrait"),
)
NATIVE = tuple(t for t in STILLS if t[3] == TACTICAL)
SWEPT_PARTS = ("humerus", "radius", "ulna", "wrist cluster",
               "Index phalanx 1", "Index phalanx 3", "Middle phalanx 2",
               "Ring phalanx 2", "Little phalanx 3", "Thumb phalanx 3")
TORSO_OBSTACLES = (
    "Skull | connected vault, brow and cheekbones", "Mandible | single U with chin and rami",
    "Neckerchief | long split tail", "Neckerchief | outward tail", "Sternum | tapered plate",
    "L | rib 02", "R | rib 02", "L | rib 04", "R | rib 04", "L | rib 06", "R | rib 06",
)
OBJ = bpy.data.objects


def pose(scene, rig, action, frame):
    rig.animation_data.action = bpy.data.actions[PREFIX + action]
    scene.frame_set(int(frame), subframe=frame % 1)


@cache
def local_geometry(name):
    obj = OBJ[name]
    # The original skull, teeth, and neckerchief still carry their detail modifiers.
    mesh = obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).data if obj.modifiers else obj.data
    return [v.co.copy() for v in mesh.vertices], [tuple(p.vertices) for p in mesh.polygons]


def geometry(name):
    verts, polys = local_geometry(name)
    matrix = OBJ[name].matrix_world
    return [matrix @ v for v in verts], polys


def camera_bounds(scene, actor):
    """Conservative bounds from the corners of each evaluated rigid part."""
    camera = scene.camera
    inv = camera.matrix_world.inverted()
    corners = camera.data.view_frame(scene=scene)
    left, bottom = min(v.x for v in corners), min(v.y for v in corners)
    width, height = max(v.x for v in corners) - left, max(v.y for v in corners) - bottom
    coords = []
    for name in actor:
        obj = OBJ[name]
        transform = inv @ obj.matrix_world
        coords.extend(transform @ corner for corner in bounds_corners(name))
    return [(min(p.x for p in coords) - left) / width, (min(p.y for p in coords) - bottom) / height,
            (max(p.x for p in coords) - left) / width, (max(p.y for p in coords) - bottom) / height]


@cache
def bounds_corners(name):
    verts, _ = local_geometry(name)
    (x1, y1, z1), (x2, y2, z2) = ([fn(v[i] for v in verts) for i in range(3)] for fn in (min, max))
    return [Vector((x, y, z)) for x in (x1, x2) for y in (y1, y2) for z in (z1, z2)]


def delta(a, b):
    return max(abs(x - y) for arow, brow in zip(a, b) for x, y in zip(arow, brow))


def snapshot(rig):
    return {bone.name: bone.matrix.copy() for bone in rig.pose.bones}


def verify_scene(scene, rig):
    assert not (bpy.data.libraries or bpy.data.images or rig.animation_data.nla_tracks)
    assert scene.camera.name == TACTICAL and scene.camera.data.type == "ORTHO"
    assert abs(scene.camera.data.ortho_scale - 2.47) < 1e-5
    assert all(abs(a - b) < 1e-5 for a, b in zip(scene.camera.rotation_euler, (1.1508292, 0, -.4353864)))
    assert scene.unit_settings.system == "METRIC" and scene.unit_settings.scale_length == 1
    assert scene.render.fps == 24 and scene.frame_current == 1 and scene.frame_end == ENDS[READY]
    assert rig.animation_data.action.name == PREFIX + READY
    assert set(bpy.data.actions.keys()) == {PREFIX + name for name in ENDS}
    for take, end in ENDS.items():
        action = bpy.data.actions[PREFIX + take]
        assert action.use_fake_user and action.frame_range[:] == (1., float(end))
    actor = tuple(obj.name for obj in scene.objects
                  if obj.type == "MESH" and obj.name != "Review ground Z=0")
    bones = rig.pose.bones
    for name in actor:
        obj = OBJ[name]
        assert obj.parent == rig and obj.parent_type == "BONE" and obj.parent_bone in bones
        assert obj.material_slots and obj.data.polygons, name
    assert OBJ["Mandible | single U with chin and rami"].parent_bone == "jaw"
    assert all(OBJ[n].parent_bone == "jaw" for n in actor if n.startswith("Lower tooth"))
    assert all(OBJ[n].parent_bone == "head" for n in actor if n.startswith("Upper tooth"))
    assert OBJ["Neckerchief | draped wrap"].parent_bone == "chest"
    assert OBJ["Neckerchief | long split tail"].parent_bone == "scarf.long"
    assert OBJ["Neckerchief | outward tail"].parent_bone == "scarf.short"
    assert bones["jaw"].parent == bones["head"]
    pose(scene, rig, REST, 1)
    assert all(delta(b.matrix, b.bone.matrix_local) < 1e-5 for b in bones)
    for side, sign in (("L", 1), ("R", -1)):
        for parent, child in (("clavicle", "upper_arm"), ("upper_arm", "forearm"), ("forearm", "hand"),
                              ("thigh", "shin"), ("shin", "foot"), ("index.01", "index.02")):
            p, c = bones[f"{parent}.{side}"], bones[f"{child}.{side}"]
            assert c.parent == p and (c.head - p.tail).length < 1e-5
        assert all(abs(bones[f"{p}.{side}"].vector.normalized().dot(Vector((sign, 0, 0))) - 1) < 1e-6
                   for p in ("upper_arm", "forearm", "hand"))
        for digit in ("thumb", "index", "middle", "ring", "little"):
            for joint in (1, 2, 3):
                bone = bones[f"{digit}.{joint:02}.{side}"]
                assert OBJ[f"{side} | {digit.title()} knuckle {joint}"].parent_bone == bone.name
                assert OBJ[f"{side} | {digit.title()} phalanx {joint}"].parent_bone == bone.name
                assert bone.parent == bones[
                    f"hand.{side}" if joint == 1 else f"{digit}.{joint-1:02}.{side}"]
                if joint > 1:
                    assert (bone.head - bone.parent.tail).length < 1e-5
    verts = [v for name in actor for v in geometry(name)[0]]
    low = [min(v[i] for v in verts) for i in range(3)]
    high = [max(v[i] for v in verts) for i in range(3)]
    print(f"Rest: {len(bones)} bones, {len(actor)} meshes, "
          f"dimensions m {[round(b-a, 3) for a,b in zip(low, high)]}; "
          f"minimum Z {low[2]*1000:.2f} mm.", flush=True)
    assert -.001 <= low[2] <= .003 and 1.75 <= high[2] <= 2.05
    return actor


def limit_joint_gap(cache, side):
    result = {}
    joints = (
        ("hip", "femoral head", "continuous pelvic half"),
        ("shoulder", "humerus", "shoulder joint"),
        ("elbow-radius", "radius", "elbow condyle"),
        ("elbow-ulna", "ulna", "elbow condyle"),
        ("wrist-radius", "radius", "wrist cluster"),
        ("wrist-ulna", "ulna", "wrist cluster"),
        ("knee", "femur", "tibia"),
        ("ankle", "tibia", "talus"),
    )
    for label, source, target in joints:
        src_vertices, src = cache(f"{side} | {source}")
        dst_vertices, dst = cache(f"{side} | {target}")
        result[f"{label}.{side}"] = 0.0 if src.overlap(dst) else min(
            min(dst.find_nearest(v)[3] for v in src_vertices[::3]),
            min(src.find_nearest(v)[3] for v in dst_vertices[::3]),
        )
    return result


def inspect_actions(scene, rig, actor, diagnostics):
    pose(scene, rig, READY, 1)
    ready = snapshot(rig)
    footnames = {s: [n for n in actor if n[0] == s and OBJ[n].parent_bone in
                     {f"foot.{s}", f"toe.{s}"}] for s in "LR"}
    worst_gaps, collisions = {}, {}
    lowest, highest = float("inf"), -float("inf")
    foot_delta = endpoint_delta = root_delta = local_scale_delta = 0.
    projection = [.5, .5, .5, .5]
    scene.render.resolution_x, scene.render.resolution_y = 640, 590
    b = rig.pose.bones
    qa_wave = []
    for take, end in ENDS.items():
        for j in range(2, 2*end + 1):
            frame = j / 2
            pose(scene, rig, take, frame)
            root_delta = max(root_delta, delta(b["root"].matrix, ready["root"]))
            local_scale_delta = max(local_scale_delta, max(abs(v-1) for bone in b for v in bone.scale))
            if take != REST:
                if frame in (1, end):
                    endpoint_delta = max(endpoint_delta, max(delta(ready[n], m)
                                                            for n, m in snapshot(rig).items()))
                for side in "LR":
                    foot_delta = max(foot_delta, *(delta(b[n].matrix, ready[n])
                                                 for n in (f"foot.{side}", f"toe.{side}")))
                    bottom = min(v.z for n in footnames[side] for v in geometry(n)[0])
                    lowest, highest = min(lowest, bottom), max(highest, bottom)
            if j % 2:
                continue
            cache = {}

            def surface(name):
                if name not in cache:
                    verts, polys = geometry(name)
                    cache[name] = (verts, BVHTree.FromPolygons(verts, polys))
                return cache[name]

            for side in "LR":
                for label, gap in limit_joint_gap(surface, side).items():
                    if label not in worst_gaps or gap > worst_gaps[label][0]:
                        worst_gaps[label] = (gap, take, frame)
                for part in SWEPT_PARTS:
                    for obstacle in TORSO_OBSTACLES:
                        if part == "humerus" and "rib" in obstacle and obstacle.startswith(side):
                            continue  # The shoulder-end cuff and upper rib are neighboring geometry.
                        if surface(f"{side} | {part}")[1].overlap(surface(obstacle)[1]):
                            collisions.setdefault((side, part, obstacle), []).append((take, frame))
            if take == WAVE:
                qa_wave.append(b["middle.03.L"].tail.copy())
            if take != REST:
                observed = camera_bounds(scene, actor)
                projection = [fn(a, c) for fn, a, c in zip((min, min, max, max), projection, observed)]
    span = max(v.x for v in qa_wave) - min(v.x for v in qa_wave)
    pose(scene, rig, WAVE, 15)
    wave_height = b["hand.L"].head.z
    pose(scene, rig, PLEAD, 27)
    plea_wrist = b["hand.L"].head.copy()
    palm_up = b["hand.L"].matrix.to_3x3().col[2].z
    plea_reach = (b["clavicle.L"].tail - plea_wrist).y
    pose(scene, rig, PLEAD, 35)
    hold_shift = (b["hand.L"].head - plea_wrist).length
    print(f"Foot matrix drift {foot_delta:.7f}; per-foot ground contact {lowest*1000:.3f}–"
          f"{highest*1000:.3f} mm; root {root_delta:.7f}; endpoint {endpoint_delta:.7f}; "
          f"local scale delta {local_scale_delta:.7f}.")
    print("Maximum sampled surface gap by joint (mm):",
          {n: (round(gap * 1000, 2), take, frame) for n, (gap, take, frame) in worst_gaps.items()})
    print("Arm/hand versus face, torso and scarf overlaps (pair, count, first, last):",
          [(n, len(v), v[0], v[-1]) for n, v in collisions.items()])
    print(f"Wave hand travel across X: {span:.3f} m; Wave peak wrist Z {wave_height:.3f} m; "
          f"Don't Go wrist Z {plea_wrist.z:.3f} m, forward reach {plea_reach:.3f} m, "
          f"palm-up {palm_up:.3f}, held wrist travel {hold_shift:.5f} m.")
    print("Tactical image bounds across all moving takes:", [round(x, 4) for x in projection], flush=True)
    if not diagnostics:
        assert max(foot_delta, endpoint_delta, root_delta, local_scale_delta) < 2e-4
        assert -.001 <= lowest <= highest <= .003
        assert all(gap < .012 for gap, _, _ in worst_gaps.values())
        assert not collisions
        assert span > .7 and wave_height - plea_wrist.z > .3
        assert plea_reach > .40 and palm_up > .70 and hold_shift < .01
        assert min(projection[:2]) > .015 and max(projection[2:]) < .985


def render(scene, rig, out, action, frame, camera, width, height, samples):
    pose(scene, rig, action, frame)
    scene.camera = OBJ[camera]
    scene.render.resolution_x, scene.render.resolution_y = width, height
    scene.cycles.samples = samples
    scene.render.filepath = str(out)
    assert "FINISHED" in bpy.ops.render.render(write_still=True)
    assert out.is_file() and out.stat().st_size > 100


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--render-only", action="store_true")
    parser.add_argument("--diagnostics", action="store_true")
    parser.add_argument("--quick", action="store_true", help="Faster renders for iteration")
    parser.add_argument("--motion", action="store_true", help="Render acting frames at 12 samples of time per second")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    scene, rig = bpy.context.scene, OBJ["Skeleton_Rig"]
    if not args.render_only:
        actors = verify_scene(scene, rig)
        inspect_actions(scene, rig, actors, args.diagnostics)
    if args.check_only:
        return
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    if args.motion:
        for title, slug in ((READY, "greet"), (WAVE, "wave"), (PLEAD, "dont-go")):
            for frame in range(1, ENDS[title] + 1, 2):
                render(scene, rig, out / f"{slug}-{(frame-1)//2:02}.png",
                       title, frame, TACTICAL, 252, 232, 12)
        return
    size = (320, 295, 12) if args.quick else (640, 590, 32)
    for slug, title, frame, camera in STILLS:
        render(scene, rig, out / f"{slug}.png", title, frame, camera, *size)
    for slug, title, frame, camera in NATIVE:
        render(scene, rig, out / f"{slug}-native.png", title, frame, camera, 65, 54, 32)


if __name__ == "__main__":
    main()
