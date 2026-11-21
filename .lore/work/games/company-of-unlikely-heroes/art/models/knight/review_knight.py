"""Reopen the Knight in Blender to check contact and render its review views.

blender -b /absolute/knight-guard-blockout.blend --python-exit-code 1 \
    --python /absolute/review_knight.py -- /absolute/output-directory
After --, pass --check-only instead of an output directory for checks only.
"""

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def surface(obj):
    vertices = [obj.matrix_world @ v.co for v in obj.data.vertices]
    faces = [tuple(p.vertices) for p in obj.data.polygons]
    return vertices, BVHTree.FromPolygons(vertices, faces)


def check(scene, rig, shield):
    assert scene.frame_current == 39, "The saved file should open on guard"
    assert scene.camera == bpy.data.objects["Camera_Tactical_3Q"]
    assert not bpy.data.libraries, "Model needs an external Blender library"
    assert not bpy.data.images, "Model should only use built-in procedural materials"
    assert rig.type == "ARMATURE"
    assert shield.parent == rig and shield.parent_type == "BONE"
    assert shield.parent_bone == "shield_mount.L"
    assert rig.data.bones["shield_mount.L"].parent.name == "forearm.L"
    assert len(shield.children) > 4 and any("iron pull handle" in o.name for o in shield.children)
    assert any("broad open forearm strap" in o.name for o in shield.children)
    assert rig.animation_data.action and (scene.frame_start, scene.frame_end) == (8, 78)
    assert {0, 8, 25, 31, 39, 44, 65, 78} <= {m.frame for m in scene.timeline_markers}

    scene.frame_set(0)
    assert all((p.matrix.translation-p.bone.matrix_local.translation).length < 1e-5
               for p in rig.pose.bones), "Frame zero should be the true T-pose"
    for side, direction in (("R", -1), ("L", 1)):
        p = rig.pose.bones["forearm."+side]
        assert (p.tail - p.head).normalized().dot(Vector((direction,0,0))) > .999

    knight = [o for o in scene.objects if o.parent == rig and o.type in {"MESH","CURVE"}]
    corners = [o.matrix_world @ Vector(p) for o in knight for p in o.bound_box]
    dimensions = tuple(max(v[i] for v in corners)-min(v[i] for v in corners) for i in range(3))
    assert 2 < dimensions[2] < 2.25, dimensions
    print("Neutral actor bounding box, width × depth × height (m):", tuple(round(d,3) for d in dimensions))
    print("Editable objects: actor =", len(knight), "shield children =", len(shield.children),
          "bones =", len(rig.data.bones))

    # Check the sampled arm/armor shell vertices against the actual outer oak
    # surface, not a bounding box. This catches the couter emerging through
    # the heraldry when the shield turns during the flinch.
    face = bpy.data.objects["Shield • curved oak outer skin"]
    _, face_bvh = surface(face)
    shield_neutral = shield.matrix_world.copy()
    tested_arm_parts = ("Quilted sleeve L", "Rerebrace L", "Elbow articulation L",
                        "Couter • pointed elbow L", "Vambrace • ridged L", "Wrapped wrist L")
    min_clearance = None
    shoulders = {
        "R": ("Right pauldron • raised bowl", "Right pauldron • first sliding lame"),
        "L": ("Left pauldron • cutback cap", "Left pauldron • short lame"),
    }
    nearest_skin = {s: float("inf") for s in shoulders}

    boots = {side: bpy.data.objects["Boot • bent leather "+side] for side in ("R","L")}
    rear = None
    lead = None
    ranges = {s: [] for s in boots}
    right_slide = 0
    left_slide = 0
    for frame in range(8, 79):
        scene.frame_set(frame)
        assert all(math.isfinite(p.matrix[0][0]) for p in rig.pose.bones)
        for side, boot in boots.items():
            soles = min((boot.matrix_world @ v.co).z for v in boot.data.vertices)
            ranges[side].append(soles)
            assert -.012 <= soles <= (.042 if side=="L" and 18<frame<31 else .014), (frame,side,soles)
        r = rig.pose.bones["boot.R"].matrix.translation.copy()
        l = rig.pose.bones["boot.L"].matrix.translation.copy()
        if rear is None:
            rear = r
        if frame == 31:
            lead = l
        right_slide = max(right_slide,(r-rear).length)
        if lead is not None:
            left_slide = max(left_slide,(l-lead).length)
        for side, names in shoulders.items():
            skin = [surface(bpy.data.objects[name])[1] for name in
                    ("Face • cheeks, sockets and chin", "Neck • scarf bridge", "Ear "+side)]
            for name in names:
                verts, plate = surface(bpy.data.objects[name])
                for part in skin:
                    assert not plate.overlap(part), (frame, name, "head/neck intersection")
                    distances = (part.find_nearest(v)[3] for v in verts)
                    nearest_skin[side] = min(nearest_skin[side], min(d for d in distances if d is not None))
        into_shield = shield_neutral @ shield.matrix_world.inverted()
        for name in tested_arm_parts:
            obj = bpy.data.objects[name]
            as_neutral = into_shield @ obj.matrix_world
            for v in obj.data.vertices:
                p = as_neutral @ v.co
                hit, _, _, _ = face_bvh.ray_cast(Vector((p.x,-.5,p.z)),Vector((0,1,0)))
                if hit is not None:
                    clearance = p.y-hit.y
                    if min_clearance is None or clearance < min_clearance[0]:
                        min_clearance = (clearance,frame,name)
    assert right_slide < .004 and left_slide < .004, (right_slide,left_slide)
    assert max(ranges["L"]) > .020, "Lead boot should lift before plant"
    for side, value in ranges.items():
        print("Sole height",side, "mm:",round(min(value)*1000,2), "to",round(max(value)*1000,2))
    print("Max boot-anchor displacement (mm): right frames 8–78 =",round(right_slide*1000,2),
          "; left frames 31–78 =", round(left_slide*1000,2))
    assert min_clearance is not None and min_clearance[0] > .010, min_clearance
    print("Minimum modeled arm/outer shield face sample gap (mm):", round(min_clearance[0]*1000,2),
          "at frame",min_clearance[1],min_clearance[2])
    print("Minimum upper pauldron/head-and-neck sample gaps (mm):",
          {s: round(d*1000,2) for s,d in nearest_skin.items()})


