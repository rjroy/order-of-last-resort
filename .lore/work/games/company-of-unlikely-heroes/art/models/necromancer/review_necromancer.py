"""Reopen, check and render the saved Necromancer. This script never saves."""

import argparse
from pathlib import Path
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector
from mathutils.bvhtree import BVHTree


PREFIX = "Necromancer | "
REST, READY, RING, RAISE = ("Neutral T", "Ready", "Summon Skeleton", "Raise Dead")
ENDS = {READY: 25, RING: 45, RAISE: 69}
TACTICAL = "Camera_Tactical_3Q"
STILLS = (
    ("neutral", REST, 1, "Camera_Neutral_Front"),
    ("ready", READY, 1, TACTICAL),
    ("ring", RING, 13, TACTICAL),
    ("raise", RAISE, 34, TACTICAL),
    ("portrait", READY, 1, "Camera_Portrait"),
    ("kneel-side", RAISE, 34, "Camera_Kneel_Side"),
)
NATIVE = (("ready", READY, 1), ("ring", RING, 13), ("raise", RAISE, 34))
OBJECTS = bpy.data.objects
GROUND = "Review ground Z=0"
MOUNT = "bell_mount.R"
BELL = "Handbell_R_Detachable"
CASTING = "Hollow flared casting · bright lip and dark interior"
CLAPPER = "Bell clapper · visible striking ball"
GRIP = "Turned walnut handbell handle"
SOLES = ("Boot outsole • L", "Boot outsole • R")
SKIRTS = ("Split frock skirt • L", "Split frock skirt • R")
STOLES = ("Pale stole with marigold selvage • L", "Pale stole with marigold selvage • R")
FINGERS = ("Index", "Middle", "Ring", "Little", "Thumb")


def pose(scene, rig, action, frame):
    rig.animation_data.action = bpy.data.actions[PREFIX + action]
    scene.frame_set(int(frame), subframe=frame % 1)


def geometry(name, deps):
    obj = OBJECTS[name].evaluated_get(deps)
    mesh = obj.to_mesh()
    verts = [obj.matrix_world @ v.co for v in mesh.vertices]
    polys = [tuple(p.vertices) for p in mesh.polygons]
    obj.to_mesh_clear()
    return verts, polys


def tree(name, deps):
    return BVHTree.FromPolygons(*geometry(name, deps))


def collision_band(polys, verts, hits):
    return [min(verts[i].z for idx in hits for i in polys[idx]),
            max(verts[i].z for idx in hits for i in polys[idx])]


def matrix_delta(a, b):
    return max(abs(a[i][j] - b[i][j]) for i in range(4) for j in range(4))


def snapshot(rig):
    return {p.name: p.matrix.copy() for p in rig.pose.bones}


def pose_delta(a, b):
    return max(matrix_delta(m, b[name]) for name, m in a.items())


def verify_detach(bell):
    """Exercise Clear Parent and Keep Transformation in memory."""
    view = bpy.context.view_layer
    view.update()
    pieces = {ob.name: ob.matrix_world.copy() for ob in bell.children_recursive}
    rig, inverse, basis = bell.parent, bell.matrix_parent_inverse.copy(), bell.matrix_basis.copy()
    world = bell.matrix_world.copy()
    bell.parent = None
    bell.matrix_world = world
    view.update()
    assert len(bell.children_recursive) == len(pieces)
    assert all(matrix_delta(ob.matrix_world, pieces[ob.name]) < .00005 for ob in bell.children_recursive)
    bell.parent, bell.parent_type, bell.parent_bone = rig, "BONE", MOUNT
    bell.matrix_parent_inverse, bell.matrix_basis = inverse, basis
    view.update()
    assert matrix_delta(bell.matrix_world, world) < .00005


