"""Reopen the Rogue in Blender and check/render the saved candidate. Does not save."""

import argparse
from pathlib import Path
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector
from mathutils.bvhtree import BVHTree


PREFIX = "Rogue | "
REST, READY, DODGE, ALIBI = "Neutral T", "Ready / Retreat", "Confusing Dodge", "Wasn't Me"
TAKES = {READY: (29, "retreat"), DODGE: (37, "dodge"), ALIBI: (53, "alibi")}
STILLS = (
    ("neutral", REST, 1, "Camera_Neutral_Front"),
    ("retreat", READY, 13, "Camera_Tactical_3Q"),
    ("dodge", DODGE, 10, "Camera_Tactical_3Q"),
    ("alibi", ALIBI, 25, "Camera_Tactical_3Q"),
    ("detail-face", ALIBI, 25, "Camera_Face_Detail"),
    ("detail-cape", DODGE, 12, "Camera_Turn_Back"),
)
MINIS = (
    ("retreat", READY, 13),
    ("dodge", DODGE, 10),
    ("cross-plant", DODGE, 12),
    ("alibi", ALIBI, 25),
)
OBJECTS = bpy.data.objects
CAPE_PARTS = ("Asymmetrical midnight half-cape", "Doubled teal shoulder fold")
MOUNTS = (("Keys_L_Detachable", "keys_mount.L"), ("Punch_R_Detachable", "punch_mount.R"))
FINGERS = ("Index", "Middle", "Ring", "Little", "Thumb")
FLEXIBLE_HANGERS = {"Brass key ring belt tab", "Ticket punch leather hanger"}


def pose(scene, rig, action, frame):
    rig.animation_data.action = bpy.data.actions[PREFIX + action]
    scene.frame_set(int(frame), subframe=frame % 1)


def geometry(name, deps):
    ob = OBJECTS[name].evaluated_get(deps)
    me = ob.to_mesh()
    verts = [ob.matrix_world @ v.co for v in me.vertices]
    faces = [tuple(p.vertices) for p in me.polygons]
    ob.to_mesh_clear()
    return verts, faces


def max_delta(a,b):
    return max(abs(a[i][j]-b[i][j]) for i in range(4) for j in range(4))


def snapshot(rig):
    return {p.name: p.matrix.copy() for p in rig.pose.bones}


def compare(a,b):
    return max(max_delta(m,b[name]) for name,m in a.items())


def check_detach(obj):
    """Check a keep-transform detach of the entire assembly in memory."""
    bpy.context.view_layer.update()
    root = OBJECTS[obj]
    parent,kind,bone = root.parent,root.parent_type,root.parent_bone
    parent_inverse,basis = root.matrix_parent_inverse.copy(),root.matrix_basis.copy()
    world = root.matrix_world.copy()
    attached = [(child,child.matrix_world.copy()) for child in root.children]
    root.parent = None
    root.matrix_world = world
    bpy.context.view_layer.update()
    assert all(child.parent == root and max_delta(child.matrix_world,m)<.0001 for child,m in attached)
    root.parent,root.parent_type,root.parent_bone = parent,kind,bone
    root.matrix_parent_inverse,root.matrix_basis = parent_inverse,basis
    bpy.context.view_layer.update()
    assert max_delta(root.matrix_world,world)<.0001


