"""Verify or render the reopened Harpooner without saving the source."""

import argparse
from pathlib import Path
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
from pose_harpooner import CAST, END, FALL, HIT, JAB, MOVE, PREFIX, READY, RELEASE, REST, RESTORE


STILLS = (
    ("neutral",REST,1,"Camera_Neutral_Front"),
    ("back",READY,1,"Camera_Back_3Q"),
    ("ready",READY,1,"Camera_Tactical_Wide"),
    ("jab",JAB,8,"Camera_Tactical_Wide"),
    ("aim",CAST,8,"Camera_Tactical_Wide"),
    ("release",CAST,11,"Camera_Tactical_Wide"),
    ("pursue",MOVE,9,"Camera_Tactical_Wide"),
    ("hit",HIT,4,"Camera_Tactical_Wide"),
    ("defeat",FALL,22,"Camera_Tactical_Wide"),
)
MINIS = (("ready",READY,1),("jab",JAB,8),("aim",CAST,8),
         ("release",CAST,11),("pursue",MOVE,9),("defeat",FALL,22))
MOTION = {"jab":JAB,"release":CAST,"pursue":MOVE,"hit":HIT,"defeat":FALL}
V = Vector
scene = bpy.context.scene
rig = bpy.data.objects["Harpooner_Rig"]
prop = bpy.data.objects["Harpoon_Detachable"]
weapon_group = bpy.data.collections["04 · Detachable ash harpoon"]


def pose(take,frame):
    rig.animation_data.action = bpy.data.actions[PREFIX+take]
    scene.frame_set(int(frame),subframe=frame%1)


def matrix_delta(a,b):
    return max(abs(a[i][j]-b[i][j]) for i in range(4) for j in range(4))


def poses():
    return {b.name:b.matrix.copy() for b in rig.pose.bones}


def points(obj, edge_step=None):
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    result = [evaluated.matrix_world @ v.co for v in mesh.vertices]
    if edge_step is not None:
        for edge in mesh.edges:
            start,end = [result[i] for i in edge.vertices]
            segments = int((start-end).length/edge_step)+1
            result.extend(start.lerp(end,j/segments) for j in range(1,segments))
    evaluated.to_mesh_clear()
    return result


def detach():
    world = prop.matrix_world.copy()
    refs = {ob:ob.matrix_world.copy() for ob in prop.children}
    parent,kind,bone = prop.parent,prop.parent_type,prop.parent_bone
    inv,basis = prop.matrix_parent_inverse.copy(),prop.matrix_basis.copy()
    prop.parent = None
    prop.matrix_world = world
    bpy.context.view_layer.update()
    assert all(matrix_delta(ob.matrix_world,m)<.00001 for ob,m in refs.items())
    prop.parent,prop.parent_type,prop.parent_bone = parent,kind,bone
    prop.matrix_parent_inverse,prop.matrix_basis = inv,basis
    bpy.context.view_layer.update()
    assert matrix_delta(prop.matrix_world,world)<.00001


def body_clearance(weapon, name, restrict_height=False):
    # Blade/shaft bounds use actual evaluated mesh. The head/neck plane is
    # intentionally more conservative than a rendered silhouette comparison.
    body = points(bpy.data.objects[name])
    if restrict_height:
        # The Ready butt can sit farther back in Y below the ribcage;
        # compare only prop vertices within the vertical band at issue.
        floor = min(v.z for v in body)-.025
        weapon = [v for v in weapon if v.z >= floor]
        if not weapon:
            return float("inf")
    return min(v.y for v in body)-max(v.y for v in weapon)


