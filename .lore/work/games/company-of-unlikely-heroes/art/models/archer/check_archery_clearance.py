"""Read-only, evaluated-mesh clearance test for the Archer's entire action set."""
import hashlib
import json
from pathlib import Path
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector
from mathutils.bvhtree import BVHTree


SOURCE = Path(bpy.data.filepath).resolve()
ORIGINAL = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
MODE, OUT = sys.argv[sys.argv.index("--") + 1:]
assert MODE in ("diagnose", "verify")
REPO = next(p for p in SOURCE.parents if (p / "games/company-of-unlikely-heroes/tools/cast/bake_actor.py").is_file())
sys.path.insert(0, str(REPO / "games/company-of-unlikely-heroes/tools/cast"))
from bake_actor import ANCHOR, SIZE, setup

scene = setup(bpy.context.scene, "archer", ANCHOR)
rig = bpy.data.objects["Archer_Rig"]
bow = bpy.data.objects["Longbow_Detachable"]
arrow = bpy.data.objects["Arrow_Detachable"]
bow_parts = list(bow.children_recursive)
stave = [o for o in bow_parts if not o.name.startswith("Suede bow grip")]
strings = [o for o in scene.objects if o.name.startswith("Tensioned string")]
arrow_parts = list(arrow.children_recursive)
body = [o for o in scene.objects if o.type == "MESH"
        and o not in bow_parts + strings + arrow_parts]
grip_names = ("Palm heel R", "Closed grip finger 0R", "Closed grip finger 1R",
              "Closed grip finger 2R", "Closed grip finger 3R", "Grip thumb R")
draw_names = ("Palm heel L", "Closed grip finger 0L", "Closed grip finger 1L",
              "Closed grip finger 2L", "Closed grip finger 3L", "Grip thumb L")


class Surface:
    """World-space evaluated triangle soup; use AABB before exact BVH tests."""
    def __init__(self, obj, deps, omit_gripped_core=False):
        evaluated = obj.evaluated_get(deps)
        mesh = evaluated.data
        self.vertices = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
        mesh.calc_loop_triangles()
        if omit_gripped_core:
            self.tris = []
            self.vertices = []
            for tri in mesh.loop_triangles:
                triangle = [mesh.vertices[i].co for i in tri.vertices]
                for z, sign in ((.958, -1), (1.103, 1)):
                    part = self._clip(triangle, z, sign)
                    for i in range(1, len(part)-1):
                        start = len(self.vertices)
                        self.vertices.extend(evaluated.matrix_world @ p for p in (part[0], part[i], part[i+1]))
                        self.tris.append((start, start+1, start+2))
        else:
            self.tris = [tuple(tri.vertices) for tri in mesh.loop_triangles]
        self.range = tuple((min(v[i] for v in self.vertices), max(v[i] for v in self.vertices)) for i in range(3))
        self._tree = None
        self.closed = not omit_gripped_core

    @staticmethod
    def _clip(triangle, z, sign):
        poly = []
        for a, b in zip(triangle, triangle[1:] + triangle[:1]):
            inside_a = (a.z-z)*sign > 0
            inside_b = (b.z-z)*sign > 0
            if inside_a:
                poly.append(a)
            if inside_a != inside_b:
                poly.append(a.lerp(b, (z-a.z)/(b.z-a.z)))
        return poly

    @property
    def tree(self):
        if self._tree is None:
            self._tree = BVHTree.FromPolygons(self.vertices, self.tris, all_triangles=True)
        return self._tree

    def intersects_box(self, other):
        return all(lo < hi2 and lo2 < hi for (lo, hi), (lo2, hi2) in zip(self.range, other.range))

    def overlaps(self, other):
        if not self.intersects_box(other):
            return False
        if self.tree.overlap(other.tree):
            return True
        # A wholly embedded thin string/arrow may never cross a surface.
        # Containment is only attempted with both sides of a planar boundary
        # available and a point inside the other's AABB.
        return self.contains(other.vertices[0]) or other.contains(self.vertices[0])

    def contains(self, point):
        if not self.closed:
            return False
        if not all(lo < x < hi for x, (lo, hi) in zip(point, self.range)):
            return False
        ray = Vector((.671,.522,.429)).normalized()
        # Close polygon contacts can share triangle edges; step off each hit.
        count = 0
        while count < 24:
            location, *_ = self.tree.ray_cast(point, ray)
            if location is None:
                break
            point = location + ray * .00016
            count += 1
        return count % 2 == 1


def body_part(obj):
    names = {g.name for g in obj.vertex_groups}
    if obj.name.startswith(("Stitched oblique leather quiver", "Rolled quiver mouth",
                            "Quiver arrow shaft", "Split fletching")):
        return "quiver"
    if "head" in names:
        return "face/cap"
    if "hand.L" in names or "hand.R" in names:
        return "hand"
    if any(s.startswith("upper.") for s in names):
        return "sleeve"
    if any(s.startswith("fore.") for s in names):
        return "forearm/cuff"
    if any(s.startswith(("thigh", "shin", "foot")) for s in names):
        return "leg/boot"
    return "torso/hem"


def props_box(objs, surfaces):
    return min((min(v.x, 1-v.x, v.y, 1-v.y)*SIZE
                for p in objs for xyz in surfaces[p].vertices
                for v in [world_to_camera_view(scene, scene.camera, xyz)]), default=SIZE)