def check(scene, rig):
    assert scene.camera.name == "Camera_Tactical_3Q"
    assert abs(scene.camera.data.ortho_scale - 2.47) < .0001
    assert all(abs(a-b)<.0001 for a,b in zip(scene.camera.rotation_euler,(1.1508292,0,-.4353864)))
    assert scene.unit_settings.system == "METRIC" and scene.unit_settings.scale_length == 1
    assert scene.render.fps == 24 and scene.frame_current == 1
    assert rig.animation_data.action.name == PREFIX + READY
    assert not bpy.data.libraries and not bpy.data.images
    assert len(bpy.data.actions) == 4 and not rig.animation_data.nla_tracks
    for take in (REST,*TAKES):
        ac = bpy.data.actions[PREFIX + take]
        assert ac.use_fake_user and ac.frame_range[:] == (1.,float(TAKES.get(take,(1,))[0]))
    assert len(OBJECTS[CAPE_PARTS[0]].data.shape_keys.key_blocks) == 3
    assert len(OBJECTS[CAPE_PARTS[0]].data.shape_keys.animation_data.drivers) == 2
    bones = rig.pose.bones
    for obj,name in MOUNTS:
        ob = OBJECTS[obj]
        assert (ob.parent,ob.parent_type,ob.parent_bone) == (rig,"BONE",name)
        assert bones[name].parent.name == "pelvis" and len(ob.children) >= 7
    actors = [o.name for o in scene.objects if o.type in {"MESH","CURVE"} and o.name!="Paper ground Z=0"]
    assert all(OBJECTS[n].parent for n in actors)
    deps = bpy.context.evaluated_depsgraph_get()
    pose(scene,rig,REST,1)
    for b in bones:
        assert max_delta(b.matrix,b.bone.matrix_local) < .0001, b.name
    for side,s in (("L",1),("R",-1)):
        assert (bones["hand."+side].tail-bones["upper_arm."+side].head).normalized().dot(Vector((s,0,0))) > .999
    verts = [v for n in actors for v in geometry(n,deps)[0]]
    bounds = tuple(max(v[i] for v in verts)-min(v[i] for v in verts) for i in range(3))
    print(f"Model: {len(bones)} bones, {len(actors)} editable mesh/curve pieces; "
          f"neutral bounds {bounds[0]:.3f} × {bounds[1]:.3f} × {bounds[2]:.3f} m")
    print(f"Neutral review floor: {min(v.z for v in verts)*1000:.2f} mm minimum Z")
    pose(scene,rig,READY,1)
    start = snapshot(rig)
    mount_refs = {obj:bones[name].matrix.inverted() @ OBJECTS[obj].matrix_world for obj,name in MOUNTS}
    for obj,_ in MOUNTS:
        check_detach(obj)
    hold = None
    floor = {side:[float("inf"),0.] for side in "LR"}
    mount_drift = root_drift = pose_drift = plant_drift = integer_drift = 0.
    root_floor = start["root"].translation
    max_hip = 0.
    collisions = {}
    kit_contacts = {}
    finger_gaps = {}
    shoe_overlaps = []
    hardware = {
        side: [child.name for child in OBJECTS[name].children if child.name not in FLEXIBLE_HANGERS]
        for side,(name,_) in zip("LR",MOUNTS)
    }
    checks = {
        READY: {"R": ((1,29),), "L": ((13,17),)},
        DODGE: {"L": ((1,12),(19,25)), "R": ((1,4),(12,19))},
        ALIBI: {"L": ((9,41),), "R": ((14,36),)},
    }
    for take,(end,_) in TAKES.items():
        plant_refs = {}
        for i in range(2,2*end+1):
            f = i/2
            pose(scene,rig,take,f)
            if f in (1,end):
                pose_drift = max(pose_drift,compare(start,snapshot(rig)))
                assert rig["cape_usher"] == rig["cape_flash"] == 0.
            root_drift = max(root_drift,(bones["root"].head-root_floor).length)
            max_hip = max(max_hip,(bones["pelvis"].head.xy-start["pelvis"].translation.xy).length)
            for obj,name in MOUNTS:
                mount_drift = max(mount_drift,max_delta(mount_refs[obj],
                    bones[name].matrix.inverted() @ OBJECTS[obj].matrix_world))
            for side in "LR":
                sole = geometry("Soft shoe sole • "+side,deps)[0]
                lo = min(v.z for v in sole)
                floor[side][0] = min(floor[side][0],lo)
                floor[side][1] = max(floor[side][1],lo)
                for start_frame,end_frame in checks[take][side]:
                    if start_frame <= f <= end_frame:
                        loc = bones["foot."+side].head.copy()
                        ref = plant_refs.setdefault((side,start_frame),loc)
                        drift = (loc-ref).length
                        plant_drift = max(plant_drift,drift)
                        if f.is_integer():
                            integer_drift = max(integer_drift,drift)
            if take == ALIBI and 14 <= f <= 36:
                if hold is None:
                    hold=snapshot(rig)
                assert compare(hold,snapshot(rig)) < .00001 and abs(rig["cape_usher"]-1)<.00001
            cape_parts = [BVHTree.FromPolygons(*geometry(n,deps)) for n in CAPE_PARTS]
            soles = [BVHTree.FromPolygons(*geometry("Soft shoe sole • "+s,deps)) for s in "LR"]
            if soles[0].overlap(soles[1]):
                shoe_overlaps.append((take,f))
            # Intentional shoulder yoke contact is not in this check.
            for side in "LR":
                prop_shapes = {n:BVHTree.FromPolygons(*geometry(n,deps)) for n in hardware[side]}
                for name in ("Forearm","Palm shell",*FINGERS,"Twill breeches"):
                    ob_name = name+" • "+side
                    verts,faces=geometry(ob_name,deps)
                    arm = BVHTree.FromPolygons(verts,faces)
                    if name != "Twill breeches" and any(cape.overlap(arm) for cape in cape_parts):
                        collisions.setdefault(ob_name,[]).append((take,f))
                    for part,prop_shape in prop_shapes.items():
                        if prop_shape.overlap(arm):
                            kit_contacts.setdefault((part,ob_name),[]).append((take,f))
                    if name=="Palm shell":
                        gap=min(cape.find_nearest(v)[3] for v in verts for cape in cape_parts)
                        finger_gaps[ob_name]=min(finger_gaps.get(ob_name,float("inf")),gap)
    print(f"Verification: {sum(2*n-1 for n,_ in TAKES.values())} half-frame samples across acting takes")
    print(f"Endpoint matrix delta {pose_drift:.7f}; root translation {root_drift*1000:.4f} mm; "
          f"hip travel {max_hip*100:.1f} cm; mount matrix delta {mount_drift:.7f}; "
          f"planted ankle drift {plant_drift*1000:.4f} mm at half-frames, {integer_drift*1000:.4f} mm at integer frames")
    print("Sole heights: "+", ".join(f"{s} {lo*1000:.2f}–{hi*1000:.2f} mm" for s,(lo,hi) in floor.items()))
    print("Cape / forearm and hand surface overlaps:", collisions or "none")
    print("Cape / closest sampled palm vertex:",
          ", ".join(f"{n} {d*1000:.2f} mm" for n,d in finger_gaps.items()))
    print("Sole mesh intersections:",shoe_overlaps or "none")
    print("Hard kit / same-side twill and hand surface overlaps:",kit_contacts or "none")
    assert pose_drift < .0001 and root_drift < .0001
    assert mount_drift < .0001 and plant_drift < .0002
    assert max_hip < .28
    assert min(floor[s][0] for s in "LR") >= .002
    pose(scene,rig,DODGE,4)
    load = bones["pelvis"].head.z
    pose(scene,rig,DODGE,10)
    swing = bones["foot.R"].head.copy()
    assert swing.x > bones["foot.L"].head.x and swing.y < bones["foot.L"].head.y-.35
    assert bones["pelvis"].head.z < load - .085 and abs(rig["cape_flash"]-1)<.0001
    cape_keys = OBJECTS[CAPE_PARTS[0]].data.shape_keys.key_blocks
    assert abs(cape_keys["Dodge | throw lining"].value-1)<.0001
    print(f"Dodge f10: crossing ankle passes {100*(swing.x-bones['foot.L'].head.x):.1f} cm "
          f"across stance ankle and sits {100*(swing.z-.108):.1f} cm off its floor height; "
          f"pelvis drops {100*(load-bones['pelvis'].head.z):.1f} cm from loading")
    pose(scene,rig,ALIBI,25)
    assert abs(cape_keys["Alibi | usher drape"].value-1)<.0001
    heels = [OBJECTS["Soft shoe sole • "+s].matrix_world @ Vector((sign*.118,.069,.029))
             for s,sign in (("L",1),("R",-1))]
    assert (heels[0]-heels[1]).length < .12
    palm_up = -(bones["hand.L"].matrix.to_3x3()@Vector((0,0,1))).z
    assert palm_up>.55
    neutral = rig.data.bones["chest"].matrix_local.inverted() @ Vector((.048,-.133,1.34))
    chest = bones["chest"].matrix @ neutral
    assert (chest-bones["hand.R"].tail).length < .15
    print(f"Alibi f14–36: constant full-rig hold; heel-center separation {(heels[0]-heels[1]).length*100:.1f} cm; "
          f"palm normal up component {palm_up:.2f}")
    for _,take,f,camera in STILLS:
        if camera not in ("Camera_Tactical_3Q", "Camera_Neutral_Front"):
            continue
        pose(scene,rig,take,f)
        cam=OBJECTS[camera]
        coords = [world_to_camera_view(scene,cam,v) for n in actors
                  for v in geometry(n,deps)[0][::5]]
        assert all(.01 <= p.x <= .99 and .01 <= p.y <= .99 for p in coords), (take,f)
    return collisions or shoe_overlaps or kit_contacts