def verify():
    assert not bpy.data.libraries and not bpy.data.images
    assert scene.unit_settings.system == "METRIC" and scene.unit_settings.scale_length == 1
    assert scene.render.fps == 24 and scene.camera.name == "Camera_Tactical_3Q"
    assert (prop.parent,prop.parent_type,prop.parent_bone)==(rig,"BONE","harpoon")
    assert not rig.animation_data.nla_tracks and len(bpy.data.actions)==len(END)
    for take,end in END.items():
        action = bpy.data.actions[PREFIX+take]
        assert action.use_fake_user and tuple(action.frame_range)==(1,end), take
    pose(REST,1)
    for bone in rig.pose.bones:
        assert matrix_delta(bone.matrix,bone.bone.matrix_local)<.00005, bone.name
    for side,sign in (("R",-1),("L",1)):
        arm = rig.pose.bones["upper_arm."+side]
        hand = rig.pose.bones["hand."+side]
        assert (hand.tail-arm.head).normalized().dot(V((sign,0,0)))>.9999
    pieces = [ob for ob in scene.objects if ob.type in {"MESH","CURVE"} and ob not in prop.children[:]]
    verts = [v for ob in pieces for v in points(ob)]
    bounds = tuple(max(v[k] for v in verts)-min(v[k] for v in verts) for k in range(3))
    print(f"Neutral body bounds {bounds[0]:.3f} × {bounds[1]:.3f} × {bounds[2]:.3f} m; "
          f"{len(rig.pose.bones)} rig bones, {len(pieces)} body parts, {len(prop.children)} prop parts")

    pose(READY,1)
    base = poses()
    detach()
    boot_floor = {}
    ankle_spread = {}
    clearances, load_clearances = [], []
    sampled = 0
    for take,end in END.items():
        if take==REST:
            continue
        low = {s:float("inf") for s in "RL"}
        drift = {s:0 for s in "RL"}
        for sample in range(2,2*end+1):
            frame = sample/2
            sampled += 1
            pose(take,frame)
            bones = rig.pose.bones
            assert matrix_delta(bones["root"].matrix,base["root"])<.00001,(take,frame)
            if frame==1 or (frame==end and take!=FALL):
                assert max(matrix_delta(m,bones[k].matrix) for k,m in base.items())<.00003,(take,frame)
            for side in "RL":
                ankle = bones["foot."+side].head
                drift[side] = max(drift[side],(ankle-base["foot."+side].translation).length)
                low[side] = min(low[side],min(v.z for v in points(bpy.data.objects["Welt and sole "+side])))
            if take==CAST and bones["harpoon"].scale.x>.99:
                shaft = points(bpy.data.objects["Single straight ash shaft"],edge_step=.01)
                tip = points(bpy.data.objects["Forged single-barb harpoon head"])
                referents = ("Tall angular face","Neck","Cutaway charcoal hood")
                depth = min(body_clearance(shaft+tip,k,restrict_height=True) for k in referents)
                clearances.append((depth,frame))
                if 3<=frame<14:
                    clearance = min(body_clearance(shaft+tip,k) for k in referents)
                    load_clearances.append((clearance,frame))
        ankle_spread[take] = max(drift.values())
        boot_floor[take] = min(low.values())
    print(f"{sampled} half-frame samples; world root stationary; Ready endpoints exact on every nonterminal action")
    print("Minimum sole height by take (mm):", {k:round(v*1000,3) for k,v in boot_floor.items()})
    print("Maximum ankle displacement by take (mm):",{k:round(v*1000,3) for k,v in ankle_spread.items()})
    assert min(boot_floor.values())>0,boot_floor
    assert max(ankle_spread[k] for k in (READY,JAB,CAST,HIT))<.015,ankle_spread
    assert ankle_spread[MOVE]>.2
    for name,samples,margin in (("full visible cast",clearances,0),("load and release",load_clearances,.015)):
        clearance,frame = min(samples)
        print(f"Minimum front depth separation for {name}: {clearance*1000:.1f} mm at f{frame:g}")
        assert clearance>margin
    pose(CAST,RELEASE)
    shaft = points(bpy.data.objects["Single straight ash shaft"])
    hand = [v for ob in scene.objects if ob.name.startswith("Finger") and ob.name.endswith(" R") for v in points(ob)]
    camera = bpy.data.objects["Camera_Tactical_Wide"]
    project_x = lambda v: world_to_camera_view(scene,camera,v).x
    gap = (min(map(project_x,shaft))-max(map(project_x,hand)))*camera.data.ortho_scale
    depth = min(v.y for v in hand)-max(v.y for v in shaft)
    print(f"Release f{RELEASE} hand-to-shaft clearance: {gap*1000:.1f} mm across camera, {depth*1000:.1f} mm forward")
    assert min(gap,depth)>.015
    pose(CAST,17)
    assert rig.pose.bones["harpoon"].scale.x<.002
    pose(CAST,RESTORE)
    assert rig.pose.bones["harpoon"].scale.x>.999
    pose(FALL,22)
    settled = poses()
    pose(FALL,25)
    assert matrix_delta(settled["pelvis"],rig.pose.bones["pelvis"].matrix)<.00001
    assert rig.pose.bones["pelvis"].head.z < base["pelvis"].translation.z-.45


def render(out,size=None,samples=12):
    if size:
        scene.render.resolution_x,scene.render.resolution_y = size
    scene.cycles.samples = samples
    scene.render.filepath = str(out)
    bpy.ops.render.render(write_still=True)


def render_poses(out):
    for name,take,frame,camera in STILLS:
        scene.camera = bpy.data.objects[camera]
        pose(take,frame)
        weapon_group.hide_render = take==REST
        render(out/f"{name}.png",(510,510),14)
    weapon_group.hide_render = False
    # Proof captures at 4× oversampling. The final 102x76 crop has the
    # documented 26.55 px/m tactical pitch and an unvarying cell anchor.
    scene.camera = bpy.data.objects["Camera_Tactical_Wide"]
    w,h = 102,76
    scene.camera.data.ortho_scale = w/26.55
    anchor_x,anchor_y = 33,67
    offset = V(((.5-anchor_x/w)*w/26.55,(anchor_y/h-.5)*h/26.55,7))
    scene.camera.location = scene.camera.rotation_euler.to_matrix() @ offset
    for name,take,frame in MINIS:
        pose(take,frame)
        render(out/f"mini-{name}.png",(4*w,4*h),8)


def render_motion(out):
    scene.camera = bpy.data.objects["Camera_Tactical_Wide"]
    for clip,take in MOTION.items():
        folder = out/clip
        folder.mkdir(exist_ok=True)
        frames = list(range(1,END[take]+1,2))
        if take==CAST:
            # Keep the new release beat inspectable between anticipation and follow-through.
            assert RELEASE in frames
        for i,frame in enumerate(frames,1):
            pose(take,frame)
            render(folder/f"{i:03d}.png",(300,300),7)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode",choices=("check","poses","motion"))
    parser.add_argument("out",type=Path,nargs="?")
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    if args.mode=="check":
        verify()
        return
    if args.out is None:
        parser.error("rendering requires an output directory")
    args.out.mkdir(parents=True,exist_ok=True)
    (render_poses if args.mode=="poses" else render_motion)(args.out)


if __name__=="__main__":
    main()