def verify_setup(scene, rig):
    assert scene.camera.name == TACTICAL and scene.camera.data.type == "ORTHO"
    assert abs(scene.camera.data.ortho_scale - 2.47) < .0001
    assert all(abs(a - b) < .0001 for a, b in zip(scene.camera.rotation_euler, (1.1508292, 0, -.4353864)))
    assert scene.unit_settings.system == "METRIC" and scene.unit_settings.scale_length == 1
    assert scene.render.fps == 24 and scene.frame_current == 1 and scene.frame_end == ENDS[READY]
    assert rig.animation_data.action.name == PREFIX + READY
    assert not bpy.data.libraries and not bpy.data.images and not rig.animation_data.nla_tracks
    assert len(bpy.data.actions) == 4
    for take, end in ((REST, 1), *ENDS.items()):
        action = bpy.data.actions[PREFIX + take]
        assert action.use_fake_user and action.frame_range[:] == (1., float(end))
    bones = rig.pose.bones
    assert bones[MOUNT].parent == bones["hand.R"]
    assert bones["clapper.R"].parent == bones[MOUNT]
    for side in "LR":
        assert bones["shin." + side].parent == bones["thigh." + side]
        assert bones["foot." + side].parent == bones["shin." + side]
        assert bones["stole_end." + side].parent == bones["stole_upper." + side]
        assert bones["Index_tip." + side].parent == bones["Index." + side]
    bell = OBJECTS[BELL]
    assert (bell.parent, bell.parent_type, bell.parent_bone) == (rig, "BONE", MOUNT)
    assert OBJECTS[CLAPPER] in bell.children_recursive and OBJECTS[CASTING] in bell.children
    actors = [o.name for o in scene.objects if o.type in {"MESH", "CURVE"} and o.name != GROUND]
    assert all(OBJECTS[name].parent for name in actors)
    deps = bpy.context.evaluated_depsgraph_get()
    pose(scene, rig, REST, 1)
    for b in bones:
        assert matrix_delta(b.matrix, b.bone.matrix_local) < .0001, b.name
    for side, sign in (("L", 1), ("R", -1)):
        assert (bones["hand." + side].tail - bones["upper_arm." + side].head).normalized().dot(
            Vector((sign, 0, 0))) > .999
    verts = [v for n in actors for v in geometry(n, deps)[0]]
    bounds = tuple(max(v[i] for v in verts) - min(v[i] for v in verts) for i in range(3))
    print(f"Rest: {len(bones)} bones, {len(actors)} editable geometry objects; "
          f"{bounds[0]:.3f} × {bounds[1]:.3f} × {bounds[2]:.3f} m; "
          f"minimum Z {min(v.z for v in verts)*1000:.1f} mm.")
    return actors, deps


