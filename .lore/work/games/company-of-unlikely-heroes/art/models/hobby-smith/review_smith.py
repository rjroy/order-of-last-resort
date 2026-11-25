"""Reopen and check a Smith master. Render in memory only; never save the blend."""

import hashlib
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector


V = Vector
PREFIX = "Hobby Smith | "
CLIPS = {"Neutral T": 1, "Ready": 25, "Try This": 33, "Hammer Time": 34, "Pursue Step": 28}
VIEWS = {
    "ready": ("Ready", 1, "Camera_Tactical_3Q"),
    "try-this": ("Try This", 16, "Camera_Tactical_3Q"),
    "hammer-windup": ("Hammer Time", 12, "Camera_Tactical_3Q"),
    "hammer-time": ("Hammer Time", 17, "Camera_Tactical_3Q"),
    "pursue-step": ("Pursue Step", 19, "Camera_Tactical_3Q"),
    "neutral-front": ("Neutral T", 1, "Camera_Front"),
    "neutral-back": ("Neutral T", 1, "Camera_Back"),
    "portrait": ("Ready", 1, "Camera_Portrait"),
}
SOCKETS = {
    "Hammer_Detachable": ("hand.R", (-.918,-.028,1.500)),
    "Fitting_Detachable": ("hand.L", (.918,-.032,1.509)),
}


def load_pose(rig, clip, at):
    scene = bpy.context.scene
    rig.animation_data.action = bpy.data.actions[PREFIX + clip]
    scene.frame_set(int(at), subframe=at % 1)
    bpy.context.view_layer.update()


def actor_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def world_geometry(o, depsgraph):
    evaluated = o.evaluated_get(depsgraph)
    return [evaluated.matrix_world @ V(v) for v in evaluated.bound_box]


def bone_point(rig, bone_name, point):
    bone = rig.pose.bones[bone_name]
    return rig.matrix_world @ bone.matrix @ bone.bone.matrix_local.inverted() @ V(point)


def check_structure(rig):
    assert len([o for o in bpy.context.scene.objects if o.type == "ARMATURE"]) == 1
    assert not bpy.data.libraries and not bpy.data.images
    assert set(bpy.data.actions.keys()) == {PREFIX + name for name in CLIPS}
    assert not rig.animation_data.nla_tracks
    assert bpy.context.scene.render.fps == 24
    assert bpy.context.scene.unit_settings.system == "METRIC"
    camera = bpy.data.objects["Camera_Tactical_3Q"]
    assert camera.data.type == "ORTHO" and abs(camera.data.ortho_scale - 2.47) < 1e-5
    assert (V(camera.rotation_euler) - V((1.150829196,0,-.435386419))).length < 1e-5

    vertices, faces, weighted, cloth_shells = 0, 0, 0, 0
    source = hashlib.sha256()
    for obj in sorted(actor_objects(), key=lambda model: model.name):
        data = obj.data
        assert data.materials and len(data.vertices) and len(data.polygons), obj.name
        vertices += len(data.vertices)
        faces += len(data.polygons)
        if obj.parent == rig:
            weighted += 1
            assert all(abs(sum(group.weight for group in vertex.groups)-1) < 2e-6
                       for vertex in data.vertices), obj.name
            assert all(group.name in rig.pose.bones for group in obj.vertex_groups)
            assert any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers)
        else:
            assert obj.parent and obj.parent.name in SOCKETS, obj.name
        bm = bmesh.new()
        bm.from_mesh(data)
        shell = any(mod.type == "SOLIDIFY" for mod in obj.modifiers)
        cloth_shells += int(shell)
        assert not any(not e.is_manifold and not (shell and e.is_boundary) for e in bm.edges), obj.name
        assert not any(f.calc_area() < 1e-12 for f in bm.faces), obj.name
        bm.free()
        source.update(json.dumps([obj.name, [list(v.co) for v in data.vertices],
                                   [list(f.vertices) for f in data.polygons]]).encode())
    for name in CLIPS:
        action = bpy.data.actions[PREFIX+name]
        for channelbag in action.layers[0].strips[0].channelbags:
            for curve in channelbag.fcurves:
                source.update(json.dumps([name,curve.data_path,curve.array_index,
                                          [list(p.co) for p in curve.keyframe_points]]).encode())
    for prop, (name, _) in SOCKETS.items():
        assert bpy.data.objects[prop].parent_type == "BONE"
        assert bpy.data.objects[prop].parent_bone == name

    load_pose(rig, "Neutral T", 1)
    assert all(abs(ch) < 2e-6 for bone in rig.pose.bones for ch in bone.location)
    assert all(abs(bone.rotation_quaternion.angle) < 2e-6 for bone in rig.pose.bones)
    for side, sign in (("R",-1),("L",1)):
        for bone in ("upper_arm", "forearm", "hand"):
            pose_bone = rig.pose.bones[f"{bone}.{side}"]
            assert ((pose_bone.tail-pose_bone.head).normalized()-V((sign,0,0))).length < 2e-6
    depsgraph = bpy.context.evaluated_depsgraph_get()
    bounds = [point for obj in actor_objects() if obj.parent == rig for point in world_geometry(obj,depsgraph)]
    return {
        "bones": len(rig.data.bones), "mesh_objects": len(actor_objects()), "materials": len(bpy.data.materials),
        "base_vertices": vertices, "base_faces": faces, "weighted_meshes": weighted,
        "solidified_cloth_surfaces": cloth_shells,
        "neutral_actor_bounds_m": [round(max(p[i] for p in bounds)-min(p[i] for p in bounds), 5) for i in range(3)],
        "geometry_and_action_key_sha256": source.hexdigest(),
    }