def render(scene, output):
    output.mkdir(parents=True, exist_ok=True)
    tactical = bpy.data.objects["Camera_Tactical_3Q"]
    front = bpy.data.objects["Camera_Neutral_Front"]
    face = bpy.data.objects["Camera_Face"]
    shield = bpy.data.collections["05 • Shield (detach at root)"]
    views = [("rest",0,front,800,986),("wary",8,tactical,720,820),
             ("plant",31,tactical,720,820),("guard",39,tactical,720,820),
             ("flinch",44,tactical,720,820),("settle",65,tactical,720,820),
             ("face",0,face,620,620)]
    for name,frame,cam,width,height in views:
        scene.frame_set(frame)
        scene.camera = cam
        shield.hide_render = frame == 0
        scene.render.resolution_x, scene.render.resolution_y = width,height
        scene.render.filepath = str(output / (name+".png"))
        bpy.ops.render.render(write_still=True)
    for c in scene.collection.children:
        if c.name[:2] in {"02","03","04"}:
            c.hide_render = True
    shield.hide_render = False
    scene.frame_set(0)
    cam = bpy.data.objects["Camera_Shield_Reverse"]
    cam.location = (.9,2.6,2.08)
    cam.rotation_euler = (Vector((.724,-.038,1.469))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.ortho_scale = 1.12
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = 620,720
    scene.render.filepath = str(output / "shield-reverse.png")
    bpy.ops.render.render(write_still=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output",type=Path,nargs="?")
    parser.add_argument("--check-only",action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    scene = bpy.context.scene
    check(scene,bpy.data.objects["Knight_Rig"],bpy.data.objects["Shield_L_Detachable"])
    if not args.check_only:
        render(scene,args.output.resolve())


if __name__ == "__main__":
    main()