def check(scene, rig, diagnostic=False):
    actors, deps = verify_setup(scene, rig)
    bones = rig.pose.bones
    pose(scene, rig, READY, 1)
    ready = snapshot(rig)
    mount_ref = bones[MOUNT].matrix.inverted() @ OBJECTS[BELL].matrix_world
    verify_detach(OBJECTS[BELL])
    stance = {s: bones["foot." + s].matrix.copy() for s in "LR"}
    knee_hold = toe_hold = None
    hold = None
    endpoint_drift = mount_drift = root_drift = plant_drift = toe_drift = knee_drift = 0.
    floor = {name: [float("inf"), -float("inf")] for name in (*SOLES, *SKIRTS, "Twill trouser leg • R")}
    overlaps = {}
    hem_notes = {}
    grip_gap = 0.
    clapper_path, mouths = [], []
    knee_floor = []
    for take, end in ENDS.items():
        for i in range(2, 2 * end + 1):
            f = i / 2
            pose(scene, rig, take, f)
            if f in (1, end):
                endpoint_drift = max(endpoint_drift, pose_delta(ready, snapshot(rig)))
            mount_drift = max(mount_drift, matrix_delta(mount_ref, bones[MOUNT].matrix.inverted() @ OBJECTS[BELL].matrix_world))
            root_drift = max(root_drift, matrix_delta(ready["root"], bones["root"].matrix))
            for side in ("L", "R"):
                foot_matrix = bones["foot." + side].matrix
                if side == "L" or take != RAISE or f <= 8 or f >= 59:
                    plant_drift = max(plant_drift, matrix_delta(stance[side], foot_matrix))
            right_leg, right_faces = geometry("Twill trouser leg • R", deps)
            for name in floor:
                verts = right_leg if name == "Twill trouser leg • R" else geometry(name, deps)[0]
                low = min(v.z for v in verts)
                floor[name][0] = min(floor[name][0], low)
                floor[name][1] = max(floor[name][1], low)
            if take == RAISE and 18 <= f <= 49:
                toe = min(geometry(SOLES[1], deps)[0], key=lambda v: v.z)
                toe_hold = toe.copy() if toe_hold is None else toe_hold
                toe_drift = max(toe_drift, (toe_hold - toe).length)
            if take == RAISE and 26 <= f <= 41:
                if hold is None:
                    hold, knee_hold = snapshot(rig), bones["shin.R"].head.copy()
                knee_drift = max(knee_drift, (knee_hold - bones["shin.R"].head).length)
                knee_floor.append(min(p.z for p in right_leg))
                assert pose_delta(hold, snapshot(rig)) < .0001

            bell_tree = tree(CASTING, deps)
            fingers = {n + " • R": tree(n + " • R", deps) for n in FINGERS}
            grip_verts = geometry(GRIP, deps)[0]
            grip_gap = max(grip_gap, min(t.find_nearest(v)[3] for t in fingers.values() for v in grip_verts[::8]))
            for n in ("Long oval portrait / shaping rings", "Nose · broad bridge and softly rounded tip",
                      "Silver chin beard", "Palm • R", "Palm • L", "Frock sleeve • R",
                      "Index • R", "Middle • R", "Ring • R", "Little • R", "Thumb • R"):
                if bell_tree.overlap(fingers[n] if n in fingers else tree(n, deps)):
                    overlaps.setdefault((CASTING, n), []).append((take, f))
            for skirt in SKIRTS:
                shell_verts, shell_polys = geometry(skirt, deps)
                bvh = BVHTree.FromPolygons(shell_verts, shell_polys)
                for n in ("Palm • L", "Palm • R", "Twill trouser leg • L", "Twill trouser leg • R"):
                    other = BVHTree.FromPolygons(right_leg, right_faces) if n.endswith("leg • R") else tree(n, deps)
                    hits = bvh.overlap(other)
                    if not hits:
                        continue
                    if n.startswith("Twill") and n[-1] == skirt[-1] and f in (1, 13, 18, 26, 34):
                        hem_notes[(take, f, skirt)] = [round(v, 3) for v in
                            collision_band(shell_polys, shell_verts, {a for a, _ in hits})]
                    overlaps.setdefault((skirt, n), []).append((take, f))
            for n in STOLES:
                bvh = tree(n, deps)
                for part in ("Palm • L", "Palm • R", "Twill trouser leg • L", "Twill trouser leg • R"):
                    if bvh.overlap(tree(part, deps)):
                        overlaps.setdefault((n, part), []).append((take, f))
            if take == RING and f in (13, 16, 20):
                clapper_path.append(OBJECTS["Clapper_Hinge"].rotation_euler.z)
                mouths.append((OBJECTS[BELL].matrix_world.to_3x3() @ Vector((0, -1, 0))).normalized())
    print(f"Sampling: {sum(2*n-1 for n in ENDS.values())} half-frames. "
          f"Endpoint, root, mount, plant matrix deltas: "
          f"{endpoint_drift:.7f}, {root_drift:.7f}, {mount_drift:.7f}, {plant_drift:.7f}.")
    print(f"Rear toe travel over plant: {toe_drift*1000:.3f} mm; "
          f"knee travel during offer: {knee_drift*1000:.3f} mm; "
          f"right trouser ground clearance during offer: {min(knee_floor)*1000:.2f} mm.")
    print(f"Handle-to-finger gap, worst nearest sampled point: {grip_gap*1000:.2f} mm.")
    print("Minimum-Z ranges (mm):", {n: [round(x*1000,2) for x in span] for n, span in floor.items()})
    print("Clapper hinge rotations:", [round(x, 3) for x in clapper_path],
          "bell strokes:", [[round(t, 3) for t in v] for v in mouths])
    print("Overlap pairs / sample count / first and last:",
          [(a, b, len(v), v[0], v[-1]) for (a, b), v in overlaps.items()])
    if diagnostic:
        print("Skirt/twill collision bands by sample (world Z):", hem_notes)
    assert max(endpoint_drift, mount_drift, root_drift) < .0001
    assert max(clapper_path) - min(clapper_path) > .3 and mouths[0].angle(mouths[1]) > .35

    gesture = []
    for slug, take, f in NATIVE:
        pose(scene, rig, take, f)
        wrist_l = bones["hand.L"].head
        wrist_r = bones["hand.R"].head
        palm = -(bones["hand.L"].matrix.to_3x3() @ Vector((0, 0, 1))).z
        print(f"{slug:>5} f{f}: wrist heights L {wrist_l.z:.3f}, R {wrist_r.z:.3f}; "
              f"palm-up component {palm:.3f}; right knee Z {bones['shin.R'].head.z:.3f}; "
              f"right wrist relative to hips {(wrist_r-bones['pelvis'].head).length:.3f}.")
        gesture.append((wrist_l.z, wrist_r.z, palm))
    for _, take, f, cam in STILLS[:4]:
        pose(scene, rig, take, f)
        coords = [world_to_camera_view(scene, OBJECTS[cam], v) for n in actors
                  if not (take == REST and n in {ob.name for ob in OBJECTS[BELL].children_recursive})
                  for v in geometry(n, deps)[0][::7]]
        print(f"{take} view bounds: {min(v.x for v in coords):.3f}–{max(v.x for v in coords):.3f} x "
              f"{min(v.y for v in coords):.3f}–{max(v.y for v in coords):.3f} y.")
        if not diagnostic:
            assert all(.01 <= p.x <= .99 and .01 <= p.y <= .99 for p in coords), (take, f)
    if not diagnostic:
        assert plant_drift < .0001 and toe_drift < .001 and knee_drift < .0001
        assert min(knee_floor) >= -.002 and min(knee_floor) < .020
        assert min(lo for lo, _ in floor.values()) >= -.002
        assert grip_gap < .012
        assert not overlaps, "Inspect bell, coat and hand clearance."
        assert gesture[1][1] - gesture[2][1] > .45 and gesture[1][0] - gesture[2][0] > .40
        assert gesture[1][2] > .55 and gesture[2][2] > .55