report = {"source_sha256": ORIGINAL, "actions": {}, "problem_frames": [], "minimum_pixels_to_edge": SIZE}
assert len(bow_parts) == 3 and len(strings) == 2 and len(arrow_parts) == 5
minimum = {}
ground = {}
draw_distance = []
for take in sorted(bpy.data.actions, key=lambda a:a.name):
    name = take.name.removeprefix("Archer | ")
    if name == "Neutral T":
        continue
    rig.animation_data.action = take
    count = 0
    problem = 0
    for f2 in range(2, int(take.frame_range[1]) * 2 + 1):
        frame = f2/2
        scene.frame_set(int(frame), subframe=frame-int(frame))
        bpy.context.view_layer.update()
        dep = bpy.context.evaluated_depsgraph_get()
        count += 1
        # The existing source hides its ready arrow by parking it below floor.
        # A partial transit towards that point is *not* parked.
        arrow_is_visible = arrow.matrix_world.translation.z > -1.99
        current_arrows = arrow_parts if arrow_is_visible else []
        group = {"stave": stave, "grip": [o for o in bow_parts if o not in stave],
                 "string": strings, "arrow": current_arrows}
        objects = bow_parts + strings + current_arrows
        surfaces = {p:Surface(p,dep) for p in objects}
        surfaces.update((b,Surface(b,dep)) for b in body)
        # Only subtract the span physically wrapped by the suede grip when
        # testing the closed gripping fingers. The rest of each limb is checked.
        outer_stave = {p:Surface(p,dep,omit_gripped_core=True) for p in stave}
        frame_problems = []
        if MODE == "verify":
            grip_surface = surfaces[group["grip"][0]].tree
            grasp = min(grip_surface.find_nearest(p)[3]
                        for b in body if b.name in grip_names
                        for p in surfaces[b].vertices[::3])
            holds = name != "Defeat" or frame <= 7
            # The shot and ordinary holds are still gripping. Only Defeat
            # intentionally releases the bow into its separate landing path.
            if holds and grasp > .012:
                frame_problems.append(["grip", "not in bow hand", round(grasp,4)])
            if name == "Draw and Release" and 7 <= frame <= 17:
                nock = rig.pose.bones["bow.nock"].head
                distance = min(surfaces[b].tree.find_nearest(nock)[3]
                               for b in body if b.name in draw_names)
                draw_distance.append(distance)
                if (nock-arrow.matrix_world.translation).length > .032:
                    frame_problems.append(["arrow","detached from held nock",round(frame,2)])
                if frame >= 8 and distance > .042:
                    frame_problems.append(["string","not in draw hand",round(distance,4)])
        for category, props in group.items():
            gap = props_box(props,surfaces)
            minimum[category] = min(minimum.get(category, SIZE),gap)
            z = min((surfaces[p].range[2][0] for p in props),default=3)
            ground[category] = min(ground.get(category,3),z)
            if gap < 3:
                frame_problems.append([category,"capture edge",round(gap,2)])
            if z < -.001:
                frame_problems.append([category,"ground",round(z,4)])
            for o in props:
                for b in body:
                    # Designed contact exceptions, only where the grasp occurs.
                    if category == "grip" and b.name in grip_names:
                        continue
                    tested = outer_stave[o] if category == "stave" and b.name in grip_names else surfaces[o]
                    if tested.overlaps(surfaces[b]):
                        if (category in ("string","arrow") and b.name in draw_names
                            and name == "Draw and Release" and 7 <= frame <= 17):
                            # Exempt actual grasp contact at the nock, not arbitrary
                            # intersections between the string and this hand.
                            nock = rig.pose.bones["bow.nock"].head
                            if tested.tree.find_nearest(nock)[3] < .018 \
                               and surfaces[b].tree.find_nearest(nock)[3] < .055:
                                continue
                        frame_problems.append([category, body_part(b), o.name, b.name])
        if current_arrows:
            for p in current_arrows:
                for b in bow_parts:
                    if surfaces[p].overlaps(surfaces[b]):
                        frame_problems.append(["arrow", "bow", p.name, b.name])
        elif name == "Draw and Release" and 7 <= frame <= 18:
            frame_problems.append(["arrow", "missing from held shot or flight", frame])
        if frame_problems:
            report["problem_frames"].append({"action":name, "frame":frame,"contacts":frame_problems})
            problem += 1
    report["actions"][name] = {"frames":count,"problem_frames":problem}

report["minimum_pixels_to_edge"] = {k:round(v,2) for k,v in minimum.items()}
report["minimum_metres_above_floor"] = {k:round(v,4) for k,v in ground.items()}
if draw_distance:
    report["max_nock_distance_to_draw_hand_m"] = round(max(draw_distance[2:]), 4)
assert ORIGINAL == hashlib.sha256(SOURCE.read_bytes()).hexdigest()
out = Path(OUT)
assert out.is_absolute() and out.resolve() != SOURCE
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(report, indent=2) + "\n")
print("Archer evaluated clearance:", report["actions"], report["minimum_pixels_to_edge"],
      report["minimum_metres_above_floor"], flush=True)
if MODE == "verify":
    assert not report["problem_frames"], f"{len(report['problem_frames'])} problem frames; see {OUT}"