def delta_from(rig, reference, offset=V((0,0,0))):
    return max((pb.head - reference[pb.name][0] - offset).length
               + (pb.tail - reference[pb.name][1] - offset).length for pb in rig.pose.bones if pb.name != "root")


def action_check(rig):
    result = {}
    scene = bpy.context.scene
    camera = bpy.data.objects["Camera_Tactical_3Q"]
    load_pose(rig,"Ready",1)
    ref = {pb.name: (pb.head.copy(),pb.tail.copy()) for pb in rig.pose.bones}
    foot_base = {side: rig.pose.bones["foot."+side].head.copy() for side in ("L","R")}
    soles = {side: bpy.data.objects["Layered welt " + side] for side in ("L","R")}

    for clip, last in CLIPS.items():
        action = bpy.data.actions[PREFIX + clip]
        assert tuple(action.frame_range) == (1.,float(last)), action.name
        if clip == "Neutral T":
            continue
        load_pose(rig,clip,1)
        assert delta_from(rig,ref) < 2e-5, clip
        load_pose(rig,clip,last)
        travel = rig.pose.bones["pelvis"].head - ref["pelvis"][0]
        assert delta_from(rig,ref,travel if clip == "Pursue Step" else V((0,0,0))) < .015, clip
        grip_error, planted, floor, edge = 0., 0., math.inf, math.inf
        speed, fastest = 0., None
        previous = None
        for half in range(2, last*2 + 1):
            load_pose(rig,clip,half*.5)
            for prop,(bone_name,grip) in SOCKETS.items():
                diff = bpy.data.objects[prop].matrix_world.translation - bone_point(rig,bone_name,grip)
                grip_error = max(grip_error,diff.length)
            if clip != "Pursue Step":
                planted = max(planted,max((rig.pose.bones["foot."+s].head - foot_base[s]).length for s in ("L","R")))
            else:
                # Each step has one true contact before the other toe leaves its mark.
                at = half*.5
                if at <= 13:
                    planted = max(planted,(rig.pose.bones["foot.L"].head - foot_base["L"]).length)
                else:
                    planted = max(planted,(rig.pose.bones["foot.R"].head - V((-.225,-.433,.149))).length)
            depsgraph = bpy.context.evaluated_depsgraph_get()
            floor = min(floor,min(p.z for o in soles.values() for p in world_geometry(o,depsgraph)))
            angle_joints = ("upper_arm.R","forearm.R","hand.R","upper_arm.L","forearm.L","hand.L",
                            "thigh.R","shin.R","thigh.L","shin.L")
            current = [rig.pose.bones[name].matrix.to_quaternion() for name in angle_joints]
            if previous:
                for joint, a, b in zip(angle_joints,current,previous):
                    jump = math.degrees(2*math.acos(min(1.,abs(a.dot(b)))))
                    if jump > speed:
                        speed, fastest = jump, (joint,half*.5)
            previous = current
            if half % 4 == 0 or half in (2,last*2):
                for obj in actor_objects():
                    for p in world_geometry(obj,depsgraph):
                        view = world_to_camera_view(scene,camera,p)
                        edge = min(edge,view.x,view.y,1-view.x,1-view.y)
        assert grip_error < 3e-5, (clip,grip_error)
        assert planted < .004, (clip,planted)
        assert floor > -.004, (clip,floor)
        assert edge > .018, (clip,edge)
        assert speed < 43, (clip,speed,fastest)
        result[clip] = {
            "samples": last*2-1, "max_grip_error_mm": round(grip_error*1000,4),
            "max_planted_ankle_drift_mm": round(planted*1000,4),
            "min_welt_clearance_mm":round(floor*1000,4), "min_frame_margin_percent":round(100*edge,2),
            "max_joint_degrees_per_half_frame": round(speed,2),
            "travel_m": round(travel.length,5),
        }

    # Test detaching both assembly roots in the loaded scene, never while writing the file.
    load_pose(rig,"Try This",16)
    for prop in SOCKETS:
        root = bpy.data.objects[prop]
        child = sorted(root.children, key=lambda ob: ob.name)[0]
        world, child_world = root.matrix_world.copy(), child.matrix_world.copy()
        parent, bone, basis, inverse = root.parent, root.parent_bone, root.matrix_basis.copy(), root.matrix_parent_inverse.copy()
        root.parent = None
        root.matrix_world = world
        bpy.context.view_layer.update()
        assert (child.matrix_world.translation-child_world.translation).length < 3e-5
        root.parent, root.parent_type, root.parent_bone = parent, "BONE", bone
        root.matrix_parent_inverse, root.matrix_basis = inverse, basis
        bpy.context.view_layer.update()
    return result


