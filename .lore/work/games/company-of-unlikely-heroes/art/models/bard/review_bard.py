"""Read-only verification and review renders from the saved Bard."""

import argparse
import math
from pathlib import Path
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector
from mathutils.bvhtree import BVHTree


PREFIX = "Bard | "
REST, READY, MELODY, SONNET = "Neutral T", "Ready Count-In", "Inspiring Melody", "Healing Sonnet"
TAKES = {READY: (25, "count-in"), MELODY: (49, "melody"), SONNET: (61, "sonnet")}
STILLS = (
    ("ready", READY, 13),
    ("melody", MELODY, 13),
    ("melody-answer", MELODY, 34),
    ("sonnet", SONNET, 25),
    ("sonnet-breath", SONNET, 46),
)
PROPS = ("04 • Fiddle | detachable", "05 • Bow | detachable")
PROP_ROOTS = {
    "Fiddle_L_Detachable": ("fiddle_mount.L", "chest"),
    "Bow_R_Detachable": ("bow_mount.R", "hand.R"),
}


def set_pose(scene, rig, take, frame, subframe=0.):
    rig.animation_data.action = bpy.data.actions[PREFIX + take]
    scene.frame_set(frame, subframe=subframe)


def position(name):
    return bpy.data.objects[name].matrix_world.translation.copy()


def difference(a, b):
    return max(abs(a[i][j] - b[i][j]) for i in range(4) for j in range(4))


def closest_on_segment(point, start, end):
    edge = end - start
    t = (point - start).dot(edge) / edge.length_squared
    return (point - start.lerp(end, max(0., min(1., t)))).length, t * edge.length


def base_bvh(o):
    return BVHTree.FromPolygons([o.matrix_world @ v.co for v in o.data.vertices],
                               [tuple(p.vertices) for p in o.data.polygons])