def render(scene, rig, path, take, f, camera, w, h, samples, isolated=False):
    pose(scene, rig, take, f)
    scene.camera = OBJECTS[camera]
    neutral = take == REST
    stage_hidden = isolated or neutral or camera == "Camera_Portrait"
    OBJECTS[GROUND].hide_render = stage_hidden
    scene.render.film_transparent = stage_hidden
    for piece in OBJECTS[BELL].children_recursive:
        piece.hide_render = neutral
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.cycles.samples = samples
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    assert path.is_file() and path.stat().st_size > 100, path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--render-only", action="store_true")
    parser.add_argument("--motion", action="store_true")
    parser.add_argument("--quick", action="store_true", help="Smaller stills for iteration")
    parser.add_argument("--diagnostic", action="store_true", help="Print clearance observations without asserting them")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    scene, rig = bpy.context.scene, OBJECTS["Necromancer_Rig"]
    if not args.render_only:
        check(scene, rig, args.diagnostic)
    if args.check_only:
        return
    dst = args.output.resolve()
    dst.mkdir(parents=True, exist_ok=True)
    if args.motion:
        for take, slug in ((RING, "ring"), (RAISE, "raise")):
            for f in range(1, ENDS[take] + 1, 2):
                render(scene, rig, dst / f"{slug}-{(f-1)//2:02d}.png", take, f, TACTICAL, 280, 246, 9)
        return
    for name, take, frame, camera in STILLS:
        w, h, samples = (357, 345, 10) if args.quick else (640, 620, 32)
        render(scene, rig, dst / (name + ".png"), take, frame, camera, w, h, samples)
    for name, take, frame in NATIVE:
        render(scene, rig, dst / (name + "-native.png"), take, frame, TACTICAL, 65, 54, 32, isolated=True)


if __name__ == "__main__":
    main()