def render(scene, rig, path, take, f, camera, w, h, samples):
    pose(scene,rig,take,f)
    scene.camera=OBJECTS[camera]
    scene.cycles.samples = samples
    scene.render.resolution_x, scene.render.resolution_y = w,h
    scene.render.filepath=str(path)
    bpy.ops.render.render(write_still=True)
    assert path.is_file() and path.stat().st_size>100


def main():
    p=argparse.ArgumentParser()
    p.add_argument("output",type=Path)
    p.add_argument("--check-only",action="store_true")
    p.add_argument("--render-only",action="store_true")
    p.add_argument("--motion",action="store_true")
    opt=p.parse_args(sys.argv[sys.argv.index("--")+1:])
    scene,rig=bpy.context.scene,OBJECTS["Rogue_Rig"]
    if not opt.render_only:
        collisions=check(scene,rig)
        assert not collisions, "Inspect cape, shoes or kit clearance."
    if opt.check_only:
        return
    dst=opt.output.resolve()
    dst.mkdir(parents=True,exist_ok=True)
    if opt.motion:
        for take,(end,slug) in TAKES.items():
            for f in range(1,end,2):
                render(scene,rig,dst/f"{slug}-{(f-1)//2:02d}.png",take,f,
                       "Camera_Tactical_3Q",252,222,7)
        return
    for n,take,f,cam in STILLS:
        render(scene,rig,dst/(n+".png"),take,f,cam,620,600,24)
    for n,take,f in MINIS:
        render(scene,rig,dst/(n+"-native.png"),take,f,"Camera_Tactical_3Q",65,54,32)


if __name__=="__main__":
    main()