def check(scene, rig):
    poses = rig.pose.bones
    assert scene.camera.name == "Camera_Tactical_3Q"
    assert abs(scene.camera.data.ortho_scale - 2.47) < .0001
    assert all(abs(a-b)<.0001 for a, b in zip(scene.camera.rotation_euler, (1.1508292,0,-.4353864)))
    assert scene.unit_settings.system == "METRIC" and scene.unit_settings.scale_length == 1
    assert scene.render.fps == 24 and scene.frame_current == 1
    assert rig.animation_data.action.name == PREFIX + READY
    assert not bpy.data.libraries and not bpy.data.images
    assert len(bpy.data.actions) == 4 and not rig.animation_data.nla_tracks
    assert all(bpy.data.actions[PREFIX + a].use_fake_user for a in (REST,*TAKES))
    assert all(bpy.data.actions[PREFIX+a].frame_range[:] == (1.,float(n)) for a,(n,_) in TAKES.items())
    for name,(mount,parent) in PROP_ROOTS.items():
        obj = bpy.data.objects[name]
        assert (obj.parent,obj.parent_type,obj.parent_bone)==(rig,"BONE",mount)
        assert poses[mount].parent.name == parent and len(obj.children) > 10

    set_pose(scene, rig, REST, 1)
    for p in poses:
        assert difference(p.matrix,p.bone.matrix_local)<.0001, p.name
    for side, sign in (("L",1),("R",-1)):
        for stem in ("upper_arm","forearm","hand"):
            p=poses[f"{stem}.{side}"]
            assert (p.tail-p.head).normalized().dot(Vector((sign,0,0)))>.9999, p.name
    for name in ("Sleeve • cut and crumpled L","Sleeve • cut and crumpled R",
                 "Breeches • deep folded knee L","Breeches • deep folded knee R"):
        assert any(m.type=="ARMATURE" and m.object==rig for m in bpy.data.objects[name].modifiers)
    actor=[o for o in scene.objects if o.type in {"MESH","CURVE"} and any(
        c.name.startswith(("01","02","03")) for c in o.users_collection)]
    deps=bpy.context.evaluated_depsgraph_get()
    corners=[]
    for item in actor:
        o=item.evaluated_get(deps)
        evaluated_mesh=o.to_mesh()
        corners.extend(o.matrix_world@v.co for v in evaluated_mesh.vertices)
        o.to_mesh_clear()
    bounds=tuple(max(p[i] for p in corners)-min(p[i] for p in corners) for i in range(3))
    assert 1.95 < bounds[2] < 2.07, bounds
    print("Neutral body width/depth/height m:",tuple(round(d,3) for d in bounds),
          f"| {len(poses)} bones | {len(actor)} body parts")

    feet={s:bpy.data.objects[f"Boot sole {s}"] for s in ("L","R")}
    clearance_names=("Face • broad sculpted head","Jaw • moving chin and lower lip plane",
                     "Face • bulb of nose","Waistcoat • broad belly and fitted shoulder")
    shell_names=("Fiddle • carved spruce belly","Fiddle • maple ribs","Fiddle • two piece back",
                 "Bow • tapered sprung pernambuco")
    overlap={}
    floor=math.inf
    flight=0.
    drift=0.
    grip_proximity={"L":0.,"R":0.}
    grip_drift=0.
    ready=None
    trajectories={}
    chin_gaps=[]
    chin_surface_gaps=[]
    pressure_error=0.
    fingertip_error=0.
    for take,(length,_) in TAKES.items():
        set_pose(scene,rig,take,1)
        if ready is None:
            ready={p.name:p.matrix.copy() for p in poses}
        plants={s:poses[f"foot.{s}"].matrix.copy() for s in feet}
        mount_offsets={name:poses[mount].matrix.inverted()@bpy.data.objects[name].matrix_world
                       for name,(mount,_) in PROP_ROOTS.items()}
        bow_samples={}
        prev_mouth=0.
        for sample in range(2,2*length+1):
            frame=sample//2
            set_pose(scene,rig,take,frame,(sample%2)*.5)
            if sample in (2,2*length):
                for p in poses:
                    assert difference(p.matrix,ready[p.name])<.00015,(take,frame,p.name)
            for side,foot in feet.items():
                sole=min((foot.matrix_world@v.co).z for v in foot.data.vertices)
                floor=min(floor,sole)
                if side=="R" or take!=MELODY or frame<5 or 46<=frame:
                    drift=max(drift,difference(poses[f"foot.{side}"].matrix,plants[side]))
                if side=="L" and take==MELODY:
                    flight=max(flight,sole)
            for name,(mount,_) in PROP_ROOTS.items():
                mount_now=poses[mount].matrix@mount_offsets[name]
                grip_drift=max(grip_drift,difference(bpy.data.objects[name].matrix_world,mount_now))
            contact=position("String_contact")
            hair_start=position("Bow_hair_frog")
            hair_end=position("Bow_hair_tip")
            dist, travel=closest_on_segment(contact,hair_start,hair_end)
            press=(take==MELODY and 8<=frame<41) or (take==SONNET and 11<=frame<38)
            if press:
                assert dist < .0015 and .13 < travel < .69, (take,frame,dist,travel)
                pressure_error=max(dist,pressure_error)
            if frame in (1,length) or take==READY:
                assert dist>.042,(take,frame,dist)
            if sample%2==0:
                bow_samples[frame]=travel
                shapes={n:base_bvh(bpy.data.objects[n]) for n in (*clearance_names,*shell_names)}
                for prop in shell_names:
                    for part in clearance_names:
                        if shapes[prop].overlap(shapes[part]):
                            overlap.setdefault((prop,part),[]).append((take,frame))
                for part in shell_names[:-1]:
                    if shapes[part].overlap(shapes[shell_names[-1]]):
                        overlap.setdefault((part,shell_names[-1]),[]).append((take,frame))
                for prop,side in (("Fingering_anchor","L"),("Bow_grip","R")):
                    palm=poses[f"hand.{side}"]
                    d=(palm.matrix@Vector((0,.051,0))-position(prop)).length
                    grip_proximity[side]=max(grip_proximity[side],d)
                chin_point=poses["jaw"].matrix@poses["jaw"].bone.matrix_local.inverted()@Vector((.069,-.101,1.654))
                seat=position("Chinrest_anchor")
                chin_gaps.append((chin_point-seat).length)
                chin_surface_gaps.append(min(shapes[name].find_nearest(seat)[3] for name in clearance_names[:2]))
                for prop,bone,local in (("Fiddle_L_Detachable","thumb_tip.L",(.477,-.022,.023)),
                                        ("Bow_R_Detachable","thumb_tip.R",(-.024,.006,-.005)),
                                        ("Bow_R_Detachable","middle_tip.R",(.010,-.008,-.008))):
                    target=bpy.data.objects[prop].matrix_world@Vector(local)
                    fingertip_error=max(fingertip_error,(poses[bone].tail-target).length)
                prev_mouth=max(prev_mouth,poses["sing"].scale.y)
        trajectories[take]=bow_samples
        assert (prev_mouth>.94) if take==SONNET else (prev_mouth<.25), (take,prev_mouth)

    assert .010 < floor < .015, floor
    assert flight > .24 and drift < .00015, (flight,drift)
    assert grip_drift < .00015 and max(grip_proximity.values()) < .060, (grip_drift,grip_proximity)
    assert fingertip_error < .003, fingertip_error
    m=trajectories[MELODY]
    assert all(abs(m[a]-m[b])>.11 for a,b in zip((13,17,21,25,29,34),(17,21,25,29,34,38)))
    s=trajectories[SONNET]
    assert s[38]-s[12]>.39 and all(s[i+1]>=s[i]-.0002 for i in range(12,38))
    print("Loop/endpoints and mounts pass at half-frame sampling. Foot anchor max drift:",
          round(1000*drift,3),"mm; floor minimum:",round(1000*floor,2),"mm; left boot rise:",round(flight,3),"m")
    print(f"Melody: six alternating strokes > 11 cm; Sonnet sustained draw: {s[38]-s[12]:.3f} m.")
    print("Hair/string sample max error:",round(1000*pressure_error,3),
          "mm | selected fingertip target max error:", round(1000*fingertip_error,3), "mm")
    print("Chinrest to nearest head/jaw surface range mm:",tuple(round(1000*d,1) for d in (
        min(chin_surface_gaps),max(chin_surface_gaps))))
    assert max(chin_gaps)<.06 and max(chin_surface_gaps)<.038, (max(chin_gaps),max(chin_surface_gaps))
    for pair, frames in overlap.items():
        print("BVH base mesh contact:",pair,len(frames),"samples; examples",frames[:4])
    assert not overlap, "Prop and face, waistcoat, or fiddle base surfaces crossed."

    for name,(mount,_) in PROP_ROOTS.items():
        set_pose(scene,rig,MELODY,1)
        prop=bpy.data.objects[name]
        old_offset=prop.matrix_parent_inverse.copy()
        old_basis=prop.matrix_basis.copy()
        before=prop.matrix_world.copy()
        children=tuple(prop.children)
        probe=children[0].matrix_world.copy()
        prop.parent=None
        prop.matrix_world=before
        set_pose(scene,rig,MELODY,34)
        assert difference(prop.matrix_world,before)<.0001 and difference(children[0].matrix_world,probe)<.0001
        prop.parent,prop.parent_type,prop.parent_bone=rig,"BONE",mount
        prop.matrix_parent_inverse=old_offset
        prop.matrix_basis=old_basis
    print("Both detach roots and their children passed in-memory detach probe.")