def render(rig, destination, ids, quick):
    scene = bpy.context.scene
    if quick:
        scene.render.resolution_percentage = 53
        scene.cycles.samples = 8
    for key in ids:
        clip, frame, view = VIEWS[key]
        load_pose(rig,clip,frame)
        scene.camera = bpy.data.objects[view]
        # The true T rest is easier to inspect without hand-mounted kit.
        for ob in actor_objects():
            if ob.parent and ob.parent.name in SOCKETS:
                ob.hide_render = clip == "Neutral T"
        target = destination / (key + ".png")
        assert not target.exists(), target
        scene.render.filepath = str(target)
        bpy.ops.render.render(write_still=True)
        assert target.stat().st_size > 4096, target
        print(f"Saved {key}: {clip}, frame {frame}, {view}", flush=True)


def render_motion(rig, out):
    scene = bpy.context.scene
    scene.camera = bpy.data.objects["Camera_Tactical_3Q"]
    scene.render.resolution_percentage = 44
    scene.render.film_transparent = True
    scene.cycles.samples = 10
    for directory, clip in (("fitting","Try This"),("hammer","Hammer Time")):
        dest = out / directory
        dest.mkdir(exist_ok=True)
        for i in range(18):
            at = min(1+i*2,CLIPS[clip])
            load_pose(rig,clip,at)
            target = dest / f"{i:03d}.png"
            assert not target.exists(), target
            scene.render.filepath = str(target)
            bpy.ops.render.render(write_still=True)
            assert target.stat().st_size > 4096, target


def main():
    out, *flags = sys.argv[sys.argv.index("--")+1:]
    output = Path(out)
    assert output.is_absolute() and bpy.data.filepath, (out,bpy.data.filepath)
    output.mkdir(parents=True,exist_ok=True)
    master = Path(bpy.data.filepath)
    before = hashlib.sha256(master.read_bytes()).hexdigest()
    rig = bpy.data.objects["HobbySmith_Rig"]
    if "--images-only" not in flags:
        results = {"master_sha256":before, "blender":bpy.app.version_string,
                   **check_structure(rig), "actions":action_check(rig)}
        (output/"checks.json").write_text(json.dumps(results,indent=2)+"\n")
        print(json.dumps(results,indent=2),flush=True)
    if "--motion" in flags:
        render_motion(rig, output)
    elif "--check-only" not in flags:
        ids = [name for name in flags if name in VIEWS] or list(VIEWS)
        render(rig,output,ids,"--quick" in flags)
    after = hashlib.sha256(master.read_bytes()).hexdigest()
    assert before == after, (master,before,after)
    print(f"Unchanged source SHA-256 {after}",flush=True)


if __name__ == "__main__":
    main()