def render(scene, rig, out, mode, quick):
    out.mkdir(parents=True,exist_ok=True)
    camera=bpy.data.objects["Camera_Tactical_3Q"]

    def write(path,take,frame,cam=None,size=(480,500),props=True,framing=True):
        set_pose(scene,rig,take,frame)
        scene.camera=bpy.data.objects[cam] if cam else camera
        for c in PROPS:
            bpy.data.collections[c].hide_render=not props
        scene.render.resolution_x,scene.render.resolution_y=size
        if framing:
            for obj in (bpy.data.objects[name] for name in
                ("Bow • tapered sprung pernambuco","Fiddle • carved spruce belly","Boot sole L","Boot sole R")):
                view=[world_to_camera_view(scene,scene.camera,obj.matrix_world@v.co) for v in obj.data.vertices]
                assert all(.025<p.x<.975 and .018<p.y<.982 for p in view),(take,frame,obj.name)
        scene.render.filepath=str(path)
        bpy.ops.render.render(write_still=True)

    if mode=="stills":
        scene.cycles.samples=8 if quick else 24
        for name,take,frame in STILLS:
            write(out/(name+".png"),take,frame)
        for name,cam in (("rest","Camera_Neutral_Front"),("back","Camera_Back_Diagnostic")):
            write(out/(name+".png"),REST,1,cam=cam,props=False,framing=False)
        for take,frame,name in ((MELODY,13,"melody"),(SONNET,25,"sonnet")):
            write(out/(name+"-detail.png"),take,frame,cam="Camera_Instrument_Diagnostic",
                  size=(620,440),framing=False)
    else:
        scene.cycles.samples=5 if quick else 7
        for take,(length,slug) in TAKES.items():
            if mode not in ("motion",slug):
                continue
            seq=out/slug
            seq.mkdir(exist_ok=True)
            # The action stores an identical closing pose. Omit that duplicate in the preview.
            for index,frame in enumerate(range(1,length,2)):
                write(seq/f"{index:03d}.png",take,frame,size=(288,300))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output",type=Path,nargs="?")
    parser.add_argument("--check-only",action="store_true")
    parser.add_argument("--render-only",action="store_true")
    parser.add_argument("--quick",action="store_true")
    parser.add_argument("--mode",choices=("stills","motion",*(slug for _,slug in TAKES.values())),default="stills")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    scene=bpy.context.scene
    rig=bpy.data.objects["Bard_Rig"]
    if not args.render_only:
        check(scene,rig)
    if not args.check_only:
        if args.output is None:
            parser.error("supply an output directory")
        render(scene,rig,args.output.resolve(),args.mode,args.quick)


if __name__=="__main__":
    main()
